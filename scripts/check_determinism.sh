#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
evidence_root="$(mktemp -d)"
trap 'rm -rf "$evidence_root"' EXIT

for run in 1 2; do
    started_ns="$(date +%s%N)"
    love "$project_root" --determinism >"$evidence_root/run-$run.log" 2>&1
    finished_ns="$(date +%s%N)"
    printf '%s\n' "$(( (finished_ns - started_ns) / 1000000 ))" >"$evidence_root/run-$run.ms"
    marker="$(grep '^GC_DETERMINISM|result|' "$evidence_root/run-$run.log" || true)"
    if [ "$(printf '%s\n' "$marker" | grep -c .)" -ne 1 ]; then
        cat "$evidence_root/run-$run.log"
        echo "determinism run $run did not emit exactly one result marker" >&2
        exit 1
    fi
    printf '%s\n' "$marker" >"$evidence_root/run-$run.marker"
done

if ! cmp -s "$evidence_root/run-1.marker" "$evidence_root/run-2.marker"; then
    diff -u "$evidence_root/run-1.marker" "$evidence_root/run-2.marker" || true
    echo "fresh native determinism runs disagreed" >&2
    exit 1
fi

cat "$evidence_root/run-1.marker"
echo "native determinism: two fresh processes agree (run1_ms=$(<"$evidence_root/run-1.ms"), run2_ms=$(<"$evidence_root/run-2.ms"))"
"$project_root/scripts/measure_snapshot.sh" 100
