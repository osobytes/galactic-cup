#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
output_dir="${1:-$project_root/build/web}"

exec python3 "$project_root/scripts/web_build.py" --output "$output_dir"
