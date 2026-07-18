# OMP-0 browser compatibility report

Status: **incomplete with reproducible failures**. Issue
[#16](https://github.com/osobytes/galactic-cup/issues/16) now has the required
stable Linux Chrome and Firefox evidence, but Windows 11, physical-gamepad, and
Firefox JS-heap evidence are still unavailable. Missing evidence is not treated
as a pass.

## Artifact and evidence

- Source revision: `5f8e76cf46ce85f488be7a3ee8e88105cd43ab19`
- Game-package SHA-256:
  `c939d74873cb49fe8d587c66af9d7363c15580a3523846ee2ea210921c5aaef5`
- Pinned love.js revision: `495c5eb7eb55b54aaadfc21405c58f50a6d819c4`
- Raw evidence:
  [OMP-0 issue 16 Linux browser evidence](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-16-evidence-5f8e76c)
- Evidence archive SHA-256:
  `0088e7f878f0c965e77d60eda1fdc0c681132e99cf55669f0c8f29fcebc1b131`

The raw archive is a release asset rather than a committed generated artifact.
It contains browser/driver versions, OS/GPU metadata, served-file hashes,
capabilities, screenshots, console and service logs, memory samples, per-run
summaries, and the compressed Chrome performance trace.

`scripts/browser_matrix.py` creates a fresh browser profile for each viewport,
disables extensions, verifies every served file against `manifest.json`,
checks the page build ID, and refuses a dirty source artifact. It drives the
real Title → Squad → Formation → Tactic → Match → Result flow and runs
`scripts/web_report.py --require-flow`.

## Required environment matrix

| Row | Exact environment | 960×540 | 1280×720 | 1920×1080 | Status |
| --- | --- | --- | --- | --- | --- |
| L-C | Zorin OS 18.1; Chrome 150.0.7871.124; NVIDIA RTX 2070 SUPER, driver 595.71.05 | Flow pass; performance fail | Flow pass; performance fail | Flow pass; performance fail | Complete Linux evidence; hard-gate failures |
| L-F | Zorin OS 18.1; Firefox 152.0.6; geckodriver 0.37.0; hardware WebGL | Flow pass; performance fail | Flow and performance pass | Flow and performance pass | Complete except JS heap and physical gamepad |
| W-C | Windows 11; stable Chrome | Unavailable | Unavailable | Unavailable | Missing required environment |
| W-F | Windows 11; stable Firefox | Unavailable | Unavailable | Unavailable | Missing required environment |

Every exercised Linux row passed artifact boot, complete product flow,
`web_report.py --require-flow`, hardware acceleration, audio after a user
gesture, keyboard input, focus/blur recovery, resize/letterboxing, real
fullscreen entry/exit, clean Result, and unclassified-console checks.

## Startup and flow-performance results

The fixed hard gates in [`omp0_acceptance.md`](omp0_acceptance.md) were applied
without adjustment. Input-latency gates passed in every exercised row.

| Browser | Viewport | Navigation → Title screenshot | Flow performance | Recorded hard-gate miss |
| --- | ---: | ---: | --- | --- |
| Chrome 150 | 960×540 | 904.4 ms | Fail | At least 3 frame intervals over 33 ms |
| Chrome 150 | 1280×720 | 963.7 ms | Fail | Repeated >33 ms frames; draw p95 8.200 ms in sample 2 |
| Chrome 150 | 1920×1080 | 969.0 ms | Fail | Repeated >33 ms frames; draw p95 8.710/8.125 ms |
| Firefox 152 | 960×540 | 619.4 ms | Fail | Draw max 36.740 ms; at least 3 frame intervals over 33 ms |
| Firefox 152 | 1280×720 | 684.5 ms | Pass | None |
| Firefox 152 | 1920×1080 | 529.5 ms | Pass | None |

Chrome emitted no unclassified warning/error. Firefox's service channel
reported 19 known browser/driver messages per run, including WebGL renderer
deprecation and shutdown/profile-service messages. Every classification regex
is recorded in `environment.json`; zero Firefox messages remained
unclassified.

## Ten-minute stability and memory

The first viewport in each Linux browser ran for at least 615 seconds. Both
sessions reached Result, remained `running`, recovered from focus loss during
Match, and accepted a late mute input with resulting settings telemetry.
Neither passed the full-run frame-pacing gate.

| Browser | Duration | Process-tree RSS growth | Post-GC JS-heap growth | Full-run pacing | Memory result |
| --- | ---: | ---: | ---: | --- | --- |
| Chrome 150, 960×540 | 615.1 s | 12.91% | 185.76% (3,928,712 → 11,226,576 bytes) | Fail | Fail |
| Firefox 152, 960×540 | 615.1 s | 1.17% | Unavailable | Fail | Inconclusive |

Chrome uses CDP garbage collection plus `Performance.getMetrics`. Firefox
provided the required process-tree RSS series but no equivalent automated
post-GC JS-heap metric in this environment.

## Reproducible defects and remaining blockers

- [#20](https://github.com/osobytes/galactic-cup/issues/20): browser settings
  reset after reload in every Linux row.
- [#21](https://github.com/osobytes/galactic-cup/issues/21): affected browser
  rows miss the fixed frame-pacing gates.
- [#22](https://github.com/osobytes/galactic-cup/issues/22): Chrome post-GC
  JS-heap growth exceeds 25%.
- Windows 11 Chrome and Firefox runners are not attached.
- No physical standard-mapped gamepad was available; no A/B input proof was
  inferred from the ASRock LED controller exposed at `/dev/input/js0`.
- Firefox post-GC JS-heap acquisition remains unavailable.

Issue #16 and the parent compatibility issue
[#3](https://github.com/osobytes/galactic-cup/issues/3) therefore remain open.
The platform decision in [`platform_decision.md`](platform_decision.md) stays
inconclusive.
