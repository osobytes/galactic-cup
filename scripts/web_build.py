#!/usr/bin/env python3
"""Build a deterministic browser artifact for the Galactic Cup LÖVE project."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_REPOSITORY = "https://github.com/2dengine/love.js"
RUNTIME_COMMIT = "495c5eb7eb55b54aaadfc21405c58f50a6d819c4"
RUNTIME_ARCHIVE_SHA256 = "89b56e7953935d6cb06c454d0ee0c0d8903e433b9a94d1d6d501fb8b516f5ff6"
RUNTIME_ARCHIVE_URL = f"{RUNTIME_REPOSITORY}/archive/{RUNTIME_COMMIT}.tar.gz"

PACKAGE_ROOT_FILES = ("conf.lua", "main.lua")
PACKAGE_ROOT_DIRECTORIES = ("core", "data", "game", "sim")
RUNTIME_FILES = {
    ".htaccess": ".htaccess",
    "11.5/love.js": "11.5/love.js",
    "11.5/love.wasm": "11.5/love.wasm",
    "lua/normalize1.lua": "lua/normalize1.lua",
    "lua/normalize2.lua": "lua/normalize2.lua",
    "player.js": "third_party/lovejs-player.js",
    "style.css": "style.css",
}

BROWSER_LOADER = r'''/* Galactic Cup browser bootstrap. */
(function () {
  "use strict";

  var script = document.currentScript;
  var canvas = document.getElementById("canvas");
  var spinner = document.getElementById("spinner");
  var query = new URL(script.src).searchParams;
  var version = "11.5";
  var uri = query.get("g") || "galactic-cup.love";
  var args = [];
  var browser_compat = window.__GALACTIC_CUP__ = {
    artifact: "galactic-cup-web",
    events: [],
    status: "loading",
    started_at_ms: performance.now()
  };

  function mark(name, detail) {
    var event = { name: name, at_ms: performance.now() - browser_compat.started_at_ms };
    if (detail) {
      event.detail = detail;
    }
    browser_compat.events.push(event);
    console.info("GC_BROWSER|" + name + "|at_ms=" + event.at_ms.toFixed(3) +
      (detail ? "|detail=" + detail : ""));
  }

  mark("loader_start");

  if (query.get("arg")) {
    try {
      args = JSON.parse(query.get("arg"));
      if (!Array.isArray(args)) {
        args = [String(args)];
      }
    } catch (error) {
      console.warn(error);
      args = [];
    }
  }

  canvas.oncontextmenu = function (event) {
    event.preventDefault();
  };

  function fail(error) {
    browser_compat.status = "failed";
    mark("error", String(error));
    console.error(error);
    canvas.style.display = "none";
    spinner.className = "error";
  }

  function fetch_binary(path) {
    return fetch(path, { credentials: "same-origin" }).then(function (response) {
      if (!response.ok) {
        throw new Error("Could not fetch " + path + " (HTTP " + response.status + ")");
      }
      return response.arrayBuffer().then(function (buffer) {
        return new Uint8Array(buffer);
      });
    });
  }

  function start() {
    spinner.className = "loading";
    var paths = [uri, "lua/normalize1.lua", "lua/normalize2.lua", version + "/love.wasm"];

    Promise.all(paths.map(fetch_binary))
      .then(function (files) {
        mark("assets_loaded", "count=" + files.length);
        var cache = {};
        for (var i = 0; i < paths.length; i++) {
          cache[paths[i]] = files[i];
        }
        if (cache[uri][0] !== 80 || cache[uri][1] !== 75) {
          throw new Error("The fetched resource is not a valid love package");
        }

        var Module = window.Module || {};
        window.Module = Module;
        Module.INITIAL_MEMORY = Math.min(
          4 * cache[uri].length + 2e7,
          (navigator.deviceMemory || 1) * 1e9
        );
        Module.canvas = canvas;
        Module.warn = window.onerror;
        Module.args = [uri.substring(uri.lastIndexOf("/") + 1)].concat(args);
        Module.cache = cache;
        Module.prerun = function () {
          if (Module.FS) {
            // Keep the OMP-0 proof independent of browser storage availability.
            // Persistence can be restored as part of the compatibility baseline.
            Module.FS.syncfs = function (_populate, callback) {
              callback(null);
            };
          }
          Module.FS.mkdirTree("/usr/local/share/lua/5.1");
          for (var path in cache) {
            var filename = path.split("/").pop();
            var directory = path === uri ? "/" : "/usr/local/share/lua/5.1";
            var target = path === uri ? Module.args[0] : filename;
            Module.FS.createDataFile(directory, target, cache[path], true, true, true);
          }
        };
        Module.postrun = function () {
          browser_compat.status = "running";
          mark("runtime_postrun");
          canvas.style.display = "block";
          canvas.focus();
          spinner.className = "";
        };

        var runtime = document.createElement("script");
        runtime.src = version + "/love.js";
        runtime.async = true;
        runtime.onload = function () {
          mark("runtime_script_loaded");
          try {
            window.Love(Module);
          } catch (error) {
            fail(error);
          }
        };
        runtime.onerror = function () {
          fail(new Error("Could not load the LÖVE " + version + " runtime"));
        };
        document.body.appendChild(runtime);
      })
      .catch(fail);
  }

  window.onerror = function (message) {
    mark("window_error", String(message));
    fail(message);
  };
  window.onunhandledrejection = function (event) {
    mark("unhandled_rejection", String(event.reason || "Unhandled browser promise rejection"));
    fail(event.reason || "Unhandled browser promise rejection");
  };
  window.onload = window.focus.bind(window);
  start();
})();
'''

INDEX_HTML = """<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Galactic Cup</title>
    <link rel="stylesheet" href="style.css">
  </head>
  <body>
    <canvas id="canvas" aria-label="Galactic Cup game"></canvas>
    <div id="spinner" class="pending" aria-live="polite"></div>
    <script src="player.js?g=galactic-cup.love&amp;v=11.5"></script>
  </body>
