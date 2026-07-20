#!/usr/bin/env python3
"""Run the frozen OMP-1 Lua determinism suite in real Chrome and Firefox."""

from __future__ import annotations

import argparse
import json
import subprocess
import threading
import time
import urllib.parse
from datetime import UTC, datetime
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any

from browser_matrix import resolve_assets
from web_serve import ArtifactHandler


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_COMMIT = "495c5eb7eb55b54aaadfc21405c58f50a6d819c4"
REQUIRED_FIELDS = {
    "schema": "1",
    "fixture": "omp1-nebula-orion-eight-streams-v1",
    "build": "omp1-determinism-v1",
    "source": "issue-39-canonical-recording-v1",
    "content": "nebula-orion-showcase-content-v1",
    "config": "field=960x540;duration=120;max_goals=3;tick_rate=60",
    "tuning": "defaults",
    "seed": "19",
    "tick_rate": "60",
    "ticks": "7201",
    "boundaries": "7202",
    "hash": "fnv1a64-canonical-snapshot-v1",
    "final_hash": "b379a3a3ab5d7682",
    "sequence_digest": "0ff53075e3e626e0",
    "score": "0-1",
    "outcome": "away",
    "snapshot_bytes": "16859",
    "coverage": "goal_kickoff,tackle,aerial,keeper,full_time",
    "events": (
        "block:3,catch:6,claim:2,header:13,parry:1,pass:8,shot:5,"
        "tackle:421,touch:493,volley:8"
    ),
    "love": "11.5.0",
}
ERROR_MARKERS = (
    "GC_BROWSER|error|",
    "GC_BROWSER|window_error|",
    "GC_BROWSER|unhandled_rejection|",
    "GC_DETERMINISM|failure|",
)


def parse_marker(line: str) -> dict[str, str]:
    parts = line.split("|")
    if parts[:2] != ["GC_DETERMINISM", "result"]:
        raise RuntimeError(f"invalid determinism marker: {line}")
    fields: dict[str, str] = {}
    for part in parts[2:]:
        key, separator, value = part.partition("=")
        if not separator or not key or key in fields:
            raise RuntimeError(f"invalid determinism marker field: {part}")
        fields[key] = value
    for key, expected in REQUIRED_FIELDS.items():
        if fields.get(key) != expected:
            raise RuntimeError(
                f"determinism marker {key} mismatch: expected {expected}, got {fields.get(key)}"
            )
    return fields


