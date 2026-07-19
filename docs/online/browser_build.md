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

The generated host keeps the 960×540 logical canvas at 16:9. Non-16:9
windowed viewports center the largest fitting canvas rectangle over black
bars; the runtime maps pointer input through the resulting scale and offset.

## Packaging smoke check

The non-interactive smoke check exercises save, populate/reload, and
storage-unavailable host semantics; builds the artifact twice; compares the
deterministic `.love` packages; checks the required runtime files; validates
the ZIP entries; verifies the pinned runtime manifest; and self-tests the
expected 800×540 tall, 1280×540 wide, and required 16:9 canvas geometry:

```sh
./scripts/web_smoke.sh
```

CI can run this command without opening a browser. A normal browser should be
used for the title-screen and complete-flow checks; those compatibility and
performance checks remain part of issue #3.

## Evidence campaign

The evidence runner needs Python 3.11 or newer and the exact Selenium version
in `scripts/browser_matrix-requirements.txt`. Install it in a disposable
environment before running `scripts/browser_matrix.py`; browser and driver
discovery is delegated to pinned Selenium 4.43.0.

On an attended Windows 11 host, install current stable Chrome and Firefox, then
run from PowerShell:

```powershell
.\scripts\windows_browser_campaign.ps1
```

The entrypoint creates an evidence-only virtual environment, builds and serves
the artifact, runs the 600-second Chrome matrix followed by Firefox, stops the
server in cleanup, and archives each packet. Raw packets, ZIPs, server logs,
operator observations, and `campaign-summary.json` are under
`.cache\omp0-windows-campaign\<timestamp>\` by default and remain ignored.
Each packet's `environment.json` includes a bounded
`Win32_VideoController` inventory, so Intel and AMD adapters are retained
alongside any `nvidia-smi` result.

Keep the desktop unlocked and foregrounded with hardware acceleration enabled,
Windows scaling at 100%, and enough physical resolution for an exact
1920×1080 browser viewport (2560×1440 or larger is recommended). Enable audible
playback and connect one physical controller exposed by the browser with
`mapping="standard"`; listen during the opening flow and press physical A then
B in each browser. Do not substitute a virtual HID or infer a pass from a
connected device without both input events. No Actions workflow is provided:
the fixed attended desktop, GPU/audio, resolution, and physical-input
requirements are not available on an eligible repository runner.

### Firefox heap companion

Firefox process-tree RSS remains useful supplemental process memory, but it is
not JavaScript heap. `performance.memory` is a non-standard Chromium-only API,
so capture Firefox heap manually against the same clean artifact revision:

1. Let the game tab complete the compatibility flow and reach its stable
   Result state. Open that tab's Firefox DevTools **Memory** panel.
2. At t0, t5, and t10, open `about:memory`, click **Minimize memory usage** to
   force GC/CC, optionally select **anonymize**, and save a `.json.gz` report.
   Return to the game tab's Memory panel immediately, take a tab-scoped heap
   snapshot, and save the `.fxsnapshot` with the matching checkpoint label.
3. Retain all six files with the automated Firefox packet, exact source/package
   hashes, browser version, and checkpoint times. Compare the tab snapshots;
   report the `about:memory` files separately as Firefox-wide companion data.

Mozilla documents
[`about:memory` GC/CC and reports](https://firefox-source-docs.mozilla.org/performance/memory/about_colon_memory.html),
the [Firefox Memory tool](https://firefox-source-docs.mozilla.org/devtools-user/memory/index.html),
and [snapshot save/diff operations](https://firefox-source-docs.mozilla.org/performance/memory/basic_operations.html).
MDN documents
[`performance.memory` as non-standard and Chromium-only](https://developer.mozilla.org/en-US/docs/Web/API/Performance/memory).
This remains a manual handoff: geckodriver's
[`--allow-system-access`](https://firefox-source-docs.mozilla.org/testing/geckodriver/Flags.html)
grants browser-UI-process privileges and full system access, so it is not
enabled without a separate validated automation design.

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
