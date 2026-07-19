# OMP-0 browser compatibility report

Status: **incomplete**. Stable Linux Chrome and Firefox now pass the automated
flow, pacing, keyboard/input, persistence, and letterboxing gates. Windows 11,
physical gamepad A/B, Firefox JavaScript heap, and issue #3's native comparison
are still missing. Missing evidence is not treated as a pass.

## Artifact and durable evidence

- Original full-matrix source: `5f8e76cf46ce85f488be7a3ee8e88105cd43ab19`;
  package SHA-256:
  `c939d74873cb49fe8d587c66af9d7363c15580a3523846ee2ea210921c5aaef5`;
  [raw Linux baseline](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-16-evidence-5f8e76c).
- Reviewed Chrome audio/geometry probe:
  [source `806f7a3`](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-16-review-evidence-806f7a3).
- Corrected exact-source Chrome/Firefox audio probes:
  [source `ee56d8a`](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-16-pr29-ee56d8a).
- Persistence remediation:
  [#20 evidence](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-20-evidence-d2b175b).
- Letterboxing and pointer remediation:
  [#24 evidence](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-24-evidence-5813c53).
- Authoritative Chrome heap remediation:
  [#22 evidence](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-22-evidence-dab866b).
- Final Linux pacing/input campaign:
  [#21 evidence](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-21-evidence-d7fc8cf),
  clean source `d7fc8cfcd3ebf6bfc8a4ad6e54ed86c2afb1df75`, package
  `3542846f22b64249bdef454ddbfce07d84c9ccbe620435dc68c2bf557f2f8daa`.

Raw evidence remains release assets rather than committed generated output.
Packets contain browser/driver and OS/GPU metadata, served-file hashes,
capabilities, screenshots, console/service logs, memory samples, and summaries.

## Required environment matrix

| Row | 960×540 | 1280×720 | 1920×1080 | Remaining |
| --- | --- | --- | --- | --- |
| Linux Chrome 151 | Flow/pacing/input pass; 600 s stability and Chrome heap pass | Flow/pacing/input pass | Flow/pacing/input pass | Physical gamepad |
| Linux Firefox 152 | Flow/pacing/input pass; 600 s stability pass | Flow/pacing/input pass | Flow/pacing/input pass | Physical gamepad, JS heap |
| Windows 11 Chrome | Unavailable | Unavailable | Unavailable | Attended hardware campaign |
| Windows 11 Firefox | Unavailable | Unavailable | Unavailable | Attended hardware campaign plus manual JS heap |

Every final Linux row used hardware WebGL, completed Title → Result, passed
`web_report.py --require-flow`, retained a clean page-runtime console and
terminal health, and passed the unchanged update/draw/frame/input thresholds.
Both 600-second rows retained late input/settings and Match focus recovery.
Persistence now flushes and reloads `muted=true` in both browsers, while
storage-unavailable boot remains recoverable. Tall/wide canvas geometry and
real pointer hit-testing now pass in both browsers.

The final exact-head pacing campaign's worst complete samples had at most one
frame over 33 ms and none over 250 ms. Whole-row input p95/max remained below
100 ms in all six rows. Chrome's corrected one-document, forced-GC heap
measurement changed from the original apparent leak to
`2,639,224 → 2,632,180` bytes (-0.27%), passing the fixed 25% gate.

## Controls and memory interpretation

The runner observes exactly 11 ordered samples over roughly five seconds after
entering Match. A pass requires an unmuted setting before Match, user
activation, no autoplay warning, positive master volume, and at least one
active source. Malformed, missing, non-finite, duplicate, or out-of-order
samples fail the check without aborting evidence capture.

The positive Chrome packet at source `806f7a3` is historical evidence.
Pre-fix source `4b446ceb` left the persistence probe's `muted=true` setting in
place, so its otherwise complete Chrome and Firefox probes correctly observed
zero sources. Corrected source `ee56d8a` persists `muted=false` before the
product flow; its clean Chrome 151 and Firefox 152 packets each pass with all
11 samples positive, volume 1, user activation, and no autoplay warning.

No physical standard-mapped controller was available for the Linux packets.
The attended operator must expose `mapping="standard"` and produce both
`gamepad_a` and `gamepad_b`; the ASRock LED controller at `/dev/input/js0` is
not evidence.

Firefox's recorded process-tree RSS is not JavaScript heap.
`performance.memory` is non-standard and Chromium-only, so the required
Firefox t0/t5/t10 heap companion remains manual. The concise procedure and
Mozilla sources are in [`browser_build.md`](browser_build.md).

## Remaining blockers

- Run the serialized PowerShell campaign on an unlocked hardware-accelerated
  Windows 11 desktop with audible playback, sufficient resolution, and a
  physical standard-mapped controller.
- Capture the attended Firefox t0/t5/t10 heap companion.
- Complete issue [#3](https://github.com/osobytes/galactic-cup/issues/3)'s
  native product-flow comparison.

Issue [#16](https://github.com/osobytes/galactic-cup/issues/16) and the parent
compatibility issue #3 remain open. The decision in
[`platform_decision.md`](platform_decision.md) remains inconclusive.