</html>
"""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_revision() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def package_paths() -> list[tuple[Path, str]]:
    files: list[tuple[Path, str]] = []
    for name in PACKAGE_ROOT_FILES:
        path = ROOT / name
        if not path.is_file():
            raise RuntimeError(f"missing package entrypoint: {name}")
        files.append((path, name))

    for directory in PACKAGE_ROOT_DIRECTORIES:
        source = ROOT / directory
        if not source.is_dir():
            raise RuntimeError(f"missing package directory: {directory}")
        for path in source.rglob("*"):
            if path.is_file():
                files.append((path, path.relative_to(ROOT).as_posix()))

    return sorted(files, key=lambda item: item[1])


def write_game_package(destination: Path) -> str:
    with zipfile.ZipFile(
        destination,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for source, name in package_paths():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes())

    return sha256(destination)


def download_runtime(destination: Path) -> Path:
    archive_path = destination / "love.js.tar.gz"
    request = urllib.request.Request(
        RUNTIME_ARCHIVE_URL,
        headers={"User-Agent": "galactic-cup-web-build/1"},
    )
    with urllib.request.urlopen(request) as response, archive_path.open("wb") as stream:
        shutil.copyfileobj(response, stream)

    actual_hash = sha256(archive_path)
    if actual_hash != RUNTIME_ARCHIVE_SHA256:
        raise RuntimeError(
            "runtime archive checksum mismatch: "
            f"expected {RUNTIME_ARCHIVE_SHA256}, got {actual_hash}"
        )

    extracted = destination / "runtime"
    extracted.mkdir()
    with tarfile.open(archive_path, mode="r:gz") as archive:
        members = archive.getmembers()
        for member in members:
            member_path = PurePosixPath(member.name)
            if (
                member_path.is_absolute()
                or ".." in member_path.parts
                or member.issym()
                or member.islnk()
            ):
                raise RuntimeError(f"unsafe runtime archive member: {member.name}")
        archive.extractall(extracted)

    roots = [path for path in extracted.iterdir() if path.is_dir()]
    if len(roots) != 1:
        raise RuntimeError("runtime archive has an unexpected top-level layout")
    return roots[0]


def copy_runtime(runtime_root: Path, output: Path) -> None:
    for source_name, destination_name in RUNTIME_FILES.items():
        source = runtime_root / source_name
        if not source.is_file():
            raise RuntimeError(f"missing runtime file: {source_name}")
        destination = output / destination_name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    license_path = output / "third_party" / "lovejs.LICENSE.txt"
    license_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(runtime_root / "license.txt", license_path)


def write_browser_loader(output: Path) -> None:
    (output / "player.js").write_text(BROWSER_LOADER, encoding="utf-8")


def write_manifest(output: Path, package_hash: str) -> None:
    files = {}
    for path in sorted(output.rglob("*")):
        if path.is_file() and path.name != "manifest.json":
            files[path.relative_to(output).as_posix()] = sha256(path)

    manifest = {
        "artifact": "galactic-cup-web",
        "game_package": {
            "path": "galactic-cup.love",
            "sha256": package_hash,
        },
        "source_revision": source_revision(),
        "runtime": {
            "repository": RUNTIME_REPOSITORY,
            "commit": RUNTIME_COMMIT,
            "archive_sha256": RUNTIME_ARCHIVE_SHA256,
            "license": "MIT with included upstream notices",
        },
        "files": files,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def build(output: Path) -> None:
    output = output.resolve()
    if output == ROOT or output == output.parent:
        raise RuntimeError(f"refusing unsafe output directory: {output}")
    if output.is_symlink():
        raise RuntimeError(f"refusing symlink output directory: {output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent, prefix=f".{output.name}.") as temp:
        staging = Path(temp) / output.name
        staging.mkdir()
        package_hash = write_game_package(staging / "galactic-cup.love")
        runtime_root = download_runtime(Path(temp))
        (staging / "index.html").write_text(INDEX_HTML, encoding="utf-8")
        copy_runtime(runtime_root, staging)
        write_browser_loader(staging)
        write_manifest(staging, package_hash)

        if output.exists():
            shutil.rmtree(output)
        staging.rename(output)

    print(f"built {output}")
    print(f"game package: {output / 'galactic-cup.love'} ({package_hash})")
    print(f"runtime commit: {RUNTIME_COMMIT}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "build" / "web",
        help="artifact directory (default: build/web)",
    )
    args = parser.parse_args()
    build(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
