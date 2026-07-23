#!/usr/bin/env python3
"""Orchestrate OMP-2 rollback validation in native LÖVE, Chrome, and Firefox."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from dataclasses import dataclass
from datetime import UTC, datetime
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any, Iterable

from browser_determinism import (
    bounded_log_tail,
    console_state,
    launch,
    quit_browser_bounded,
    validate_provenance,
)
from browser_matrix import (
    executable_metadata,
    os_metadata,
    resolve_assets,
    selenium_metadata,
    validate_manifest,
)
from web_serve import ArtifactHandler


ROOT = Path(__file__).resolve().parents[1]
MARKER_PREFIX = "GC_ROLLBACK_VALIDATION"
METRICS_PREFIX = "GC_ROLLBACK_METRICS"
RESULT_REQUIRED_FIELDS = ("schema", "suite", "success", "logical_digest", "case_count")
NETWORK_SEEDS = (2001, 2002, 2003)
NATIVE_PROFILES = ("clean", "omp0_parity", "playable", "stress")
BROWSER_FULL_PROFILES = ("clean", "playable")
STRESS_PROFILE = "stress"
SCENARIOS = (
    "possession_change",
    "tackle",
    "shot",
    "goal",
    "kickoff",
    "aerial",
    "keeper_action",
    "repeated_rollback",
    "full_time",
)
SOAK_NETWORK_SEEDS = (2001, 2002, 2003, 2001, 2002)
DEFAULT_TIMEOUT_SECONDS = 7200
POLL_SECONDS = 0.2
ERROR_MARKERS = (
    "GC_BROWSER|error|",
    "GC_BROWSER|window_error|",
    "GC_BROWSER|unhandled_rejection|",
    "GC_ROLLBACK_VALIDATION|failure|",
)
SOAK_SAMPLES = ("warmup", "120", "360", "600", "final")
EXTERNAL_MEMORY_SAMPLES = ("warmup", "120", "360", "600")
MAX_MEMORY_GROWTH_RATIO = 0.10
MAX_SNAPSHOT_COUNT = 31
MAX_SNAPSHOT_BYTES = 600 * 1024
MAX_HISTORY_BYTES = 1024 * 1024
MAX_P95_WORK_MS = 16.67
MAX_ROLLBACK_JOB_MS = 33.3


@dataclass(frozen=True)
class ValidationMarker:
    """One stable logical marker emitted by the Lua validation campaign."""

    kind: str
    fields: dict[str, str]
    raw: str


@dataclass(frozen=True)
class ProcessIdentity:
    """A PID plus Linux start time, which protects teardown checks from PID reuse."""

    pid: int
    start_ticks: int


@dataclass(frozen=True)
class ProcessInfo:
    """The /proc fields needed for process-tree memory and CPU accounting."""

    identity: ProcessIdentity
    parent_pid: int
    rss_bytes: int
    cpu_seconds: float


@dataclass(frozen=True)
class RuntimeMetric:
    """A nonlogical wall-time observation paired with one logical case."""

    fields: dict[str, str]
    kind: str
    raw: str


def utc_now() -> str:
    return datetime.now(UTC).isoformat()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def parse_marker(line: str) -> ValidationMarker:
    parts = line.split("|")
    if len(parts) < 4 or parts[0] != MARKER_PREFIX:
        raise RuntimeError(f"invalid rollback validation marker: {line}")
    kind = parts[1]
    if kind not in {"case", "result"}:
        raise RuntimeError(f"unexpected rollback validation marker kind {kind!r}")
    fields: dict[str, str] = {}
    for part in parts[2:]:
        key, separator, value = part.partition("=")
        if not separator or not key or key in fields:
            raise RuntimeError(f"invalid rollback validation marker field: {part}")
        fields[key] = value
    return ValidationMarker(kind=kind, fields=fields, raw=line)


def markers_from_messages(messages: Iterable[str]) -> list[ValidationMarker]:
    markers = []
    for message in messages:
        if message.startswith(MARKER_PREFIX + "|"):
            markers.append(parse_marker(message))
    return markers


def parse_runtime_metric(line: str) -> RuntimeMetric:
    parts = line.split("|")
    if len(parts) < 4 or parts[0] != METRICS_PREFIX:
        raise RuntimeError(f"invalid rollback runtime metric: {line}")
    kind = parts[1]
    if kind not in {"case", "runtime"}:
        raise RuntimeError(f"unexpected rollback runtime metric kind {kind!r}")
    fields: dict[str, str] = {}
    for part in parts[2:]:
        key, separator, value = part.partition("=")
        if not separator or not key or key in fields:
            raise RuntimeError(f"invalid rollback runtime metric field: {part}")
        fields[key] = value
    return RuntimeMetric(fields=fields, kind=kind, raw=line)


def runtime_metrics_from_messages(messages: Iterable[str]) -> list[RuntimeMetric]:
    metrics = []
    for message in messages:
        if message.startswith(METRICS_PREFIX + "|"):
            metrics.append(parse_runtime_metric(message))
    return metrics


def rejected_case(marker: ValidationMarker) -> str | None:
    """Reject explicit failed gates without constraining the evolving case schema."""

    fields = marker.fields
    expected_failure = fields.get("expected_failure") == "1"
    if fields.get("gate") in {"fail", "failed"}:
        return "gate"
    if fields.get("pass") == "0":
        return "pass"
    if fields.get("success") == "0" and not expected_failure:
        return "success"
    if fields.get("status") in {"fail", "failed", "error"} and not expected_failure:
        return "status"
    return None


def validate_marker_set(
    markers: list[ValidationMarker],
    expected_suite: str,
) -> ValidationMarker:
    if not markers:
        raise RuntimeError(f"{expected_suite} emitted no rollback validation markers")
    results = [marker for marker in markers if marker.kind == "result"]
    cases = [marker for marker in markers if marker.kind == "case"]
    if len(results) != 1:
        raise RuntimeError(f"{expected_suite} emitted {len(results)} result markers, expected one")
    result = results[0]
    missing = [field for field in RESULT_REQUIRED_FIELDS if not result.fields.get(field)]
    if missing:
        raise RuntimeError(f"{expected_suite} result omits required fields: {', '.join(missing)}")
    if result.fields["schema"] != "1":
        raise RuntimeError(
            f"{expected_suite} result schema is {result.fields['schema']!r}, expected '1'"
        )
    if result.fields["suite"] != expected_suite:
        raise RuntimeError(
            f"{expected_suite} command emitted suite {result.fields['suite']!r}"
        )
    if result.fields["success"] != "1":
        raise RuntimeError(f"{expected_suite} result reports success={result.fields['success']!r}")
    try:
        declared_count = int(result.fields["case_count"])
    except ValueError as error:
        raise RuntimeError(f"{expected_suite} case_count is not an integer") from error
    if declared_count <= 0 or declared_count != len(cases):
        raise RuntimeError(
            f"{expected_suite} declared {declared_count} cases but emitted {len(cases)}"
        )
    raw_cases = [marker.raw for marker in cases]
    if len(set(raw_cases)) != len(raw_cases):
        raise RuntimeError(f"{expected_suite} emitted duplicate case markers")
    for marker in cases:
        failed_field = rejected_case(marker)
        if failed_field is not None:
            raise RuntimeError(
                f"{expected_suite} case reports a failed {failed_field} gate: {marker.raw}"
            )
    if markers[-1].kind != "result":
        raise RuntimeError(f"{expected_suite} emitted logical markers after its result")
    return result


def positive_integer(value: str, description: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise RuntimeError(f"{description} is not an integer") from error
    if parsed <= 0:
        raise RuntimeError(f"{description} must be positive")
    return parsed


def non_negative_integer(value: str, description: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise RuntimeError(f"{description} is not an integer") from error
    if parsed < 0:
        raise RuntimeError(f"{description} must be non-negative")
    return parsed


def expected_case_plan(
    suite: str,
    arguments: tuple[str, ...],
) -> list[dict[str, str]]:
    plan: list[dict[str, str]] = []

    def full_case(profile: str, seed: int) -> dict[str, str]:
        return {
            "case": f"full-{profile}-{seed}",
            "network_seed": str(seed),
            "profile": profile,
            "scenario": "complete_fixture",
        }

    def scenario_case(scenario: str, profile: str, seed: int) -> dict[str, str]:
        return {
            "case": f"scenario-{scenario}-{profile}-{seed}",
            "network_seed": str(seed),
            "profile": profile,
            "scenario": scenario,
        }

    if suite == "native":
        if arguments:
            raise RuntimeError("native validation does not accept case filters")
        for profile in NATIVE_PROFILES:
            for seed in NETWORK_SEEDS:
                plan.append(full_case(profile, seed))
        for seed in NETWORK_SEEDS:
            for scenario in SCENARIOS:
                plan.append(scenario_case(scenario, STRESS_PROFILE, seed))
    elif suite == "browser-full":
        if len(arguments) != 2:
            raise RuntimeError("browser-full requires profile and network seed")
        profile, raw_seed = arguments
        if profile not in NATIVE_PROFILES or not raw_seed.isdigit():
            raise RuntimeError("browser-full received an unsupported profile or seed")
        seed = int(raw_seed)
        if seed not in NETWORK_SEEDS:
            raise RuntimeError("browser-full received an unsupported network seed")
        plan.append(full_case(profile, seed))
    elif suite == "browser-stress":
        if len(arguments) != 2 or arguments[0] != STRESS_PROFILE:
            raise RuntimeError("browser-stress requires the pinned stress profile and seed")
        if not arguments[1].isdigit() or int(arguments[1]) not in NETWORK_SEEDS:
            raise RuntimeError("browser-stress received an unsupported network seed")
        seed = int(arguments[1])
        for scenario in SCENARIOS:
            plan.append(scenario_case(scenario, STRESS_PROFILE, seed))
    elif suite == "late-window":
        if arguments:
            raise RuntimeError("late-window validation does not accept case filters")
        for delay in (30, 31):
            plan.append(
                {
                    "case": f"delay-{delay}",
                    "network_seed": str(delay),
                    "profile": f"delay_{delay}",
                    "scenario": "late_window",
                }
            )
    elif suite == "soak":
        if arguments:
            raise RuntimeError("soak validation does not accept case filters")
        for index, seed in enumerate(SOAK_NETWORK_SEEDS, start=1):
            plan.append(
                {
                    "case": f"soak-{index}-{seed}",
                    "network_seed": str(seed),
                    "profile": "playable",
                    "scenario": "complete_fixture",
                }
            )
    else:
        raise RuntimeError(f"no pinned case plan for suite {suite!r}")
    return plan


def validate_case_plan(
    markers: list[ValidationMarker],
    suite: str,
    arguments: tuple[str, ...],
) -> None:
    cases = [marker for marker in markers if marker.kind == "case"]
    expected = expected_case_plan(suite, arguments)
    if len(cases) != len(expected):
        raise RuntimeError(
            f"{suite} emitted {len(cases)} cases, expected pinned plan of {len(expected)}"
        )
    for index, (marker, planned) in enumerate(zip(cases, expected, strict=True), start=1):
        mismatches = [
            f"{key}={marker.fields.get(key)!r}"
            for key, value in planned.items()
            if marker.fields.get(key) != value
        ]
        if mismatches:
            raise RuntimeError(
                f"{suite} case {index} differs from the pinned plan: " + ", ".join(mismatches)
            )


def validate_case_integrity(markers: list[ValidationMarker]) -> None:
    for marker in (row for row in markers if row.kind == "case"):
        fields = marker.fields
        case_id = fields.get("case", "<unknown>")
        required = (
            "client_hash",
            "cpu_gate",
            "event_confirmed_digest",
            "event_reference_digest",
            "event_residue",
            "expected_failure",
            "game_gate",
            "history_gate",
            "hidden_progress",
            "lab_success",
            "peak_history_bytes",
            "peak_snapshot_bytes",
            "peak_snapshots",
            "profile",
            "reference_hash",
            "scenario_pass",
            "snapshot_gate",
            "success",
        )
        missing = [name for name in required if fields.get(name) in {None, ""}]
        if missing:
            raise RuntimeError(
                f"{case_id} omits integrity fields: {', '.join(missing)}"
            )
        if fields["success"] != "1":
            raise RuntimeError(f"{case_id} was not accepted")
        if fields["scenario_pass"] != "1":
            raise RuntimeError(f"{case_id} did not cover its declared scenario")
        if fields["hidden_progress"] != "0":
            raise RuntimeError(f"{case_id} made hidden progress after a terminal result")
        for gate in ("cpu_gate", "snapshot_gate", "history_gate", "game_gate"):
            if fields[gate] != "1":
                raise RuntimeError(f"{case_id} reports {gate}={fields[gate]!r}")
        expected_failure = fields["expected_failure"] == "1"
        if not expected_failure:
            if fields["lab_success"] != "1":
                raise RuntimeError(f"{case_id} laboratory result failed unexpectedly")
            if fields["reference_hash"] != fields["client_hash"]:
                raise RuntimeError(f"{case_id} client hash did not converge to authority")
            if fields["event_reference_digest"] != fields["event_confirmed_digest"]:
                raise RuntimeError(f"{case_id} confirmed event digest differs from authority")
            if fields["event_residue"] != "0":
                raise RuntimeError(f"{case_id} retained speculative event residue")
        if fields["profile"] == "playable":
            snapshot_count = non_negative_integer(
                fields["peak_snapshots"],
                f"{case_id} peak_snapshots",
            )
            snapshot_bytes = non_negative_integer(
                fields["peak_snapshot_bytes"],
                f"{case_id} peak_snapshot_bytes",
            )
            history_bytes = non_negative_integer(
                fields["peak_history_bytes"],
                f"{case_id} peak_history_bytes",
            )
            if snapshot_count > MAX_SNAPSHOT_COUNT:
                raise RuntimeError(f"{case_id} exceeded the 31-snapshot gate")
            if snapshot_bytes >= MAX_SNAPSHOT_BYTES:
                raise RuntimeError(f"{case_id} exceeded the 600 KiB snapshot gate")
            if history_bytes >= MAX_HISTORY_BYTES:
                raise RuntimeError(f"{case_id} exceeded the 1 MiB history gate")


def finite_non_negative_float(value: str, description: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise RuntimeError(f"{description} is not numeric") from error
    if not math.isfinite(parsed) or parsed < 0:
        raise RuntimeError(f"{description} must be finite and non-negative")
    return parsed


def validate_runtime_metrics(
    metrics: list[RuntimeMetric],
    markers: list[ValidationMarker],
    suite: str,
) -> None:
    runtimes = [metric for metric in metrics if metric.kind == "runtime"]
    if len(runtimes) != 1:
        raise RuntimeError(f"emitted {len(runtimes)} runtime provenance rows, expected one")
    runtime = runtimes[0].fields
    expected_runtime = {
        "input_version": "1",
        "love": "11.5.0",
        "snapshot_version": "5",
        "suite": suite,
        "tick_rate": "60",
    }
    mismatches = [
        f"{key}={runtime.get(key)!r}"
        for key, value in expected_runtime.items()
        if runtime.get(key) != value
    ]
    if mismatches:
        raise RuntimeError("runtime provenance mismatch: " + ", ".join(mismatches))
    if not re.fullmatch(r"[0-9a-f]{16}", runtime.get("profile_digest", "")):
        raise RuntimeError("runtime profile_digest is not canonical 16-hex")

    metrics = [metric for metric in metrics if metric.kind == "case"]
    cases = [marker for marker in markers if marker.kind == "case"]
    if len(metrics) != len(cases):
        raise RuntimeError(
            f"emitted {len(metrics)} runtime metric rows for {len(cases)} validation cases"
        )
    seen: set[str] = set()
    numeric_fields = (
        "p95_work_ms",
        "max_rollback_ms",
        "p95_update_wall_ms",
        "max_update_wall_ms",
        "simulation_ms",
        "capture_ms",
        "restore_ms",
        "resimulation_ms",
        "rollback_ms",
    )
    count_fields = (
        "capture_calls",
        "simulation_calls",
        "restore_calls",
        "resimulation_calls",
        "rollback_calls",
    )
    for case, metric in zip(cases, metrics, strict=True):
        fields = metric.fields
        case_id = case.fields["case"]
        if fields.get("case") != case_id:
            raise RuntimeError(
                f"runtime metric {fields.get('case')!r} is out of order for {case_id}"
            )
        if case_id in seen:
            raise RuntimeError(f"duplicate runtime metric for {case_id}")
        seen.add(case_id)
        if fields.get("profile") != case.fields["profile"]:
            raise RuntimeError(f"{case_id} runtime metric profile does not match its case")
        missing = [
            name
            for name in (*numeric_fields, *count_fields, "work_samples")
            if fields.get(name) in {None, ""}
        ]
        if missing:
            raise RuntimeError(
                f"{case_id} runtime metric omits fields: {', '.join(missing)}"
            )
        values = {
            name: finite_non_negative_float(fields[name], f"{case_id} {name}")
            for name in numeric_fields
        }
        positive_integer(fields["work_samples"], f"{case_id} work_samples")
        counts = {
            name: non_negative_integer(fields[name], f"{case_id} {name}")
            for name in count_fields
        }
        if counts["simulation_calls"] <= 0:
            raise RuntimeError(f"{case_id} recorded no simulation timing samples")
        if case.fields["profile"] == "playable":
            if values["p95_work_ms"] >= MAX_P95_WORK_MS:
                raise RuntimeError(
                    f"{case_id} p95 work {values['p95_work_ms']:.6f} ms "
                    f"does not meet the <{MAX_P95_WORK_MS} ms gate"
                )
            if values["max_rollback_ms"] >= MAX_ROLLBACK_JOB_MS:
                raise RuntimeError(
                    f"{case_id} max rollback {values['max_rollback_ms']:.6f} ms "
                    f"does not meet the <{MAX_ROLLBACK_JOB_MS} ms gate"
                )


def runtime_metric_record(metrics: list[RuntimeMetric]) -> dict[str, Any]:
    payload = "\n".join(metric.raw for metric in metrics)
    encoded = (payload + ("\n" if payload else "")).encode()
    return {
        "marker_sha256": sha256_bytes(encoded),
        "rows": [
            {
                "fields": metric.fields,
                "kind": metric.kind,
                "marker": metric.raw,
            }
            for metric in metrics
        ],
    }


def validate_soak_contract(markers: list[ValidationMarker]) -> dict[str, ValidationMarker]:
    cases = [marker for marker in markers if marker.kind == "case"]
    emitted_samples = [marker.fields.get("sample") for marker in cases]
    if emitted_samples != list(SOAK_SAMPLES):
        raise RuntimeError(
            "soak checkpoint order is "
            f"{emitted_samples!r}, expected {list(SOAK_SAMPLES)!r}"
        )
    by_sample: dict[str, ValidationMarker] = {}
    for marker in cases:
        sample = marker.fields.get("sample")
        if sample not in SOAK_SAMPLES:
            raise RuntimeError(f"soak case has unexpected sample {sample!r}")
        if sample in by_sample:
            raise RuntimeError(f"soak emitted duplicate {sample} checkpoint")
        if marker.fields.get("forced_gc") != "1":
            raise RuntimeError(f"soak {sample} checkpoint did not force garbage collection")
        positive_integer(
            marker.fields.get("lua_heap_bytes", ""),
            f"soak {sample} lua_heap_bytes",
        )
        if not re.fullmatch(r"[0-9a-f]{16}", marker.fields.get("logical_digest", "")):
            raise RuntimeError(f"soak {sample} logical_digest is not canonical 16-hex")
        if marker.fields.get("success") != "1":
            raise RuntimeError(f"soak {sample} checkpoint reports failure")
        by_sample[sample] = marker
    missing = [sample for sample in SOAK_SAMPLES if sample not in by_sample]
    if missing:
        raise RuntimeError(f"soak omitted checkpoints: {', '.join(missing)}")
    if len(cases) != len(SOAK_SAMPLES):
        raise RuntimeError("soak emitted unexpected non-checkpoint cases")
    return by_sample


def validate_late_window_contract(markers: list[ValidationMarker]) -> None:
    cases = [marker for marker in markers if marker.kind == "case"]
    supported = next(
        (marker for marker in cases if marker.fields.get("case") == "delay-30"),
        None,
    )
    if supported is None:
        raise RuntimeError("late-window omitted the supported delay-30 correction")
    if (
        supported.fields.get("lab_success") != "1"
        or supported.fields.get("status") != "converged"
        or supported.fields.get("max_depth") != "30"
    ):
        raise RuntimeError(
            "delay-30 did not converge at the exact supported rollback depth"
        )
    expected_failures = [
        marker
        for marker in cases
        if marker.kind == "case" and marker.fields.get("expected_failure") == "1"
    ]
    if len(expected_failures) != 1:
        raise RuntimeError(
            "late-window must emit exactly one accepted over-window terminal case"
        )
    fields = expected_failures[0].fields
    expected = {
        "hidden_progress": "0",
        "lab_success": "0",
        "late_tick": "0",
        "status": "late_input_unrecoverable",
        "success": "1",
    }
    mismatches = [
        f"{key}={fields.get(key)!r}"
        for key, value in expected.items()
        if fields.get(key) != value
    ]
    if mismatches:
        raise RuntimeError(
            "late-window over-window terminal contract failed: " + ", ".join(mismatches)
        )


def growth_gate(values: dict[str, int], label: str) -> dict[str, Any]:
    baseline = values["warmup"]
    peak_sample = max(values, key=lambda sample: values[sample])
    peak = values[peak_sample]
    growth_ratio = max(0.0, (peak - baseline) / baseline)
    passed = growth_ratio <= MAX_MEMORY_GROWTH_RATIO + 1e-12
    return {
        "baseline_bytes": baseline,
        "growth_percent": round(growth_ratio * 100, 6),
        "label": label,
        "limit_percent": MAX_MEMORY_GROWTH_RATIO * 100,
        "pass": passed,
        "peak_bytes": peak,
        "peak_sample": peak_sample,
        "samples": values,
    }


def soak_memory_evidence(
    markers: list[ValidationMarker],
    resources: dict[str, Any],
    browser_name: str | None,
) -> dict[str, Any]:
    by_sample = validate_soak_contract(markers)
    checkpoints = {
        row.get("validation_marker"): row
        for row in resources.get("checkpoints", [])
        if row.get("validation_marker") is not None
    }
    lua_values = {
        sample: positive_integer(
            by_sample[sample].fields["lua_heap_bytes"],
            f"soak {sample} lua_heap_bytes",
        )
        for sample in SOAK_SAMPLES
    }
    rss_values: dict[str, int] = {}
    js_heap_values: dict[str, int] = {}
    for sample in EXTERNAL_MEMORY_SAMPLES:
        checkpoint = checkpoints.get(by_sample[sample].raw)
        if checkpoint is None:
            raise RuntimeError(f"soak {sample} has no external process checkpoint")
        rss_bytes = checkpoint.get("rss_bytes")
        if not isinstance(rss_bytes, int) or rss_bytes <= 0:
            raise RuntimeError(f"soak {sample} process RSS is unavailable")
        rss_values[sample] = rss_bytes
        if browser_name == "chrome":
            js_heap = checkpoint.get("js_heap")
            used_bytes = js_heap.get("used_bytes") if isinstance(js_heap, dict) else None
            if not isinstance(used_bytes, int) or used_bytes <= 0:
                raise RuntimeError(f"soak {sample} Chrome JS heap is unavailable")
            js_heap_values[sample] = used_bytes
    gates = {
        "lua_heap": growth_gate(lua_values, "Lua heap"),
        "process_rss": growth_gate(rss_values, "process-tree RSS"),
    }
    if browser_name == "chrome":
        gates["js_heap"] = growth_gate(js_heap_values, "Chrome JS heap")
    return {
        "gates": gates,
        "pass": all(gate["pass"] for gate in gates.values()),
    }


def compare_fresh_markers(
    first: list[ValidationMarker],
    second: list[ValidationMarker],
) -> str:
    first_lines = [marker.raw for marker in first]
    second_lines = [marker.raw for marker in second]
    if first_lines != second_lines:
        mismatch = 0
        while (
            mismatch < len(first_lines)
            and mismatch < len(second_lines)
            and first_lines[mismatch] == second_lines[mismatch]
        ):
            mismatch += 1
        first_value = first_lines[mismatch] if mismatch < len(first_lines) else "<missing>"
        second_value = second_lines[mismatch] if mismatch < len(second_lines) else "<missing>"
        raise RuntimeError(
            "fresh native rollback validation markers disagreed at "
            f"index {mismatch}: {first_value!r} != {second_value!r}"
        )
    payload = ("\n".join(first_lines) + "\n").encode()
    return sha256_bytes(payload)


def source_provenance() -> dict[str, Any]:
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout
    return {
        "dirty": bool(status.strip()),
        "revision": revision,
    }


def system_provenance() -> dict[str, Any]:
    return {
        "environment": {
            key: os.environ.get(key)
            for key in (
                "CI",
                "DISPLAY",
                "GALLIUM_DRIVER",
                "LIBGL_ALWAYS_SOFTWARE",
                "SE_CACHE_PATH",
            )
        },
        "machine": platform.machine(),
        "os": os_metadata(),
        "platform": platform.platform(),
        "python_runtime": executable_metadata(Path(sys.executable)),
        "python_version": platform.python_version(),
    }


def read_process_table() -> dict[int, ProcessInfo]:
    """Read a best-effort Linux process table without adding a psutil dependency."""

    if not Path("/proc").is_dir():
        return {}
    clock_ticks = os.sysconf("SC_CLK_TCK")
    page_size = os.sysconf("SC_PAGE_SIZE")
    result: dict[int, ProcessInfo] = {}
    for stat_path in Path("/proc").glob("[0-9]*/stat"):
        try:
            payload = stat_path.read_text(encoding="utf-8")
            close = payload.rfind(")")
            if close < 0:
                continue
            pid = int(payload[: payload.find(" ")])
            fields = payload[close + 2 :].split()
            parent_pid = int(fields[1])
            user_ticks = int(fields[11])
            system_ticks = int(fields[12])
            start_ticks = int(fields[19])
            rss_pages = int(fields[21])
            identity = ProcessIdentity(pid=pid, start_ticks=start_ticks)
            result[pid] = ProcessInfo(
                identity=identity,
                parent_pid=parent_pid,
                rss_bytes=max(0, rss_pages) * page_size,
                cpu_seconds=(user_ticks + system_ticks) / clock_ticks,
            )
        except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError):
            continue
    return result


def validation_process_census() -> dict[ProcessIdentity, tuple[str, ...]]:
    """Find native validation commands, including helpers detached by an AppImage."""

    table = read_process_table()
    matches: dict[ProcessIdentity, tuple[str, ...]] = {}
    root_argument = str(ROOT)
    for pid, info in table.items():
        try:
            raw = Path(f"/proc/{pid}/cmdline").read_bytes()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        arguments = tuple(
            value.decode("utf-8", errors="replace")
            for value in raw.split(b"\0")
            if value
        )
        if root_argument in arguments and "--rollback-validation" in arguments:
            matches[info.identity] = arguments
    return matches


class ProcessTreeSampler:
    """Track a process and every descendant seen during a bounded campaign."""

    def __init__(self, root_pid: int) -> None:
        self.root_pid = root_pid
        self._root_identity: ProcessIdentity | None = None
        self.started = time.monotonic()
        self._known: set[ProcessIdentity] = set()
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._sample_loop, daemon=True)
        self._peak_rss_bytes = 0
        self._peak_process_count = 0
        self._latest_cpu_seconds = 0.0
        self._checkpoints: list[dict[str, Any]] = []
        self._available = Path("/proc").is_dir()
        self._sample()
        self._thread.start()

    def _sample_loop(self) -> None:
        while not self._stop.wait(POLL_SECONDS):
            self._sample()

    def _sample(self) -> dict[str, Any]:
        table = read_process_table()
        if not table:
            return {
                "cpu_seconds": None,
                "process_count": None,
                "rss_bytes": None,
            }
        with self._lock:
            root = table.get(self.root_pid)
            if self._root_identity is None and root is not None:
                self._root_identity = root.identity
            known_pids = {
                identity.pid
                for identity in self._known
                if table.get(identity.pid)
                and table[identity.pid].identity.start_ticks == identity.start_ticks
            }
            selected = set(known_pids)
            if (
                root is not None
                and self._root_identity is not None
                and root.identity == self._root_identity
            ):
                selected.add(self.root_pid)
            changed = True
            while changed:
                changed = False
                for pid, info in table.items():
                    if pid not in selected and info.parent_pid in selected:
                        selected.add(pid)
                        changed = True
            infos = [table[pid] for pid in selected if pid in table]
            for info in infos:
                self._known.add(info.identity)
            rss_bytes = sum(info.rss_bytes for info in infos)
            cpu_seconds = sum(info.cpu_seconds for info in infos)
            self._peak_rss_bytes = max(self._peak_rss_bytes, rss_bytes)
            self._peak_process_count = max(self._peak_process_count, len(infos))
            self._latest_cpu_seconds = max(self._latest_cpu_seconds, cpu_seconds)
            return {
                "cpu_seconds": round(cpu_seconds, 6),
                "process_count": len(infos),
                "rss_bytes": rss_bytes,
            }

    def checkpoint(self, label: str) -> dict[str, Any]:
        sample = self._sample()
        row = {
            "elapsed_seconds": round(time.monotonic() - self.started, 6),
            "label": label,
            **sample,
        }
        with self._lock:
            self._checkpoints.append(row)
        return row

    def alive_identities(self) -> list[ProcessIdentity]:
        table = read_process_table()
        with self._lock:
            return sorted(
                (
                    identity
                    for identity in self._known
                    if table.get(identity.pid)
                    and table[identity.pid].identity.start_ticks == identity.start_ticks
                ),
                key=lambda identity: identity.pid,
            )

    def finish(self) -> dict[str, Any]:
        self._stop.set()
        self._thread.join(timeout=2)
        self._sample()
        with self._lock:
            return {
                "available": self._available,
                "checkpoints": list(self._checkpoints),
                "cpu_seconds": round(self._latest_cpu_seconds, 6)
                if self._available
                else None,
                "peak_process_count": self._peak_process_count if self._available else None,
                "peak_rss_bytes": self._peak_rss_bytes if self._available else None,
            }


def wait_identities_gone(
    sampler: ProcessTreeSampler,
    timeout_seconds: float,
) -> list[ProcessIdentity]:
    deadline = time.monotonic() + timeout_seconds
    alive = sampler.alive_identities()
    while alive and time.monotonic() < deadline:
        time.sleep(0.05)
        alive = sampler.alive_identities()
    return alive


def terminate_identities(identities: Iterable[ProcessIdentity], sent_signal: int) -> None:
    table = read_process_table()
    for identity in identities:
        current = table.get(identity.pid)
        if current is None or current.identity.start_ticks != identity.start_ticks:
            continue
        try:
            os.kill(identity.pid, sent_signal)
        except (PermissionError, ProcessLookupError):
            continue


def wait_validation_processes_gone(
    baseline: set[ProcessIdentity],
    timeout_seconds: float,
) -> dict[ProcessIdentity, tuple[str, ...]]:
    deadline = time.monotonic() + timeout_seconds
    alive = {
        identity: arguments
        for identity, arguments in validation_process_census().items()
        if identity not in baseline
    }
    while alive and time.monotonic() < deadline:
        time.sleep(0.05)
        alive = {
            identity: arguments
            for identity, arguments in validation_process_census().items()
            if identity not in baseline
        }
    return alive


def finish_process_tree(
    process: subprocess.Popen[Any],
    sampler: ProcessTreeSampler,
    timed_out: bool,
    validation_baseline: set[ProcessIdentity],
) -> dict[str, Any]:
    signals: list[str] = []
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            signals.append("TERM")
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
                signals.append("KILL")
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
    alive = wait_identities_gone(sampler, 2)
    detected_orphans = len(alive)
    if alive:
        terminate_identities(alive, signal.SIGTERM)
        alive = wait_identities_gone(sampler, 2)
    if alive:
        terminate_identities(alive, signal.SIGKILL)
        alive = wait_identities_gone(sampler, 2)
    detached = wait_validation_processes_gone(validation_baseline, 2)
    detected_detached = len(detached)
    detached_signals: list[str] = []
    if detached:
        terminate_identities(detached, signal.SIGTERM)
        detached_signals.append("TERM")
        detached = wait_validation_processes_gone(validation_baseline, 2)
    if detached:
        terminate_identities(detached, signal.SIGKILL)
        detached_signals.append("KILL")
        detached = wait_validation_processes_gone(validation_baseline, 2)
    sampler.checkpoint("teardown")
    return {
        "detached_orphan_count": detected_detached,
        "detached_remaining_process_count": len(detached),
        "detached_signals": detached_signals,
        "detected_orphan_count": detected_orphans,
        "orphan_free": (
            not alive
            and not detached
            and detected_orphans == 0
            and detected_detached == 0
        ),
        "remaining_process_count": len(alive),
        "signals": signals,
    }


def bounded_tail(path: Path, max_lines: int = 80, max_characters: int = 12000) -> str:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as error:
        return f"<log unavailable: {error}>"
    value = "\n".join(lines[-max_lines:])
    if len(value) > max_characters:
        value = "<truncated>\n" + value[-max_characters:]
    return value or "<log empty>"


def command_executable(command: str) -> Path:
    candidate = Path(command)
    resolved = candidate if candidate.parent != Path(".") else Path(shutil.which(command) or "")
    if not resolved or not resolved.is_file():
        raise RuntimeError(f"runtime executable does not exist: {command}")
    return resolved.resolve()


def marker_record(
    markers: list[ValidationMarker],
    result: ValidationMarker,
) -> dict[str, Any]:
    encoded = ("\n".join(marker.raw for marker in markers) + "\n").encode()
    return {
        "case_count": int(result.fields["case_count"]),
        "logical_digest": result.fields["logical_digest"],
        "logical_marker_sha256": sha256_bytes(encoded),
        "markers": [marker.raw for marker in markers],
        "result_fields": result.fields,
    }


def run_native_once(
    love_bin: Path,
    suite: str,
    arguments: tuple[str, ...],
    log_path: Path,
    timeout_seconds: int,
    enforce_plan: bool = True,
) -> dict[str, Any]:
    command = [
        str(love_bin),
        str(ROOT),
        "--rollback-validation",
        suite,
        *arguments,
    ]
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    timed_out = False
    messages: list[str] = []
    reader_errors: list[str] = []
    validation_baseline = set(validation_process_census())
    if validation_baseline:
        identities = ", ".join(
            f"{identity.pid}:{identity.start_ticks}"
            for identity in sorted(validation_baseline, key=lambda row: row.pid)
        )
        raise RuntimeError(
            "native rollback validation requires a serialized runtime lane; "
            f"pre-existing validation processes: {identities}"
        )
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            text=True,
            bufsize=1,
        )
        sampler = ProcessTreeSampler(process.pid)
        sampler.checkpoint("started")

        def read_output() -> None:
            stream = process.stdout
            if stream is None:
                reader_errors.append("native process stdout pipe is unavailable")
                return
            try:
                for raw_line in stream:
                    log.write(raw_line)
                    log.flush()
                    line = raw_line.rstrip("\r\n")
                    messages.append(line)
                    if line.startswith(MARKER_PREFIX + "|"):
                        marker = parse_marker(line)
                        checkpoint = sampler.checkpoint(
                            f"marker-{len(markers_from_messages(messages))}-{marker.kind}"
                        )
                        checkpoint["validation_marker"] = marker.raw
            except Exception as error:
                reader_errors.append(str(error))

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()
        try:
            try:
                process.wait(timeout=timeout_seconds)
            except subprocess.TimeoutExpired:
                timed_out = True
        finally:
            try:
                teardown = finish_process_tree(
                    process,
                    sampler,
                    timed_out,
                    validation_baseline,
                )
                reader.join(timeout=5)
                if reader.is_alive():
                    reader_errors.append("native output reader did not stop")
            finally:
                resources = sampler.finish()
    duration_seconds = round(time.monotonic() - started, 6)
    if reader_errors:
        raise RuntimeError(f"native {suite} output reader failed: {reader_errors[0]}")
    if timed_out:
        raise RuntimeError(
            f"native {suite} timed out after {timeout_seconds}s\n{bounded_tail(log_path)}"
        )
    if process.returncode != 0:
        raise RuntimeError(
            f"native {suite} exited {process.returncode}\n{bounded_tail(log_path)}"
        )
    if not teardown["orphan_free"]:
        raise RuntimeError(f"native {suite} left processes behind after bounded teardown")
    markers = markers_from_messages(messages)
    runtime_metrics = runtime_metrics_from_messages(messages)
    result = validate_marker_set(markers, suite)
    if enforce_plan:
        validate_case_plan(markers, suite, arguments)
        validate_case_integrity(markers)
        validate_runtime_metrics(runtime_metrics, markers, suite)
    if suite == "late-window":
        validate_late_window_contract(markers)
    record = {
        "arguments": list(arguments),
        "command": command,
        "duration_seconds": duration_seconds,
        "log": {
            "path": str(log_path.resolve()),
            "sha256": sha256_file(log_path),
            "size_bytes": log_path.stat().st_size,
        },
        **marker_record(markers, result),
        "resources": resources,
        "runtime_metrics": runtime_metric_record(runtime_metrics),
        "suite": suite,
        "teardown": teardown,
    }
    if suite == "soak":
        record["soak_memory"] = soak_memory_evidence(markers, resources, None)
    return record


def native_shard_plan() -> list[tuple[str, tuple[str, ...]]]:
    """Split independent native matrix cases into fresh bounded processes."""

    plan: list[tuple[str, tuple[str, ...]]] = []
    for profile in NATIVE_PROFILES:
        for network_seed in NETWORK_SEEDS:
            plan.append(("browser-full", (profile, str(network_seed))))
    for network_seed in NETWORK_SEEDS:
        plan.append(("browser-stress", (STRESS_PROFILE, str(network_seed))))
    return plan


def native_aggregate_record(
    run_number: int,
    shards: list[dict[str, Any]],
) -> dict[str, Any]:
    markers = [
        parse_marker(raw)
        for shard in shards
        for raw in shard["markers"]
    ]
    validate_case_plan(markers, "native", ())
    validate_case_integrity(markers)
    encoded = ("\n".join(marker.raw for marker in markers) + "\n").encode()
    return {
        "case_count": sum(shard["case_count"] for shard in shards),
        "duration_seconds": round(
            sum(float(shard["duration_seconds"]) for shard in shards),
            6,
        ),
        "logical_marker_sha256": sha256_bytes(encoded),
        "markers": [marker.raw for marker in markers],
        "result_count": sum(1 for marker in markers if marker.kind == "result"),
        "run": run_number,
        "shard_count": len(shards),
        "shards": shards,
        "suite": "native-sharded",
    }


def native_matrix(
    evidence: dict[str, Any],
    love_bin: Path,
    raw_root: Path,
    timeout_seconds: int,
) -> None:
    native: dict[str, Any] = {
        "matrix_process_model": "fresh_process_per_full_case_and_stress_seed",
        "plan": [
            {"arguments": list(arguments), "suite": suite}
            for suite, arguments in native_shard_plan()
        ],
        "persistent_soak": True,
        "runtime": executable_metadata(love_bin),
        "fresh_runs": [],
    }
    evidence["native"] = native
    for run_number in (1, 2):
        shards: list[dict[str, Any]] = []
        for shard_number, (suite, arguments) in enumerate(
            native_shard_plan(),
            start=1,
        ):
            slug = "-".join((suite, *arguments))
            shard = run_native_once(
                love_bin,
                suite,
                arguments,
                raw_root / f"native-{run_number}-{shard_number:02d}-{slug}.log",
                timeout_seconds,
            )
            shard["shard"] = shard_number
            shards.append(shard)
        native["fresh_runs"].append(
            native_aggregate_record(run_number, shards)
        )
    first_markers = [
        parse_marker(marker) for marker in native["fresh_runs"][0]["markers"]
    ]
    second_markers = [
        parse_marker(marker) for marker in native["fresh_runs"][1]["markers"]
    ]
    native["fresh_marker_sha256"] = compare_fresh_markers(first_markers, second_markers)
    native["fresh_runs_agree"] = True
    native["late_window"] = run_native_once(
        love_bin,
        "late-window",
        (),
        raw_root / "native-late-window.log",
        timeout_seconds,
    )
    native["soak"] = run_native_once(
        love_bin,
        "soak",
        (),
        raw_root / "native-soak.log",
        timeout_seconds,
    )
    if not native["soak"]["soak_memory"]["pass"]:
        raise RuntimeError("native soak exceeded the 10% post-warmup memory-growth gate")


def browser_js_heap(driver: Any, browser_name: str) -> dict[str, Any] | None:
    if browser_name != "chrome":
        return None
    try:
        metrics = driver.execute_cdp_cmd("Performance.getMetrics", {}).get("metrics", [])
        values = {
            str(row.get("name")): row.get("value")
            for row in metrics
            if isinstance(row, dict)
        }
        return {
            "total_bytes": int(values["JSHeapTotalSize"]),
            "used_bytes": int(values["JSHeapUsedSize"]),
        }
    except Exception:
        return None


def browser_checkpoint(
    sampler: ProcessTreeSampler,
    driver: Any,
    browser_name: str,
    label: str,
    force_js_gc: bool = False,
) -> dict[str, Any]:
    if force_js_gc and browser_name == "chrome":
        driver.execute_cdp_cmd("HeapProfiler.collectGarbage", {})
    row = sampler.checkpoint(label)
    row["js_heap"] = browser_js_heap(driver, browser_name)
    return row


def browser_teardown(
    driver: Any,
    sampler: ProcessTreeSampler,
) -> tuple[dict[str, Any], dict[str, Any]]:
    teardown_error = None
    try:
        teardown = quit_browser_bounded(driver)
    except Exception as error:
        teardown_error = str(error)
        teardown = {
            "fallback": True,
            "process_group": None,
            "quit_error": teardown_error,
            "service_exit_code": None,
            "signals": [],
        }
    alive = wait_identities_gone(sampler, 2)
    detected_orphans = len(alive)
    if alive:
        terminate_identities(alive, signal.SIGTERM)
        alive = wait_identities_gone(sampler, 2)
    if alive:
        terminate_identities(alive, signal.SIGKILL)
        alive = wait_identities_gone(sampler, 2)
    sampler.checkpoint("teardown")
    teardown["detected_orphan_count"] = detected_orphans
    teardown["orphan_free"] = not alive and detected_orphans == 0
    teardown["remaining_process_count"] = len(alive)
    teardown["teardown_error"] = teardown_error
    resources = sampler.finish()
    return teardown, resources


def run_browser_once(
    browser_name: str,
    binary: Path,
    driver_path: Path,
    base_url: str,
    suite: str,
    arguments: tuple[str, ...],
    log_path: Path,
    timeout_seconds: int,
) -> dict[str, Any]:
    driver_log = log_path.with_suffix(".webdriver.log")
    started = time.monotonic()
    try:
        driver = launch(browser_name, binary, driver_path, driver_log)
    except Exception as error:
        raise RuntimeError(
            f"{browser_name} {suite} launch failed: {error}\n"
            f"{bounded_log_tail(driver_log)}"
        ) from error
    process = getattr(getattr(driver, "service", None), "process", None)
    if process is None or getattr(process, "pid", None) is None:
        try:
            driver.quit()
        finally:
            raise RuntimeError(f"{browser_name} {suite} WebDriver process is unavailable")
    if browser_name == "chrome":
        driver.execute_cdp_cmd("Performance.enable", {})
    sampler = ProcessTreeSampler(process.pid)
    resource_checkpoints = [browser_checkpoint(sampler, driver, browser_name, "started")]
    messages: list[str] = []
    markers: list[ValidationMarker] = []
    result: ValidationMarker | None = None
    teardown: dict[str, Any]
    resources: dict[str, Any]
    try:
        driver.set_page_load_timeout(90)
        driver.set_script_timeout(90)
        query_arguments = [
            "--rollback-validation",
            suite,
            *arguments,
            "--browser-runtime",
        ]
        query = urllib.parse.urlencode(
            {"arg": json.dumps(query_arguments, separators=(",", ":"))}
        )
        driver.get(f"{base_url}?{query}")
        deadline = time.monotonic() + timeout_seconds
        observed_marker_count = 0
        while time.monotonic() < deadline:
            state = console_state(driver)
            entries = state.get("entries")
            if not isinstance(entries, list):
                raise RuntimeError(f"{browser_name} {suite} returned malformed console entries")
            messages = [str(entry) for entry in entries]
            failures = [
                message
                for message in messages
                if any(error_marker in message for error_marker in ERROR_MARKERS)
            ]
            if failures:
                raise RuntimeError(f"{browser_name} {suite} runtime failure: {failures[0]}")
            markers = markers_from_messages(messages)
            while observed_marker_count < len(markers):
                marker = markers[observed_marker_count]
                checkpoint = browser_checkpoint(
                    sampler,
                    driver,
                    browser_name,
                    f"marker-{observed_marker_count + 1}-{marker.kind}",
                    force_js_gc=marker.fields.get("forced_gc") == "1",
                )
                checkpoint["validation_marker"] = marker.raw
                resource_checkpoints.append(checkpoint)
                observed_marker_count += 1
            results = [marker for marker in markers if marker.kind == "result"]
            if len(results) > 1:
                raise RuntimeError(f"{browser_name} {suite} emitted duplicate results")
            if results:
                result = validate_marker_set(markers, suite)
                break
            time.sleep(0.5)
        if result is None:
            raise RuntimeError(
                f"{browser_name} {suite} timed out after {timeout_seconds}s without a result"
            )
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("\n".join(messages) + "\n", encoding="utf-8")
        resource_checkpoints.append(
            browser_checkpoint(sampler, driver, browser_name, "completed")
        )
    finally:
        if messages:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text("\n".join(messages) + "\n", encoding="utf-8")
        teardown, resources = browser_teardown(driver, sampler)
    if teardown["teardown_error"] is not None:
        raise RuntimeError(
            f"{browser_name} {suite} teardown failed: {teardown['teardown_error']}"
        )
    if not teardown["orphan_free"]:
        raise RuntimeError(f"{browser_name} {suite} left browser processes after teardown")
    if result is None:
        raise RuntimeError(f"{browser_name} {suite} produced no validated result")
    validate_case_plan(markers, suite, arguments)
    validate_case_integrity(markers)
    runtime_metrics = runtime_metrics_from_messages(messages)
    validate_runtime_metrics(runtime_metrics, markers, suite)
    js_heap_samples = [
        row["js_heap"] for row in resource_checkpoints if row.get("js_heap") is not None
    ]
    resources["browser_checkpoints"] = resource_checkpoints
    resources["js_heap_peak_used_bytes"] = (
        max(row["used_bytes"] for row in js_heap_samples) if js_heap_samples else None
    )
    resources["js_heap_peak_total_bytes"] = (
        max(row["total_bytes"] for row in js_heap_samples) if js_heap_samples else None
    )
    record = {
        "arguments": list(arguments),
        "browser": browser_name,
        "browser_version": str(driver.capabilities.get("browserVersion")),
        "duration_seconds": round(time.monotonic() - started, 6),
        "log": {
            "path": str(log_path.resolve()),
            "sha256": sha256_file(log_path),
            "size_bytes": log_path.stat().st_size,
        },
        **marker_record(markers, result),
        "resources": resources,
        "runtime_metrics": runtime_metric_record(runtime_metrics),
        "suite": suite,
        "teardown": teardown,
        "webdriver_log": {
            "path": str(driver_log.resolve()),
            "sha256": sha256_file(driver_log),
            "size_bytes": driver_log.stat().st_size,
        },
    }
    if suite == "soak":
        record["soak_memory"] = soak_memory_evidence(
            markers,
            resources,
            browser_name,
        )
    return record


def artifact_provenance(artifact: Path, allow_dirty: bool) -> dict[str, Any]:
    manifest_path = artifact / "manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"browser artifact manifest is missing: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    validate_provenance(manifest, allow_dirty)
    return {
        "manifest": manifest,
        "manifest_path": str(manifest_path.resolve()),
        "manifest_sha256": sha256_file(manifest_path),
    }


def browser_plan() -> list[tuple[str, tuple[str, ...]]]:
    plan = []
    for profile in BROWSER_FULL_PROFILES:
        for network_seed in NETWORK_SEEDS:
            plan.append(("browser-full", (profile, str(network_seed))))
    for network_seed in NETWORK_SEEDS:
        plan.append(("browser-stress", (STRESS_PROFILE, str(network_seed))))
    plan.append(("soak", ()))
    return plan


def browser_matrix(
    evidence: dict[str, Any],
    artifact: Path,
    browsers: list[str],
    raw_root: Path,
    timeout_seconds: int,
    allow_dirty: bool,
) -> None:
    provenance = artifact_provenance(artifact, allow_dirty)
    source = evidence["source"]
    if provenance["manifest"].get("source_revision") != source["revision"]:
        raise RuntimeError("browser artifact source revision does not match the checkout")
    server = ThreadingHTTPServer(
        ("127.0.0.1", 0),
        lambda *args, **kwargs: ArtifactHandler(
            *args,
            directory=str(artifact),
            **kwargs,
        ),
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://127.0.0.1:{server.server_port}/"
    browser_evidence: dict[str, Any] = {
        "artifact": provenance,
        "plan": [
            {"arguments": list(arguments), "suite": suite}
            for suite, arguments in browser_plan()
        ],
        "runtimes": {},
        "selenium": selenium_metadata(),
    }
    evidence["browser"] = browser_evidence
    try:
        validate_manifest(base_url, provenance["manifest"])
        for browser_name in browsers:
            binary, driver_path = resolve_assets(browser_name, None, None)
            runtime: dict[str, Any] = {
                "binary": executable_metadata(binary),
                "driver": executable_metadata(driver_path),
                "runs": [],
            }
            browser_evidence["runtimes"][browser_name] = runtime
            for run_number, (suite, arguments) in enumerate(browser_plan(), start=1):
                slug = "-".join((browser_name, suite, *arguments))
                run = run_browser_once(
                    browser_name,
                    binary,
                    driver_path,
                    base_url,
                    suite,
                    arguments,
                    raw_root / f"{slug}.log",
                    timeout_seconds,
                )
                run["run"] = run_number
                runtime["runs"].append(run)
                if suite == "soak" and not run["soak_memory"]["pass"]:
                    raise RuntimeError(
                        f"{browser_name} soak exceeded the 10% post-warmup "
                        "memory-growth gate"
                    )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    if thread.is_alive():
        raise RuntimeError("browser artifact server did not stop cleanly")


def run_self_test() -> None:
    case = f"{MARKER_PREFIX}|case|schema=1|id=fixture|success=1"
    result = (
        f"{MARKER_PREFIX}|result|schema=1|suite=native|success=1|"
        "logical_digest=abc123|case_count=1"
    )
    markers = markers_from_messages(["noise", case, result])
    validated = validate_marker_set(markers, "native")
    if validated.fields["logical_digest"] != "abc123":
        raise RuntimeError("marker parsing self-test lost the logical digest")
    if compare_fresh_markers(markers, list(markers)) != sha256_bytes(
        (case + "\n" + result + "\n").encode()
    ):
        raise RuntimeError("fresh marker digest self-test failed")

    invalid_sets = [
        [],
        markers + [validated],
        [parse_marker(result.replace("case_count=1", "case_count=2"))],
        [
            parse_marker(case.replace("success=1", "success=0")),
            validated,
        ],
        [
            parse_marker(case),
            parse_marker(result.replace("success=1", "success=0")),
        ],
    ]
    for invalid in invalid_sets:
        try:
            validate_marker_set(invalid, "native")
        except RuntimeError:
            pass
        else:
            raise RuntimeError("invalid marker set passed self-test")
    try:
        compare_fresh_markers(markers, markers[:-1])
    except RuntimeError:
        pass
    else:
        raise RuntimeError("fresh marker disagreement passed self-test")

    expected_plan = [
        ("browser-full", ("clean", "2001")),
        ("browser-full", ("clean", "2002")),
        ("browser-full", ("clean", "2003")),
        ("browser-full", ("playable", "2001")),
        ("browser-full", ("playable", "2002")),
        ("browser-full", ("playable", "2003")),
        ("browser-stress", ("stress", "2001")),
        ("browser-stress", ("stress", "2002")),
        ("browser-stress", ("stress", "2003")),
        ("soak", ()),
    ]
    if browser_plan() != expected_plan:
        raise RuntimeError("browser matrix plan self-test failed")
    expected_counts = {
        ("native", ()): 39,
        ("browser-full", ("clean", "2001")): 1,
        ("browser-stress", ("stress", "2001")): 9,
        ("late-window", ()): 2,
        ("soak", ()): 5,
    }
    for (suite, arguments), count in expected_counts.items():
        if len(expected_case_plan(suite, arguments)) != count:
            raise RuntimeError(f"{suite} pinned case-plan self-test failed")
    flattened_native_shards = [
        case
        for suite, arguments in native_shard_plan()
        for case in expected_case_plan(suite, arguments)
    ]
    if flattened_native_shards != expected_case_plan("native", ()):
        raise RuntimeError("native shard plan changed the pinned case order")
    try:
        raise_on_interruption(signal.SIGTERM, None)
    except InterruptedError as error:
        if "SIGTERM" not in str(error):
            raise RuntimeError("interruption handler lost the signal name") from error
    else:
        raise RuntimeError("interruption handler self-test failed")

    integrity_case = parse_marker(
        f"{MARKER_PREFIX}|case|schema=1|case=integrity|profile=playable|success=1|"
        "lab_success=1|expected_failure=0|hidden_progress=0|scenario_pass=1|"
        "cpu_gate=1|snapshot_gate=1|history_gate=1|game_gate=1|"
        "reference_hash=abcd|client_hash=abcd|event_reference_digest=ef01|"
        "event_confirmed_digest=ef01|event_residue=0|peak_snapshots=31|"
        "peak_snapshot_bytes=614399|peak_history_bytes=1048575"
    )
    validate_case_integrity([integrity_case])
    over_budget = parse_marker(
        integrity_case.raw.replace("peak_snapshots=31", "peak_snapshots=32")
    )
    try:
        validate_case_integrity([over_budget])
    except RuntimeError:
        pass
    else:
        raise RuntimeError("over-budget playable case passed integrity self-test")
    runtime_metric = parse_runtime_metric(
        f"{METRICS_PREFIX}|case|case=integrity|profile=playable|p95_work_ms=1.25|"
        "max_rollback_ms=2.5|p95_update_wall_ms=3|max_update_wall_ms=4|"
        "simulation_ms=5|capture_ms=6|restore_ms=7|resimulation_ms=8|"
        "rollback_ms=9|capture_calls=10|simulation_calls=11|restore_calls=12|"
        "resimulation_calls=13|rollback_calls=14|work_samples=15"
    )
    runtime_provenance = parse_runtime_metric(
        f"{METRICS_PREFIX}|runtime|love=11.5.0|suite=native|"
        "profile_digest=0000000000000000|input_version=1|snapshot_version=5|tick_rate=60"
    )
    validate_runtime_metrics(
        [runtime_provenance, runtime_metric],
        [integrity_case],
        "native",
    )
    over_cpu = parse_runtime_metric(
        runtime_metric.raw.replace("p95_work_ms=1.25", "p95_work_ms=16.67")
    )
    try:
        validate_runtime_metrics(
            [runtime_provenance, over_cpu],
            [integrity_case],
            "native",
        )
    except RuntimeError:
        pass
    else:
        raise RuntimeError("over-budget runtime metric passed self-test")

    soak_cases = [
        parse_marker(
            f"{MARKER_PREFIX}|case|schema=1|sample={sample}|forced_gc=1|"
            f"lua_heap_bytes={1000 + index * 10}|logical_digest={index:016x}|success=1"
        )
        for index, sample in enumerate(SOAK_SAMPLES)
    ]
    soak_result = parse_marker(
        f"{MARKER_PREFIX}|result|schema=1|suite=soak|success=1|"
        "logical_digest=soak|case_count=5"
    )
    soak_markers = [*soak_cases, soak_result]
    validate_marker_set(soak_markers, "soak")
    soak_resources = {
        "checkpoints": [
            {
                "js_heap": {"used_bytes": 2000 + index * 10},
                "rss_bytes": 3000 + index * 10,
                "validation_marker": soak_cases[index].raw,
            }
            for index in range(4)
        ]
    }
    soak_gate = soak_memory_evidence(soak_markers, soak_resources, "chrome")
    if not soak_gate["pass"]:
        raise RuntimeError("passing soak memory self-test failed")
    soak_resources["checkpoints"][-1]["rss_bytes"] = 4000
    if soak_memory_evidence(soak_markers, soak_resources, "chrome")["pass"]:
        raise RuntimeError("over-budget soak memory self-test passed")

    late_case = parse_marker(
        f"{MARKER_PREFIX}|case|schema=1|success=1|lab_success=0|expected_failure=1|"
        "case=delay-31|status=late_input_unrecoverable|late_tick=0|hidden_progress=0"
    )
    supported_late_case = parse_marker(
        f"{MARKER_PREFIX}|case|schema=1|success=1|lab_success=1|expected_failure=0|"
        "case=delay-30|status=converged|late_tick=none|hidden_progress=0|max_depth=30"
    )
    validate_late_window_contract([supported_late_case, late_case])

    with tempfile.TemporaryDirectory(prefix="gc-rollback-self-test-") as temp:
        script = Path(temp) / "fake-love"
        script.write_text(
            "#!/usr/bin/env python3\n"
            f"print({case!r})\n"
            f"print({result!r})\n",
            encoding="utf-8",
        )
        script.chmod(0o755)
        record = run_native_once(
            script,
            "native",
            (),
            Path(temp) / "fake.log",
            5,
            enforce_plan=False,
        )
        if record["case_count"] != 1 or not record["teardown"]["orphan_free"]:
            raise RuntimeError("fake native launcher self-test failed")
        detached_script = Path(temp) / "fake-love-detached"
        detached_script.write_text(
            "#!/usr/bin/env python3\n"
            "import subprocess\n"
            "import sys\n"
            "subprocess.Popen(\n"
            "    [sys.executable, '-c', 'import time; time.sleep(60)', sys.argv[1], sys.argv[2]],\n"
            "    start_new_session=True,\n"
            "    stdout=subprocess.DEVNULL,\n"
            "    stderr=subprocess.DEVNULL,\n"
            ")\n",
            encoding="utf-8",
        )
        detached_script.chmod(0o755)
        try:
            run_native_once(
                detached_script,
                "native",
                (),
                Path(temp) / "fake-detached.log",
                5,
                enforce_plan=False,
            )
        except RuntimeError as error:
            if "left processes behind" not in str(error):
                raise
        else:
            raise RuntimeError("detached native helper passed teardown self-test")
        if validation_process_census():
            raise RuntimeError("detached native helper survived teardown self-test")
    print("rollback validation orchestration self-test: OK")


def default_output() -> Path:
    directory = Path(tempfile.mkdtemp(prefix="galactic-cup-omp2-rollback-"))
    return directory / "omp2_rollback.json"


def raise_on_interruption(sent_signal: int, _frame: Any) -> None:
    """Turn terminal signals into exceptions so bounded teardown always runs."""

    try:
        signal_name = signal.Signals(sent_signal).name
    except ValueError:
        signal_name = str(sent_signal)
    raise InterruptedError(f"rollback validation interrupted by {signal_name}")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("native", "browser", "full"),
        default="native",
    )
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--love-bin", default=os.environ.get("LOVE_BIN", "love"))
    parser.add_argument(
        "--browser",
        action="append",
        choices=("chrome", "firefox"),
        dest="browsers",
    )
    parser.add_argument("--timeout-seconds", type=int, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    if args.self_test:
        run_self_test()
        return 0
    if args.timeout_seconds <= 0:
        raise SystemExit("--timeout-seconds must be positive")
    if args.mode in {"browser", "full"} and args.artifact is None:
        raise SystemExit("--artifact is required for browser and full modes")

    output = (args.output or default_output()).resolve()
    raw_root = output.parent / (output.stem + "-raw")
    source = source_provenance()
    evidence: dict[str, Any] = {
        "generated_at": utc_now(),
        "mode": args.mode,
        "pass": False,
        "schema": 1,
        "source": source,
        "system": system_provenance(),
    }
    signal.signal(signal.SIGINT, raise_on_interruption)
    signal.signal(signal.SIGTERM, raise_on_interruption)
    try:
        if source["dirty"] and not args.allow_dirty:
            raise RuntimeError("rollback validation refuses a dirty source checkout")
        if raw_root.exists() and any(raw_root.iterdir()):
            raise RuntimeError(f"raw evidence directory is not empty: {raw_root}")
        raw_root.mkdir(parents=True, exist_ok=True)
        if args.mode in {"native", "full"}:
            love_bin = command_executable(args.love_bin)
            native_matrix(evidence, love_bin, raw_root, args.timeout_seconds)
        if args.mode in {"browser", "full"}:
            browser_matrix(
                evidence,
                args.artifact.resolve(),
                args.browsers or ["chrome", "firefox"],
                raw_root,
                args.timeout_seconds,
                args.allow_dirty,
            )
        evidence["pass"] = True
        evidence["completed_at"] = utc_now()
        write_json(output, evidence)
        print(f"rollback validation: PASS ({output})")
        return 0
    except Exception as error:
        evidence["completed_at"] = utc_now()
        evidence["error"] = str(error)
        write_json(output, evidence)
        print(f"rollback validation: FAIL ({output})", file=sys.stderr)
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
