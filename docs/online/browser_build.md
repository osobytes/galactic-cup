# Browser artifact

Galactic Cup's OMP-0 browser proof uses the `2dengine/love.js` LÖVE 11.5
runtime. The runtime is fetched during the build rather than vendored into the
repository or committed as generated output. The generated `player.js` is a
small project-owned loader that fetches the package and runtime assets directly;
the upstream IndexedDB-backed loader is retained as
`third_party/lovejs-player.js` for provenance but is not the boot path.
The project loader keeps the runtime's IDBFS mount at LÖVE's save root. It
waits for the runtime's populate synchronization before the game starts and
serializes a flush after each writable save-file close, so the existing
`love.filesystem` settings path persists without a browser-specific Lua path.

IndexedDB failure is recoverable. The loader records
`window.__GALACTIC_CUP__.storage.state = "unavailable"` and emits a
`GC_BROWSER|storage_error` warning with `recoverable=true`, then continues on
the mounted in-memory filesystem. The issue #16 browser runner also loads
`?storage=unavailable` as a deterministic failure probe and requires that page
to reach Title and accept an in-memory settings change.

## Build and serve

From a clean checkout with Python 3 and network access:

```sh
./scripts/web_build.sh
./scripts/web_serve.sh build/web 8000
```

Open <http://127.0.0.1:8000/> in a desktop browser. The server adds the
cross-origin isolation and WebAssembly headers required by the runtime:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`
- `Content-Security-Policy: script-src 'self' 'unsafe-eval';`

The CSP is intentionally narrow to same-origin scripts but includes
`unsafe-eval` because the selected upstream WASM player requires it. Do not
copy these headers into a public deployment without reviewing the security
policy for that deployment.

## Packaging smoke check

The non-interactive smoke check exercises save, populate/reload, and
storage-unavailable host semantics; builds the artifact twice; compares the
deterministic `.love` packages; checks the required runtime files; validates
the ZIP entries; and verifies the pinned runtime manifest:

```sh
./scripts/web_smoke.sh
```

CI can run this command without opening a browser. A normal browser should be
used for the title-screen and complete-flow checks; those compatibility and
performance checks remain part of issue #3.

## Reproducibility and provenance

The build packages only the authored runtime inputs needed by LÖVE:
`conf.lua`, `main.lua`, and the `core/`, `data/`, `game/`, and `sim/` trees.
Specs, documentation, local tooling, and generated files are not placed in the
game package.

The generated `build/` directory is ignored by Git. Every artifact contains a
`manifest.json` with the game-package hash, source revision, runtime revision,
and hashes for the generated files. `galactic-cup.love` uses normalized ZIP
timestamps and sorted entries so identical source inputs produce identical
authored package bytes.

Runtime source and license:

- Repository: <https://github.com/2dengine/love.js>
- Pinned commit: `495c5eb7eb55b54aaadfc21405c58f50a6d819c4`
- Download archive SHA-256:
  `89b56e7953935d6cb06c454d0ee0c0d8903e433b9a94d1d6d501fb8b516f5ff6`
- Runtime license: MIT, copied into `third_party/lovejs.LICENSE.txt` in the
  generated artifact

The upstream player documents its LÖVE 11.5 support, direct `.love` loading,
browser limitations, and required server headers in its own README. The
browser artifact is a spike output, not a public release package yet.
