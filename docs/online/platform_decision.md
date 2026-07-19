# OMP-0 platform decision

Status: **inconclusive**. This record applies the unchanged rules in
[`omp0_acceptance.md`](omp0_acceptance.md) to evidence available on 2026-07-18.
Unavailable evidence is not a pass.

## Decision

No primary shipping path is authorized yet. Linux browser flow, pacing,
keyboard/input, persistence, letterboxing, Chrome heap, runtime stability, and
the issue #5 transport proof now pass. The required Windows 11 rows, physical
gamepad A/B, Firefox JavaScript heap, and issue #3's complete native comparison
remain unavailable. Rule 1 therefore keeps the result inconclusive, and Rule 4
cannot select native from an incomplete comparison.

## Evidence inventory

| Area | Evidence | Status |
| --- | --- | --- |
| Criteria | [Issue #1](https://github.com/osobytes/galactic-cup/issues/1), [`omp0_acceptance.md`](omp0_acceptance.md) | Fixed before implementation |
| Browser artifact | [PR #8](https://github.com/osobytes/galactic-cup/pull/8), [`browser_build.md`](browser_build.md) | Reproducible and pinned |
| Browser matrix | [Issue #16](https://github.com/osobytes/galactic-cup/issues/16), [`browser_compatibility.md`](browser_compatibility.md) | Linux automated gates pass; external controls/heap and Windows missing |
| Linux remediations | [#20 persistence](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-20-evidence-d2b175b), [#21 pacing/input](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-21-evidence-d7fc8cf), [#22 Chrome heap](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-22-evidence-dab866b), [#24 letterboxing](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-24-evidence-5813c53) | Pass |
| Corrected audio | [Chrome/Firefox source `ee56d8a`](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-16-pr29-ee56d8a) | Pass on Linux |
| Transport seam | [PR #10](https://github.com/osobytes/galactic-cup/pull/10), [`transport_bridge.md`](transport_bridge.md) | Bounded asynchronous contract available |
| WebRTC proof | [Issue #5](https://github.com/osobytes/galactic-cup/issues/5), [PR #14](https://github.com/osobytes/galactic-cup/pull/14), [`webrtc_input_proof.md`](webrtc_input_proof.md) | Both 10-minute network profiles pass |
| Native comparison | [Issue #3](https://github.com/osobytes/galactic-cup/issues/3) | Complete product-flow comparison missing |

## Criterion evaluation

| Criterion | Current evidence | Result |
| --- | --- | --- |
| Artifact boot and product flow | Linux Chrome/Firefox boot and complete Title → Result at all required viewports | Pass on Linux; Windows missing |
| Update/draw/frame/input | All six final Linux rows pass unchanged thresholds; long rows retain stability/liveness | Pass on Linux; Windows missing |
| Console and lifecycle | Clean page runtime, terminal health, focus recovery, fullscreen, keyboard, and clean Result | Pass on Linux |
| Persistence and letterboxing | Reload/populate, recoverable storage failure, tall/wide geometry, and pointer mapping pass in Chrome/Firefox | Pass on Linux |
| Audio and gamepad | Corrected-source Chrome/Firefox audio passes; physical standard-mapped A/B is unavailable | Audio pass; gamepad incomplete |
| Memory | Authoritative Chrome post-GC heap -0.27%; Firefox RSS is supplemental and Firefox JS heap is unavailable | Chrome pass; Firefox incomplete |
| Transport | Both fixed issue #5 profiles pass bounded queue/input/latency requirements | Pass |
| Native comparison | Existing machine baseline is not the complete issue #3 product-flow comparison | Incomplete |

## Required matrix

| Environment | 960×540 | 1280×720 | 1920×1080 | Decision status |
| --- | --- | --- | --- | --- |
| Linux Chrome 151 | Automated flow/performance/memory pass | Automated flow/performance pass | Automated flow/performance pass | Gamepad missing |
| Linux Firefox 152 | Automated flow/performance/stability pass | Automated flow/performance pass | Automated flow/performance pass | Gamepad and JS heap missing |
| Windows 11 Chrome | Unavailable | Unavailable | Unavailable | Required environment missing |
| Windows 11 Firefox | Unavailable | Unavailable | Unavailable | Required environment and heap missing |

The optional macOS confidence row remains unmeasured and does not replace a
required environment.

## Blocking work

- [#16](https://github.com/osobytes/galactic-cup/issues/16): attended Windows
  Chrome/Firefox packets, physical standard-gamepad A/B, and Firefox heap
  companion.
- [#3](https://github.com/osobytes/galactic-cup/issues/3): completed native
  product-flow comparison against the browser evidence.
- [#6](https://github.com/osobytes/galactic-cup/issues/6): owner acceptance of
  one primary path and one fallback after those inputs are complete.

## Risks and later assumptions

- The pinned browser runtime still requires a local-spike CSP containing
  `unsafe-eval`; that is not a production security decision.
- Firefox heap capture remains an attended manual procedure; process RSS is not
  substituted for JS heap, and privileged browser-UI automation is not enabled.
- OMP-1 may use deterministic simulation and the transport-neutral input seam,
  but must not assume browser-first delivery.
- OMP-2 may reuse the issue #5 envelope and diagnostics; rollback, signaling,
  topology, and production STUN/TURN remain unproven.
- OMP-3 must keep browser and native clients runnable until this record changes
  from inconclusive.

Reconsider this decision only when missing evidence changes—not by
reinterpreting the fixed thresholds.