def driver_version(path: Path) -> str:
    result = subprocess.run(
        [str(path), "--version"],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return (result.stdout or result.stderr).strip()


def launch(browser_name: str, binary: Path, driver: Path, log: Path) -> Any:
    if browser_name == "chrome":
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.chrome.service import Service

        options = Options()
        options.binary_location = str(binary)
        for argument in (
            "--headless=new",
            "--disable-dev-shm-usage",
            "--disable-extensions",
            "--no-default-browser-check",
            "--no-first-run",
        ):
            options.add_argument(argument)
        return webdriver.Chrome(
            service=Service(str(driver), log_output=str(log)),
            options=options,
        )

    from selenium import webdriver
    from selenium.webdriver.firefox.options import Options
    from selenium.webdriver.firefox.service import Service

    options = Options()
    options.binary_location = str(binary)
    options.add_argument("-headless")
    options.set_preference("extensions.autoDisableScopes", 15)
    options.set_preference("extensions.enabledScopes", 0)
    return webdriver.Firefox(
        service=Service(str(driver), log_output=str(log)),
        options=options,
    )


def console_state(driver: Any) -> dict[str, Any]:
    value = driver.execute_script(
        """
        const state = window.__GALACTIC_CUP__ || {};
        return {
          status: state.status || null,
          entries: (state.console_entries || []).map((entry) => String(entry.message || ""))
        };
        """
    )
    if not isinstance(value, dict):
        raise RuntimeError("browser returned malformed compatibility state")
    return value


def run_once(
    browser_name: str,
    binary: Path,
    driver_path: Path,
    url: str,
    output: Path,
    run_number: int,
    timeout_seconds: int,
) -> dict[str, Any]:
    started = time.monotonic()
    log = output / f"{browser_name}-{run_number}-webdriver.log"
    driver = launch(browser_name, binary, driver_path, log)
    try:
        driver.set_page_load_timeout(90)
        driver.get(url)
        deadline = time.monotonic() + timeout_seconds
        state: dict[str, Any] = {}
        markers: list[str] = []
        while time.monotonic() < deadline:
            state = console_state(driver)
            entries = state.get("entries")
            if not isinstance(entries, list):
                raise RuntimeError("browser console entries are malformed")
            messages = [str(entry) for entry in entries]
            failures = [
                message
                for message in messages
                if any(marker in message for marker in ERROR_MARKERS)
            ]
            if failures:
                raise RuntimeError(f"{browser_name} runtime failure: {failures[0]}")
            markers = [
                message
                for message in messages
                if message.startswith("GC_DETERMINISM|result|")
            ]
            if markers:
                break
            time.sleep(0.5)
        if len(markers) != 1:
            raise RuntimeError(
                f"{browser_name} run {run_number} timed out without exactly one result marker"
            )
        if state.get("status") != "running":
            raise RuntimeError(
                f"{browser_name} loader status is {state.get('status')!r}, expected 'running'"
            )
        fields = parse_marker(markers[0])
        return {
            "browser": browser_name,
            "browser_version": str(driver.capabilities.get("browserVersion")),
            "duration_seconds": round(time.monotonic() - started, 3),
            "fields": fields,
            "marker": markers[0],
            "run": run_number,
        }
    finally:
        driver.quit()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--browser",
        action="append",
        choices=("chrome", "firefox"),
        dest="browsers",
        help="Required browser; repeat to select both (default: both).",
    )
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--timeout-seconds", type=int, default=1200)
    parser.add_argument("--allow-dirty", action="store_true")
    args = parser.parse_args()
    browsers = args.browsers or ["chrome", "firefox"]
    if args.runs < 2:
        raise SystemExit("--runs must be at least 2")

    artifact = args.artifact.resolve()
    manifest = json.loads((artifact / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("runtime", {}).get("commit") != RUNTIME_COMMIT:
        raise SystemExit("browser artifact does not use the pinned love.js runtime")
    if manifest.get("source_dirty") and not args.allow_dirty:
        raise SystemExit("browser determinism refuses a dirty source manifest")

    server = ThreadingHTTPServer(("127.0.0.1", 0), lambda *a, **k: ArtifactHandler(*a, directory=str(artifact), **k))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    query = urllib.parse.urlencode(
        {"arg": json.dumps(["--determinism", "--browser-runtime"], separators=(",", ":"))}
    )
    url = f"http://127.0.0.1:{server.server_port}/?{query}"
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    log_dir = output.parent / (output.stem + "-logs")
    log_dir.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, Any]] = []
    assets: dict[str, dict[str, str]] = {}
    try:
        for browser_name in browsers:
            binary, driver_path = resolve_assets(browser_name, None, None)
            assets[browser_name] = {
                "binary": str(binary),
                "driver": str(driver_path),
                "driver_version": driver_version(driver_path),
            }
            browser_records = [
                run_once(
                    browser_name,
                    binary,
                    driver_path,
                    url,
                    log_dir,
                    run_number,
                    args.timeout_seconds,
                )
                for run_number in range(1, args.runs + 1)
            ]
            first_fields = browser_records[0]["fields"]
            for record in browser_records[1:]:
                if record["fields"] != first_fields:
                    raise RuntimeError(f"fresh {browser_name} runs disagreed")
            records.extend(browser_records)
        canonical = records[0]["fields"]
        for record in records[1:]:
            if record["fields"] != canonical:
                raise RuntimeError(
                    f"{record['browser']} run {record['run']} disagreed with the runtime matrix"
                )
        result = {
            "artifact": str(artifact),
            "assets": assets,
            "generated_at": datetime.now(UTC).isoformat(),
            "manifest_source_revision": manifest.get("source_revision"),
            "pass": True,
            "records": records,
            "runtime_commit": RUNTIME_COMMIT,
        }
        output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        for record in records:
            print(
                f"{record['browser']} run {record['run']}: "
                f"{record['browser_version']} {record['duration_seconds']}s "
                f"{record['fields']['sequence_digest']}"
            )
        print(f"browser determinism: {len(records)} fresh executions agree")
        return 0
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
