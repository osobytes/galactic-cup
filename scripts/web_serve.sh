#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
artifact_dir="${1:-$project_root/build/web}"
port="${2:-8000}"

exec python3 "$project_root/scripts/web_serve.py" "$artifact_dir" --port "$port"
