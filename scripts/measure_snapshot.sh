#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
iterations="${1:-1000}"

cd "$project_root"
love . --snapshot-measure "$iterations"
