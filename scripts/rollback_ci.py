#!/usr/bin/env python3
"""Scope OMP-2 CI and validate one aggregate reusable success pointer."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[1]
GATE_CONTRACT = 4
FINGERPRINT_FORMAT = 1
POINTER_FORMAT = 2
MAX_POINTER_BYTES = 16 * 1024
MAX_ARTIFACT_BYTES = 10 * 1024 * 1024
WORKFLOW_PATH = ".github/workflows/ci.yml"
HEX_DIGEST = re.compile(r"^[0-9a-f]{64}$")
ARTIFACT_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
GIT_REVISION = re.compile(r"^[0-9a-f]{40}$")
RUN_ID = re.compile(r"^[1-9][0-9]*$")
SAFE_ID = re.compile(r"^[A-Za-z0-9._-]+$")

# This is the cumulative anti-bypass boundary. The manifest is included in the
# digest and this script is one of its pathspecs, so changing the boundary
# always invalidates old evidence.
ROLLBACK_PATHS = (
    WORKFLOW_PATH,
    "conf.lua",
    "main.lua",
    "core",
    "data",
    "game",
    "sim",
    "scripts/browser_determinism.py",
    "scripts/browser_matrix.py",
    "scripts/browser_matrix-requirements.txt",
    "scripts/browser_storage_host.js",
    "scripts/check_rollback.sh",
    "scripts/rollback_ci.py",
    "scripts/rollback_validation.py",
    "scripts/web_build.py",
    "scripts/web_build.sh",
    "scripts/web_serve.py",
    "scripts/webrtc_proof_host.js",
    "scripts/webrtc_proof_runner.js",
    "scripts/webrtc_proof_suite.js",
)

EXPECTED_JOB_STEPS = {
    "OMP-2 rollback impact filter": ("Detect rollback-impacting changes",),
    "OMP-2 rollback native": (
        "Run isolated native matrix, late-window, and persistent soak",
        "Upload native rollback evidence",
    ),
    "OMP-2 rollback browser matrix (chrome)": (
        "Run complete and stress browser validation",
        "Upload browser rollback evidence",
    ),
    "OMP-2 rollback browser matrix (firefox)": (
        "Run complete and stress browser validation",
        "Upload browser rollback evidence",
    ),
    "OMP-2 rollback browser soak (chrome)": (
        "Run persistent browser memory soak",
        "Upload browser rollback evidence",
    ),
    "OMP-2 rollback browser soak (firefox)": (
        "Run persistent browser memory soak",
        "Upload browser rollback evidence",
    ),
    "OMP-2 rollback gate": ("Require scoped rollback evidence",),
}

LONG_JOB_NAMES = frozenset(EXPECTED_JOB_STEPS) - {
    "OMP-2 rollback impact filter",
    "OMP-2 rollback gate",
}

EXPECTED_ARTIFACTS = frozenset(
    {
        "omp2-rollback-native",
        "omp2-rollback-chrome-matrix",
        "omp2-rollback-firefox-matrix",
        "omp2-rollback-chrome-soak",
        "omp2-rollback-firefox-soak",
    }
)

POINTER_KEYS = frozenset(
    {
        "artifacts",
        "base_ref",
        "base_repository",
        "base_sha",
        "conclusion",
        "fingerprint",
        "format_version",
        "gate_contract",
        "head_branch",
        "platform",
        "pr_number",
        "producer_revision",
        "producer_run_attempt",
        "producer_run_id",
        "repository",
        "workflow_id",
        "workflow_path",
    }
)

ARTIFACT_RECORD_KEYS = frozenset({"digest", "size_in_bytes"})


class DecisionError(RuntimeError):
    """A deterministic scope or evidence decision could not be established."""


@dataclass(frozen=True)
class ScopeDecision:
    run: bool
    reuse_allowed: bool
    fingerprint: str
    reason: str
    changed_paths: tuple[str, ...]


@dataclass(frozen=True)
class PointerContext:
    fingerprint: str
    platform: str
    gate_contract: int
    repository: str
    pr_number: int
    head_branch: str
    base_repository: str
    base_ref: str
    base_sha: str


def run_git(repo: Path, arguments: Sequence[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", *arguments],
        cwd=repo,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def require_git(repo: Path, arguments: Sequence[str]) -> bytes:
    completed = run_git(repo, arguments)
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", errors="replace").strip()
        raise DecisionError(message or f"git {' '.join(arguments)} failed")
    return completed.stdout


def relevant_fingerprint(repo: Path, revision: str = "HEAD") -> str:
    records = require_git(
        repo,
        ["ls-tree", "-r", "-z", "--full-tree", revision, "--", *ROLLBACK_PATHS],
    )
    digest = hashlib.sha256()
    digest.update(f"galactic-cup/omp2-relevant-content/v{FINGERPRINT_FORMAT}\0".encode())
    for pathspec in ROLLBACK_PATHS:
        digest.update(pathspec.encode("utf-8"))
        digest.update(b"\0")
    digest.update(records)
    return digest.hexdigest()


def valid_comparison_base(repo: Path, revision: str) -> bool:
    if not revision or set(revision) == {"0"}:
        return False
    return run_git(repo, ["cat-file", "-e", f"{revision}^{{commit}}"]).returncode == 0


def compare_relevant_paths(
    repo: Path, revision_range: str
) -> tuple[int, tuple[str, ...]]:
    quiet = run_git(repo, ["diff", "--quiet", revision_range, "--", *ROLLBACK_PATHS])
    if quiet.returncode != 1:
        return quiet.returncode, ()
    names = run_git(repo, ["diff", "--name-only", revision_range, "--", *ROLLBACK_PATHS])
    if names.returncode != 0:
        return 2, ()
    return 1, tuple(
        line
        for line in names.stdout.decode("utf-8", errors="surrogateescape").splitlines()
        if line
    )


def decide_scope(
    repo: Path,
    event_name: str,
    event_before: str = "",
    pr_base_sha: str = "",
) -> ScopeDecision:
    fingerprint = "unavailable"
    fingerprint_error = ""
    try:
        fingerprint = relevant_fingerprint(repo)
    except DecisionError as error:
        fingerprint_error = str(error)

    if event_name == "workflow_dispatch":
        return ScopeDecision(
            True,
            False,
            fingerprint,
            "manual dispatch always runs the complete campaign",
            (),
        )
    if event_name == "pull_request":
        base = pr_base_sha
        separator = "..."
    elif event_name == "push":
        base = event_before
        separator = ".."
    else:
        return ScopeDecision(
            True,
            False,
            fingerprint,
            f"unsupported event {event_name!r}; fail-open full campaign",
            (),
        )

    if not valid_comparison_base(repo, base):
        return ScopeDecision(
            True,
            False,
            fingerprint,
            "comparison commit unavailable; fail-open full campaign",
            (),
        )

    revision_range = f"{base}{separator}HEAD"
    status, changed_paths = compare_relevant_paths(repo, revision_range)
    if status == 0:
        return ScopeDecision(
            False,
            False,
            fingerprint,
            f"no rollback-impacting changes in {revision_range}",
            (),
        )
    if status > 1:
        return ScopeDecision(
            True,
            False,
            fingerprint,
            f"comparison failed for {revision_range}; fail-open full campaign",
            (),
        )
    if fingerprint_error:
        return ScopeDecision(
            True,
            False,
            fingerprint,
            f"fingerprint failed ({fingerprint_error}); fail-open full campaign",
            changed_paths,
        )
    return ScopeDecision(
        True,
        event_name == "pull_request",
        fingerprint,
        f"rollback-impacting changes found in {revision_range}",
        changed_paths,
    )


def write_github_output(path: Path | None, values: dict[str, str]) -> None:
    if path is None:
        return
    with path.open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            if "\n" in key or "\n" in value:
                raise ValueError("GitHub outputs must be single-line values")
            handle.write(f"{key}={value}\n")


def cache_context_digest(arguments: argparse.Namespace) -> str:
    identity = {
        "base_ref": arguments.base_ref,
        "base_repository": arguments.base_repository,
        "base_sha": arguments.base_sha,
        "gate_contract": arguments.gate_contract,
        "head_branch": arguments.head_branch,
        "platform": arguments.platform,
        "pr_number": arguments.pr_number,
        "repository": arguments.repository,
    }
    encoded = json.dumps(identity, separators=(",", ":"), sort_keys=True).encode()
    return hashlib.sha256(encoded).hexdigest()


def duplicate_safe_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate field {key!r}")
        result[key] = value
    return result


def load_pointer(path: Path) -> tuple[dict[str, Any] | None, str]:
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except FileNotFoundError:
        return None, "aggregate success pointer is missing"
    except OSError as error:
        return None, f"aggregate success pointer is unreadable: {error}"
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            return None, "aggregate success pointer is not a regular file"
        if metadata.st_size > MAX_POINTER_BYTES:
            return None, "aggregate success pointer exceeds the size limit"
        raw = os.read(descriptor, MAX_POINTER_BYTES + 1)
    except OSError as error:
        return None, f"aggregate success pointer is unreadable: {error}"
    finally:
        os.close(descriptor)
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=duplicate_safe_object)
    except (UnicodeError, json.JSONDecodeError, ValueError) as error:
        return None, f"aggregate success pointer is malformed: {error}"
    if not isinstance(value, dict):
        return None, "aggregate success pointer root is not an object"
    return value, ""


def validate_context(context: PointerContext) -> None:
    if not HEX_DIGEST.fullmatch(context.fingerprint):
        raise DecisionError("fingerprint is not a lowercase SHA-256 digest")
    if not SAFE_ID.fullmatch(context.platform):
        raise DecisionError("platform identity is malformed")
    if type(context.gate_contract) is not int or context.gate_contract != GATE_CONTRACT:
        raise DecisionError(f"gate contract must be {GATE_CONTRACT}")
    if not context.repository or "/" not in context.repository:
        raise DecisionError("repository identity is malformed")
    if type(context.pr_number) is not int or context.pr_number < 1:
        raise DecisionError("pull-request number is unavailable")
    if not context.head_branch:
        raise DecisionError("pull-request head branch is unavailable")
    if not context.base_repository or "/" not in context.base_repository:
        raise DecisionError("base repository identity is malformed")
    if not context.base_ref:
        raise DecisionError("base ref is unavailable")
    if not GIT_REVISION.fullmatch(context.base_sha):
        raise DecisionError("base revision is malformed")


def validate_pointer(pointer: dict[str, Any], context: PointerContext) -> None:
    validate_context(context)
    if frozenset(pointer) != POINTER_KEYS:
        raise DecisionError("aggregate success pointer fields do not match the contract")
    expected: dict[str, Any] = {
        "base_ref": context.base_ref,
        "base_repository": context.base_repository,
        "base_sha": context.base_sha,
        "conclusion": "success",
        "fingerprint": context.fingerprint,
        "format_version": POINTER_FORMAT,
        "gate_contract": context.gate_contract,
        "head_branch": context.head_branch,
        "platform": context.platform,
        "pr_number": context.pr_number,
        "repository": context.repository,
        "workflow_path": WORKFLOW_PATH,
    }
    for key, expected_value in expected.items():
        actual = pointer.get(key)
        if actual != expected_value or type(actual) is not type(expected_value):
            raise DecisionError(f"aggregate success pointer has wrong {key}")
    if not isinstance(pointer.get("producer_revision"), str) or not GIT_REVISION.fullmatch(
        pointer["producer_revision"]
    ):
        raise DecisionError("aggregate success pointer has invalid producer_revision")
    if not isinstance(pointer.get("producer_run_id"), str) or not RUN_ID.fullmatch(
        pointer["producer_run_id"]
    ):
        raise DecisionError("aggregate success pointer has invalid producer_run_id")
    if pointer.get("producer_run_attempt") != 1:
        raise DecisionError("only first-attempt evidence can be reused")
    if type(pointer.get("workflow_id")) is not int or pointer["workflow_id"] < 1:
        raise DecisionError("aggregate success pointer has invalid workflow_id")
    artifact_records = pointer.get("artifacts")
    if not isinstance(artifact_records, dict) or frozenset(artifact_records) != EXPECTED_ARTIFACTS:
        raise DecisionError("aggregate success pointer has the wrong artifact set")
    for name, record in artifact_records.items():
        if not isinstance(record, dict) or frozenset(record) != ARTIFACT_RECORD_KEYS:
            raise DecisionError(f"aggregate success pointer has malformed artifact {name}")
        if not ARTIFACT_DIGEST.fullmatch(str(record.get("digest", ""))):
            raise DecisionError(f"aggregate success pointer has invalid digest for {name}")
        size = record.get("size_in_bytes")
        if type(size) is not int or not 0 < size <= MAX_ARTIFACT_BYTES:
            raise DecisionError(f"aggregate success pointer has invalid size for {name}")


def parse_api_time(value: Any) -> datetime:
    if not isinstance(value, str):
        raise DecisionError("artifact expiration is malformed")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise DecisionError("artifact expiration is malformed") from error
    if parsed.tzinfo is None:
        raise DecisionError("artifact expiration has no timezone")
    return parsed


def validate_run(
    run: dict[str, Any],
    context: PointerContext,
    producer_run_id: str,
    producer_revision: str,
    require_completed_success: bool,
) -> None:
    repository = run.get("repository")
    if not isinstance(repository, dict) or repository.get("full_name") != context.repository:
        raise DecisionError("producer run belongs to a different repository")
    expected: dict[str, Any] = {
        "event": "pull_request",
        "head_branch": context.head_branch,
        "head_sha": producer_revision,
        "id": int(producer_run_id),
        "path": WORKFLOW_PATH,
        "run_attempt": 1,
    }
    for key, expected_value in expected.items():
        actual = run.get(key)
        if actual != expected_value or type(actual) is not type(expected_value):
            raise DecisionError(f"producer run has wrong {key}")
    if type(run.get("workflow_id")) is not int or run["workflow_id"] < 1:
        raise DecisionError("producer run has invalid workflow_id")
    if require_completed_success:
        if run.get("status") != "completed" or run.get("conclusion") != "success":
            raise DecisionError("producer workflow did not complete successfully")
    elif run.get("status") == "completed" and run.get("conclusion") != "success":
        raise DecisionError("producer workflow already completed unsuccessfully")


def unique_named_records(
    records: list[dict[str, Any]], expected_names: frozenset[str]
) -> dict[str, dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    for record in records:
        name = record.get("name")
        if not isinstance(name, str) or name not in expected_names:
            continue
        if name in selected:
            raise DecisionError(f"producer evidence has duplicate {name}")
        selected[name] = record
    missing = expected_names - frozenset(selected)
    if missing:
        raise DecisionError(f"producer evidence is missing {', '.join(sorted(missing))}")
    return selected


def validate_jobs(jobs: list[dict[str, Any]], require_gate: bool) -> None:
    expected_names = frozenset(EXPECTED_JOB_STEPS)
    if not require_gate:
        expected_names -= {"OMP-2 rollback gate"}
    selected = unique_named_records(jobs, expected_names)
    for job_name, job in selected.items():
        if job.get("status") != "completed" or job.get("conclusion") != "success":
            raise DecisionError(f"producer job {job_name} did not succeed")
        steps = job.get("steps")
        if not isinstance(steps, list):
            raise DecisionError(f"producer job {job_name} has no step evidence")
        required_steps = EXPECTED_JOB_STEPS[job_name]
        step_records = unique_named_records(
            [step for step in steps if isinstance(step, dict)],
            frozenset(required_steps),
        )
        for step_name, step in step_records.items():
            if step.get("status") != "completed" or step.get("conclusion") != "success":
                raise DecisionError(
                    f"producer step {job_name} / {step_name} did not succeed"
                )


def validate_artifacts(
    artifacts: list[dict[str, Any]],
    now: datetime | None = None,
) -> dict[str, dict[str, Any]]:
    now = now or datetime.now(timezone.utc)
    selected = unique_named_records(artifacts, EXPECTED_ARTIFACTS)
    result: dict[str, dict[str, Any]] = {}
    for name, artifact in selected.items():
        if artifact.get("expired") is not False:
            raise DecisionError(f"producer artifact {name} is expired")
        if parse_api_time(artifact.get("expires_at")) <= now:
            raise DecisionError(f"producer artifact {name} has passed its expiration")
        size = artifact.get("size_in_bytes")
        if type(size) is not int or not 0 < size <= MAX_ARTIFACT_BYTES:
            raise DecisionError(f"producer artifact {name} has invalid size")
        digest = artifact.get("digest")
        if not isinstance(digest, str) or not ARTIFACT_DIGEST.fullmatch(digest):
            raise DecisionError(f"producer artifact {name} has no SHA-256 digest")
        result[name] = {"digest": digest, "size_in_bytes": size}
    return result


def api_json(url: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "galactic-cup-rollback-ci",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
    except (OSError, urllib.error.HTTPError, urllib.error.URLError) as error:
        raise DecisionError(f"GitHub evidence request failed: {error}") from error
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=duplicate_safe_object)
    except (UnicodeError, json.JSONDecodeError, ValueError) as error:
        raise DecisionError(f"GitHub evidence response is malformed: {error}") from error
    if not isinstance(value, dict):
        raise DecisionError("GitHub evidence response root is not an object")
    return value


def api_collection(
    api_url: str,
    repository: str,
    endpoint: str,
    field: str,
    token: str,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    page = 1
    while True:
        separator = "&" if "?" in endpoint else "?"
        payload = api_json(
            f"{api_url}/repos/{repository}/{endpoint}{separator}per_page=100&page={page}",
            token,
        )
        values = payload.get(field)
        total = payload.get("total_count")
        if not isinstance(values, list) or type(total) is not int or total < 0:
            raise DecisionError(f"GitHub {field} response has invalid pagination")
        records.extend(value for value in values if isinstance(value, dict))
        if len(records) >= total:
            if len(records) != total:
                raise DecisionError(f"GitHub {field} response count drifted")
            return records
        if not values or page >= 20:
            raise DecisionError(f"GitHub {field} response is incomplete")
        page += 1


def fetch_producer_evidence(
    api_url: str,
    repository: str,
    run_id: str,
    token: str,
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    run = api_json(f"{api_url}/repos/{repository}/actions/runs/{run_id}", token)
    jobs = api_collection(
        api_url,
        repository,
        f"actions/runs/{run_id}/attempts/1/jobs",
        "jobs",
        token,
    )
    artifacts = api_collection(
        api_url,
        repository,
        f"actions/runs/{run_id}/artifacts",
        "artifacts",
        token,
    )
    return run, jobs, artifacts


def write_pointer(path: Path, pointer: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(pointer, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def pointer_for_run(
    context: PointerContext,
    run: dict[str, Any],
    producer_run_id: str,
    producer_revision: str,
    artifact_records: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    return {
        "artifacts": artifact_records,
        "base_ref": context.base_ref,
        "base_repository": context.base_repository,
        "base_sha": context.base_sha,
        "conclusion": "success",
        "fingerprint": context.fingerprint,
        "format_version": POINTER_FORMAT,
        "gate_contract": context.gate_contract,
        "head_branch": context.head_branch,
        "platform": context.platform,
        "pr_number": context.pr_number,
        "producer_revision": producer_revision,
        "producer_run_attempt": 1,
        "producer_run_id": producer_run_id,
        "repository": context.repository,
        "workflow_id": run["workflow_id"],
        "workflow_path": WORKFLOW_PATH,
    }


def git(repo: Path, *arguments: str) -> None:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=repo,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr.strip() or completed.stdout.strip())


def commit_fixture(repo: Path, message: str) -> str:
    git(repo, "add", ".")
    git(
        repo,
        "-c",
        "user.name=Rollback CI Self-Test",
        "-c",
        "user.email=rollback-ci@example.invalid",
        "commit",
        "-m",
        message,
    )
    return require_git(repo, ["rev-parse", "HEAD"]).decode().strip()


def write_fixture(repo: Path, relative: str, contents: str) -> None:
    path = repo / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")


def fixture_jobs() -> list[dict[str, Any]]:
    return [
        {
            "name": job_name,
            "status": "completed",
            "conclusion": "success",
            "steps": [
                {"name": step, "status": "completed", "conclusion": "success"}
                for step in required_steps
            ],
        }
        for job_name, required_steps in EXPECTED_JOB_STEPS.items()
    ]


def fixture_artifacts() -> list[dict[str, Any]]:
    return [
        {
            "name": name,
            "expired": False,
            "expires_at": "2099-01-01T00:00:00Z",
            "size_in_bytes": 1024,
            "digest": f"sha256:{hashlib.sha256(name.encode()).hexdigest()}",
        }
        for name in sorted(EXPECTED_ARTIFACTS)
    ]


def validate_workflow_wiring() -> None:
    workflow = (ROOT / WORKFLOW_PATH).read_text(encoding="utf-8")
    cache_revision = "0057852bfaa89a56745cba8c7296529d2fc39830"
    assert workflow.count(f"actions/cache/restore@{cache_revision}") == 1
    assert workflow.count(f"actions/cache/save@{cache_revision}") == 1
    assert "restore-keys:" not in workflow
    assert workflow.index("actions/cache/save@") > workflow.index("rollback_gate:")
    assert "github.run_attempt == 1" in workflow
    assert workflow.count("if: needs.rollback_scope.outputs.run == 'true'") == 3
    assert "steps.seed.outputs.save == 'true'" in workflow


def run_self_test() -> None:
    validate_workflow_wiring()
    with tempfile.TemporaryDirectory(prefix="rollback-ci-self-test-") as directory:
        repo = Path(directory)
        git(repo, "init", "-q")
        write_fixture(repo, WORKFLOW_PATH, "name: fixture\n")
        write_fixture(repo, "scripts/rollback_ci.py", "fixture manifest\n")
        write_fixture(repo, "sim/runtime.lua", "return 1\n")
        write_fixture(repo, "docs/readme.md", "base\n")
        base = commit_fixture(repo, "base")

        write_fixture(repo, "docs/readme.md", "unrelated\n")
        commit_fixture(repo, "docs only")
        unrelated = decide_scope(repo, "pull_request", pr_base_sha=base)
        assert not unrelated.run
        assert not unrelated.reuse_allowed

        write_fixture(repo, "sim/runtime.lua", "return 2\n")
        relevant_revision = commit_fixture(repo, "relevant")
        relevant = decide_scope(repo, "pull_request", pr_base_sha=base)
        assert relevant.run and relevant.reuse_allowed
        assert relevant.changed_paths == ("sim/runtime.lua",)
        assert HEX_DIGEST.fullmatch(relevant.fingerprint)

        write_fixture(repo, "docs/readme.md", "follow-up\n")
        commit_fixture(repo, "docs follow-up")
        follow_up = decide_scope(repo, "pull_request", pr_base_sha=base)
        assert follow_up.run and follow_up.reuse_allowed
        assert follow_up.fingerprint == relevant.fingerprint

        write_fixture(repo, "sim/runtime.lua", "return 3\n")
        commit_fixture(repo, "changed relevant content")
        changed = decide_scope(repo, "pull_request", pr_base_sha=base)
        assert changed.run and changed.reuse_allowed
        assert changed.fingerprint != relevant.fingerprint

        push = decide_scope(repo, "push", event_before=base)
        assert push.run and not push.reuse_allowed
        unavailable = decide_scope(repo, "pull_request", pr_base_sha="0" * 40)
        assert unavailable.run and not unavailable.reuse_allowed
        manual = decide_scope(repo, "workflow_dispatch")
        assert manual.run and not manual.reuse_allowed

        context = PointerContext(
            relevant.fingerprint,
            "Linux-X64",
            GATE_CONTRACT,
            "osobytes/galactic-cup",
            123,
            "codex/issue-123",
            "osobytes/galactic-cup",
            "main",
            base,
        )
        run = {
            "id": 12345,
            "event": "pull_request",
            "head_branch": context.head_branch,
            "head_sha": relevant_revision,
            "path": WORKFLOW_PATH,
            "run_attempt": 1,
            "workflow_id": 99,
            "status": "completed",
            "conclusion": "success",
            "repository": {"full_name": context.repository},
        }
        jobs = fixture_jobs()
        artifacts = fixture_artifacts()
        validate_run(run, context, "12345", relevant_revision, True)
        validate_jobs(jobs, True)
        artifact_records = validate_artifacts(artifacts)
        pointer = pointer_for_run(
            context, run, "12345", relevant_revision, artifact_records
        )
        validate_pointer(pointer, context)

        missing_job = [job for job in jobs if job["name"] != next(iter(LONG_JOB_NAMES))]
        try:
            validate_jobs(missing_job, True)
        except DecisionError:
            pass
        else:
            raise AssertionError("partial producer was accepted")

        failed_jobs = json.loads(json.dumps(jobs))
        failed_jobs[1]["conclusion"] = "failure"
        try:
            validate_jobs(failed_jobs, True)
        except DecisionError:
            pass
        else:
            raise AssertionError("failed producer job was accepted")

        reused_jobs = json.loads(json.dumps(jobs))
        for job in reused_jobs:
            if job["name"] in LONG_JOB_NAMES:
                job["conclusion"] = "skipped"
                job["steps"] = []
        try:
            validate_jobs(reused_jobs, True)
        except DecisionError:
            pass
        else:
            raise AssertionError("reused producer was allowed to chain")

        cancelled_run = dict(run, conclusion="cancelled")
        try:
            validate_run(cancelled_run, context, "12345", relevant_revision, True)
        except DecisionError:
            pass
        else:
            raise AssertionError("cancelled producer was accepted")

        failed_run = dict(run, conclusion="failure")
        try:
            validate_run(failed_run, context, "12345", relevant_revision, True)
        except DecisionError:
            pass
        else:
            raise AssertionError("failed producer was accepted")

        missing_artifact = artifacts[:-1]
        try:
            validate_artifacts(missing_artifact)
        except DecisionError:
            pass
        else:
            raise AssertionError("partial artifact set was accepted")

        wrong_contract = dict(pointer, gate_contract=GATE_CONTRACT - 1)
        try:
            validate_pointer(wrong_contract, context)
        except DecisionError:
            pass
        else:
            raise AssertionError("wrong-contract pointer was accepted")

        wrong_digest = json.loads(json.dumps(artifacts))
        wrong_digest[0]["digest"] = "sha256:not-a-digest"
        try:
            validate_artifacts(wrong_digest)
        except DecisionError:
            pass
        else:
            raise AssertionError("malformed artifact digest was accepted")

        malformed = repo / "pointer.json"
        malformed.write_text("{not-json", encoding="utf-8")
        loaded, _ = load_pointer(malformed)
        assert loaded is None

    print("rollback CI self-test passed")


def context_from_arguments(arguments: argparse.Namespace) -> PointerContext:
    return PointerContext(
        arguments.fingerprint,
        arguments.platform,
        arguments.gate_contract,
        arguments.repository,
        arguments.pr_number,
        arguments.head_branch,
        arguments.base_repository,
        arguments.base_ref,
        arguments.base_sha,
    )


def scope_command(arguments: argparse.Namespace) -> int:
    decision = decide_scope(
        arguments.repo.resolve(),
        arguments.event_name,
        event_before=arguments.event_before,
        pr_base_sha=arguments.pr_base_sha,
    )
    print(
        f"rollback_scope={'true' if decision.run else 'false'} "
        f"reuse_allowed={'true' if decision.reuse_allowed else 'false'} "
        f"fingerprint={decision.fingerprint}"
    )
    print(decision.reason)
    for path in decision.changed_paths:
        print(path)
    context_digest = cache_context_digest(arguments)
    write_github_output(
        arguments.github_output,
        {
            "cache_context": context_digest,
            "run": "true" if decision.run else "false",
            "reuse_allowed": "true" if decision.reuse_allowed else "false",
            "fingerprint": decision.fingerprint,
        },
    )
    return 0


def pointer_check_command(arguments: argparse.Namespace) -> int:
    reusable = False
    reason = ""
    try:
        context = context_from_arguments(arguments)
        pointer, load_error = load_pointer(arguments.path)
        if pointer is None:
            raise DecisionError(load_error)
        validate_pointer(pointer, context)
        if pointer["producer_run_id"] == arguments.current_run_id:
            raise DecisionError("current run cannot reuse itself")
        ancestor = run_git(
            arguments.repo.resolve(),
            ["merge-base", "--is-ancestor", pointer["producer_revision"], "HEAD"],
        )
        if ancestor.returncode != 0:
            raise DecisionError("producer revision is not an ancestor of the current head")
        producer_fingerprint = relevant_fingerprint(
            arguments.repo.resolve(), pointer["producer_revision"]
        )
        if producer_fingerprint != context.fingerprint:
            raise DecisionError("producer relevant-content fingerprint does not match")
        run, jobs, artifacts = fetch_producer_evidence(
            arguments.api_url,
            context.repository,
            pointer["producer_run_id"],
            arguments.token,
        )
        validate_run(
            run,
            context,
            pointer["producer_run_id"],
            pointer["producer_revision"],
            True,
        )
        if run["workflow_id"] != pointer["workflow_id"]:
            raise DecisionError("producer workflow identity does not match the pointer")
        validate_jobs(jobs, True)
        artifact_records = validate_artifacts(artifacts)
        if artifact_records != pointer["artifacts"]:
            raise DecisionError("producer artifact metadata does not match the pointer")
        reusable = True
        reason = (
            f"reusing complete first-attempt rollback campaign from run "
            f"{pointer['producer_run_id']} at {pointer['producer_revision']}"
        )
    except (DecisionError, OSError, ValueError) as error:
        reason = f"aggregate evidence is not reusable: {error}; running all five shards"
    print(reason)
    write_github_output(
        arguments.github_output,
        {"reuse": "true" if reusable else "false"},
    )
    return 0


def pointer_write_command(arguments: argparse.Namespace) -> int:
    save = False
    reason = ""
    try:
        context = context_from_arguments(arguments)
        validate_context(context)
        if not RUN_ID.fullmatch(arguments.producer_run_id):
            raise DecisionError("producer run id is malformed")
        if not GIT_REVISION.fullmatch(arguments.producer_revision):
            raise DecisionError("producer revision is malformed")
        if relevant_fingerprint(ROOT) != context.fingerprint:
            raise DecisionError("current relevant-content fingerprint drifted")
        run, jobs, artifacts = fetch_producer_evidence(
            arguments.api_url,
            context.repository,
            arguments.producer_run_id,
            arguments.token,
        )
        validate_run(
            run,
            context,
            arguments.producer_run_id,
            arguments.producer_revision,
            False,
        )
        validate_jobs(jobs, False)
        artifact_records = validate_artifacts(artifacts)
        pointer = pointer_for_run(
            context,
            run,
            arguments.producer_run_id,
            arguments.producer_revision,
            artifact_records,
        )
        validate_pointer(pointer, context)
        write_pointer(arguments.path, pointer)
        save = True
        reason = f"prepared aggregate success pointer for run {arguments.producer_run_id}"
    except (DecisionError, OSError, ValueError) as error:
        reason = f"aggregate pointer was not seeded: {error}"
    print(reason)
    write_github_output(
        arguments.github_output,
        {"save": "true" if save else "false"},
    )
    return 0


def add_pointer_context(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--path", type=Path, required=True)
    parser.add_argument("--fingerprint", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--gate-contract", type=int, default=GATE_CONTRACT)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--pr-number", type=int, required=True)
    parser.add_argument("--head-branch", required=True)
    parser.add_argument("--base-repository", required=True)
    parser.add_argument("--base-ref", required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--api-url", default="https://api.github.com")
    parser.add_argument("--github-output", type=Path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    scope = subparsers.add_parser("scope", help="decide cumulative rollback impact")
    scope.add_argument("--repo", type=Path, default=ROOT)
    scope.add_argument("--event-name", required=True)
    scope.add_argument("--event-before", default="")
    scope.add_argument("--pr-base-sha", default="")
    scope.add_argument("--repository", default="")
    scope.add_argument("--pr-number", type=int, default=0)
    scope.add_argument("--head-branch", default="")
    scope.add_argument("--base-repository", default="")
    scope.add_argument("--base-ref", default="")
    scope.add_argument("--base-sha", default="")
    scope.add_argument("--platform", default="")
    scope.add_argument("--gate-contract", type=int, default=GATE_CONTRACT)
    scope.add_argument("--github-output", type=Path)
    scope.set_defaults(handler=scope_command)

    pointer_check = subparsers.add_parser(
        "pointer-check", help="independently revalidate an untrusted pointer"
    )
    add_pointer_context(pointer_check)
    pointer_check.add_argument("--current-run-id", required=True)
    pointer_check.add_argument("--repo", type=Path, default=ROOT)
    pointer_check.set_defaults(handler=pointer_check_command)

    pointer_write = subparsers.add_parser(
        "pointer-write", help="prepare a pointer after all long shards pass"
    )
    add_pointer_context(pointer_write)
    pointer_write.add_argument("--producer-run-id", required=True)
    pointer_write.add_argument("--producer-revision", required=True)
    pointer_write.set_defaults(handler=pointer_write_command)

    self_test = subparsers.add_parser("self-test", help="run deterministic fixtures")
    self_test.set_defaults(handler=lambda _arguments: run_self_test() or 0)

    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    return arguments.handler(arguments)


if __name__ == "__main__":
    raise SystemExit(main())
