# OMP-0 browser compatibility report

Status: issue #3 evidence snapshot. This is a compatibility spike report, not
the final platform decision owned by issue #6.

## Artifact and collection method

The artifact was built with `scripts/web_build.sh` and served with
`scripts/web_serve.sh build/web 8000`. The compatibility instrumentation emits
`GC_BROWSER|...` loader events and `GC_METRICS|...` LÖVE events to the browser
console and native stdout. It keeps a 10-second warm-up followed by bounded
60-second samples. `scripts/web_report.py` summarizes an exported console log
and can fail a run that does not contain the complete route:

```sh
scripts/web_report.py browser-console.json --require-flow
```

For repeatable environment and viewport runs, pass the browser-only flow
argument through the generated loader:

```text
http://127.0.0.1:8000/?arg=%5B%22--compat-flow%22%5D
```

The driver clicks the existing Play, setup, and kickoff widgets through
`App:event`; it does not bypass screen state or accelerate the real match. It
records each scripted click as input telemetry and stops at Result. Keyboard
and gamepad checks remain separate manual acceptance rows.

Run date: 2026-07-18. Source revision and game-package hash are recorded in
`build/web/manifest.json` for the local artifact; generated `build/` output is
not committed.

## Compatibility matrix

| Row | Environment actually exercised | 960×540 | 1280×720 | 1920×1080 | Console / flow result |
| --- | --- | --- | --- | --- | --- |
| L-C | Zorin OS 18.1, in-app Chromium-based runtime; exact browser version unavailable through the connected browser inspector | Pending rerun | Exercised | Pending rerun | Browser booted; title → squad → formation → tactic → match reached live match in the captured run |
| L-F | Same Linux desktop, stable Firefox | Unavailable | Unavailable | Unavailable | Firefox is not installed in this worker environment |
| W-C | Windows 11, stable Chromium-based browser | Unavailable | Unavailable | Unavailable | No Windows environment is attached |
| W-F | Windows 11, stable Firefox | Unavailable | Unavailable | Unavailable | No Windows environment is attached |
| M-C | macOS, stable Chromium-based browser | Unavailable | Unavailable | Unavailable | No macOS environment is attached |

Unavailable required rows are recorded as missing evidence and are not treated
as passes. The exact Chromium version and the remaining Linux viewport rows are
also missing from this worker’s captured evidence.

## Captured L-C measurement

The 1280×720 run used the actual canvas input path: Return on the title, then
mouse clicks on the visible Squad, Formation, and Tactic actions. The captured
route reached `match` without an artifact error. The first complete 60-second
sample began after warm-up and reported:

| Metric | Browser observation | OMP-0 hard gate | Soft target |
| --- | ---: | ---: | ---: |
| Frames / updates | 4,463 / 4,464 | — | — |
| Update p95 / max | 0.845 / 2.870 ms | ≤8 / ≤33 ms | ≤4 ms p95 |
| Draw p95 / max | 3.490 / 7.120 ms | ≤8 / ≤33 ms | ≤6 ms p95 |
| Frame interval p50 / p95 | 13.380 / 19.620 ms | fewer than 3 >33 ms; none >250 ms | ≤16.7 ms p95 |
| Frame intervals over 33 / 250 ms | 1 / 0 | pass for this sample | — |
| Input response | Per-event lines added; final flow summary pending | ≤100 ms p95 | ≤50 ms p95 |

The sample is a single worker run, not a cross-machine promise. The existing
native comparison baseline remains the reference in
`docs/online/omp0_acceptance.md`: native title boot p50 509 ms / p95 516 ms,
scripted title-to-kickoff p50 605 ms / p95 675 ms, and a 60 Hz frame budget.

## Browser startup and runtime warnings

The loader reported asset fetch, runtime script load, and runtime post-run
events before the title route. No uncaught exception, unhandled rejection,
WebAssembly trap, or artifact error was observed in the captured console.

The connected in-app browser emitted repeated Electron “Insecure
Content-Security-Policy” warnings because the OMP-0 server policy intentionally
contains `unsafe-eval` for the pinned upstream WASM player. These are host
warnings, not LÖVE exceptions; they must remain classified in future exports
and reviewed before public deployment.

## Lifecycle and input checklist

| Check | Evidence | Status |
| --- | --- | --- |
| Focus / blur | LÖVE lifecycle lines appeared during browser startup | Observed; deliberate focus-loss recovery not yet rerun |
| Resize / letterboxing | Instrumentation path is present; 960/1920 evidence pending | Missing required rows |
| Fullscreen | Not exercised | Missing |
| Audio gesture | Not separately exercised | Missing |
| Gamepad | No gamepad attached | Unavailable |
| Clean Result transition | Match was live in the captured run; result transition pending | Missing |
| 10-minute stability and memory | No task-manager/heap capture in this worker | Unavailable |

Required stable-browser, Windows, lifecycle, gamepad, and memory evidence is
tracked in issue #16. Those missing rows are environment/evidence acquisition
blockers rather than reproducible browser compatibility defects. The parent
decision remains inconclusive until #16 satisfies the fixed acceptance rules.
