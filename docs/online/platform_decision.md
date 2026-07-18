# OMP-0 platform decision

Status: **inconclusive**. This record applies the fixed rules in
[`omp0_acceptance.md`](omp0_acceptance.md) to the evidence available on
2026-07-18. It does not move a threshold or turn unavailable evidence into a
pass.

## Decision

No primary shipping path is authorized yet.

- `browser-first` with `native-download` fallback requires every browser hard
  gate to pass in every required environment, issue #5's transport profiles to
  pass, and the fixed soft-target score to qualify.
- `native-download` with browser investigation as fallback requires a complete
  evidence set, a passing native product-flow baseline, and either a browser
  hard-gate failure or a sub-80% browser soft-target score.

The Linux matrix now contains reproducible browser hard-gate failures, but
Windows 11, physical-gamepad, and some heap evidence are still unavailable.
Rule 1 therefore keeps the result inconclusive; Rule 4 does not allow the
native path to be selected from an incomplete comparison.

## Evidence inventory

| Area | Evidence | Status |
| --- | --- | --- |
| Criteria | [Issue #1](https://github.com/osobytes/galactic-cup/issues/1), [`omp0_acceptance.md`](omp0_acceptance.md) | Fixed before implementation |
| Browser artifact | [PR #8](https://github.com/osobytes/galactic-cup/pull/8), [`browser_build.md`](browser_build.md) | Reproducible and pinned |
| Browser matrix | [Issue #16](https://github.com/osobytes/galactic-cup/issues/16), [`browser_compatibility.md`](browser_compatibility.md), [raw Linux evidence](https://github.com/osobytes/galactic-cup/releases/tag/omp0-issue-16-evidence-5f8e76c) | Linux complete except gamepad/Firefox heap; Windows missing |
| Transport seam | [PR #10](https://github.com/osobytes/galactic-cup/pull/10), [`transport_bridge.md`](transport_bridge.md) | Bounded asynchronous contract available |
| WebRTC proof | [Issue #5](https://github.com/osobytes/galactic-cup/issues/5), [PR #14](https://github.com/osobytes/galactic-cup/pull/14), [`webrtc_input_proof.md`](webrtc_input_proof.md) | Both 10-minute network profiles pass |

The browser evidence is tied to source
`5f8e76cf46ce85f488be7a3ee8e88105cd43ab19`, game package
`c939d74873cb49fe8d587c66af9d7363c15580a3523846ee2ea210921c5aaef5`,
and the pinned love.js revision documented in `browser_build.md`.

## Criterion evaluation

| Criterion | Current evidence | Result |
| --- | --- | --- |
| Artifact boot | Linux Chrome/Firefox boot to a Title screenshot in 529–969 ms at all required viewports | Pass on Linux; Windows missing |
| Product flow | Every Linux row completes Title → Result and passes `web_report.py --require-flow` | Pass on Linux; Windows missing |
| Update/draw/frame/input | Chrome fails pacing at all viewports; Firefox fails at 960×540 and passes at 1280×720/1920×1080; input gates pass | Hard-gate failures |
| Browser console | Chrome has zero warnings/errors; Firefox has zero unclassified messages after recorded service classifications | Pass on Linux |
| Lifecycle and controls | Focus recovery during Match, resize, fullscreen, audio gesture, keyboard, and clean Result pass | Pass on Linux; physical gamepad missing |
| Runtime stability | Both 615-second Linux runs remain live and accept late input, but both fail full-run pacing | Fail |
| Memory | Chrome RSS +12.91%, post-GC heap +185.76%; Firefox RSS +1.17%, heap unavailable | Chrome fail; Firefox inconclusive |
| Persistence | Mute resets on reload in every Linux row | Fail |
| Tick/input/queue/latency transport | Issue #5 completed both fixed 10-minute browser profiles with bounded queues and full input recovery | Pass |

## Required matrix

| Environment | 960×540 | 1280×720 | 1920×1080 | Decision status |
| --- | --- | --- | --- | --- |
| Linux Chrome 150 | Flow pass; performance fail | Flow pass; performance fail | Flow pass; performance fail | Complete with failures |
| Linux Firefox 152 | Flow pass; performance fail | Flow/performance pass | Flow/performance pass | Gamepad and JS heap missing |
| Windows 11 Chrome | Unavailable | Unavailable | Unavailable | Missing required environment |
| Windows 11 Firefox | Unavailable | Unavailable | Unavailable | Missing required environment |

The optional macOS confidence row remains unmeasured and does not replace a
required environment.

## Blocking work

- [#20](https://github.com/osobytes/galactic-cup/issues/20) restores browser
  settings persistence.
- [#21](https://github.com/osobytes/galactic-cup/issues/21) owns the measured
  frame-pacing failures.
- [#22](https://github.com/osobytes/galactic-cup/issues/22) owns Chrome
  post-GC heap growth.
- [#16](https://github.com/osobytes/galactic-cup/issues/16) still owns Windows
  Chrome/Firefox, physical-gamepad proof, and Firefox heap evidence.
- [#3](https://github.com/osobytes/galactic-cup/issues/3) must compare the
  completed browser evidence with the complete native product-flow baseline.

Issue [#6](https://github.com/osobytes/galactic-cup/issues/6) remains open
until those inputs let the repository owner accept one primary path and one
fallback under the fixed rules.

## Risks and later assumptions

- The pinned browser runtime still requires a local-spike CSP containing
  `unsafe-eval`; that is not a production security decision.
- OMP-1 may use the deterministic simulation and transport-neutral input seam,
  but must not assume browser-first delivery.
- OMP-2 may reuse the issue #5 input envelope and diagnostics; rollback,
  signaling, topology, and production STUN/TURN remain unproven.
- OMP-3 must keep both the reproducible browser artifact and native client
  runnable until this record changes from inconclusive.

Reconsider this decision only when the missing required evidence or focused
defects change—not by reinterpreting the thresholds.
