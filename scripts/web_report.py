#!/usr/bin/env python3
"""Summarize exported browser or native compatibility telemetry."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


EXPECTED_FLOW = ["title", "squad", "formation", "tactic", "match", "result"]


def parse_marker(message: str) -> dict[str, str] | None:
    prefix, separator, payload = message.partition("|")
    if prefix not in {"GC_BROWSER", "GC_METRICS"} or not separator:
        return None
    parts = payload.split("|")
    record = {"source": prefix, "kind": parts[0]}
    for part in parts[1:]:
        key, equals, value = part.partition("=")
        if equals:
            record[key] = value
    return record


def records_from_text(text: str) -> tuple[list[dict[str, str]], list[dict[str, Any]]]:
    records: list[dict[str, str]] = []
    logs: list[dict[str, Any]] = []
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        value = None

    entries = value if isinstance(value, list) else None
    if entries is not None:
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            logs.append(entry)
            message = entry.get("message")
            if isinstance(message, str):
                record = parse_marker(message)
                if record:
                    records.append(record)
        return records, logs

    for line in text.splitlines():
        record = parse_marker(line.strip())
        if record:
            records.append(record)
    return records, logs


def value(records: list[dict[str, str]], kind: str, key: str) -> str:
    for record in reversed(records):
        if record.get("kind") == kind and key in record:
            return record[key]
    return "missing"


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, int(len(ordered) * fraction + 0.999999) - 1))
    return ordered[index]


def summarize(paths: list[Path], require_flow: bool) -> int:
    records: list[dict[str, str]] = []
    logs: list[dict[str, Any]] = []
    for path in paths:
        parsed_records, parsed_logs = records_from_text(path.read_text(encoding="utf-8"))
        records.extend(parsed_records)
        logs.extend(parsed_logs)

    routes = [record["route"] for record in records if record.get("kind") == "route"]
    flow_ok = routes[-len(EXPECTED_FLOW) :] == EXPECTED_FLOW
    print("Compatibility telemetry")
    print(f"  inputs: {len([r for r in records if r.get('kind') == 'input'])}")
    print(f"  routes: {' -> '.join(routes) if routes else 'missing'}")
    print(f"  complete flow: {'PASS' if flow_ok else 'MISSING'}")
    input_latencies = [
        float(record["latency_ms"])
        for record in records
        if record.get("kind") == "input_latency" and "latency_ms" in record
    ]
    if input_latencies:
        print(
            "  input latency ms: "
            f"p50={percentile(input_latencies, 0.50):.3f} "
            f"p95={percentile(input_latencies, 0.95):.3f} "
            f"max={max(input_latencies):.3f}"
        )
    else:
        print("  input latency ms: missing")
    for kind in ("boot", "sample", "flow_complete"):
        matching = [record for record in records if record.get("kind") == kind]
        if matching:
            print(f"  {kind}: {json.dumps(matching[-1], sort_keys=True)}")
        else:
            print(f"  {kind}: missing")

    warnings = [
        entry
        for entry in logs
        if entry.get("level") in {"warn", "warning", "error"}
        and isinstance(entry.get("message"), str)
        and not entry["message"].startswith(("GC_BROWSER|", "GC_METRICS|"))
    ]
    print(f"  unclassified console warnings/errors: {len(warnings)}")
    for warning in warnings:
        print(f"    [{warning.get('level')}] {warning.get('message')}")

    if require_flow and not flow_ok:
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path, nargs="+", help="console export or telemetry text")
    parser.add_argument(
        "--require-flow",
        action="store_true",
        help="fail unless the complete title-to-result route is present",
    )
    args = parser.parse_args()
    missing = [path for path in args.logs if not path.is_file()]
    if missing:
        for path in missing:
            print(f"missing log file: {path}", file=sys.stderr)
        return 2
    return summarize(args.logs, args.require_flow)


if __name__ == "__main__":
    raise SystemExit(main())
