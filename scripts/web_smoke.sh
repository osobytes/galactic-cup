#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
smoke_root="$(mktemp -d)"
trap 'rm -rf "$smoke_root"' EXIT

first="$smoke_root/first"
second="$smoke_root/second"
"$project_root/scripts/web_build.sh" "$first"
"$project_root/scripts/web_build.sh" "$second"

cmp "$first/galactic-cup.love" "$second/galactic-cup.love"

python3 - "$first" <<'PY'
import json
import sys
import zipfile
from pathlib import Path

artifact = Path(sys.argv[1])
required = {
    ".htaccess",
    "11.5/love.js",
    "11.5/love.wasm",
    "galactic-cup.love",
    "index.html",
    "lua/normalize1.lua",
    "lua/normalize2.lua",
    "manifest.json",
    "player.js",
    "style.css",
    "third_party/lovejs-player.js",
    "third_party/lovejs.LICENSE.txt",
}
missing = sorted(path for path in required if not (artifact / path).is_file())
if missing:
    raise SystemExit(f"missing browser artifact files: {', '.join(missing)}")

index = (artifact / "index.html").read_text(encoding="utf-8")
if 'player.js?g=galactic-cup.love&amp;v=11.5' not in index:
    raise SystemExit("index.html does not point at the packaged game and LÖVE 11.5")
loader = (artifact / "player.js").read_text(encoding="utf-8")
if "Promise.all(paths.map(fetch_binary))" not in loader:
    raise SystemExit("browser loader does not use direct deterministic asset loading")
for marker in ("window.__GALACTIC_CUP__", "GC_BROWSER|", "runtime_postrun"):
    if marker not in loader:
        raise SystemExit(f"browser loader is missing compatibility marker: {marker}")
if "GalacticCupTransportBridge" not in loader:
    raise SystemExit("browser loader does not include the transport bridge host")

with zipfile.ZipFile(artifact / "galactic-cup.love") as package:
    if package.testzip() is not None:
        raise SystemExit("game package contains a corrupt entry")
    names = set(package.namelist())
    for path in (
        "conf.lua",
        "main.lua",
        "game/app.lua",
        "game/compatibility_metrics.lua",
        "game/transport.lua",
        "sim/match.lua",
    ):
        if path not in names:
            raise SystemExit(f"game package is missing {path}")

manifest = json.loads((artifact / "manifest.json").read_text(encoding="utf-8"))
if manifest["runtime"]["commit"] != "495c5eb7eb55b54aaadfc21405c58f50a6d819c4":
    raise SystemExit("manifest runtime commit is not pinned")
print("browser artifact smoke: OK")
PY
