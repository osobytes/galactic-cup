# OMP-0 platform decision

Status: **inconclusive**. This record applies the rules fixed in
[`omp0_acceptance.md`](omp0_acceptance.md) to the evidence available on
2026-07-18. It does not change a threshold or treat an unavailable test as a
pass.

## Decision

No shipping primary path is authorized yet. Rule 1 makes the result
**inconclusive** because required environments and required metrics are
missing. Rule 4 also cannot authorize `native-download` because the evidence
set is incomplete, even though the native baseline is useful.

The eventual mapping is deterministic:

- `browser-first` primary, with `native-download` fallback, only after every
  browser hard gate passes in every required environment, issue #5 completes
  both network profiles, and the soft-target score reaches at least 80% with
  no required environment missing more than two soft targets.
- `native-download` primary, with browser investigation as fallback, only
  after the evidence is complete, the native product-flow gate passes, and a
  browser hard gate fails or the browser soft-target score is below 80%.

Until one condition is met, calling either path the primary would contradict
the OMP-0 decision rules.

## Evidence inventory

| Area | Evidence | Status |
| --- | --- | --- |
| Criteria and thresholds | [Issue #1](https://github.com/osobytes/galactic-cup/issues/1), [`omp0_acceptance.md`](omp0_acceptance.md) | Fixed before implementation; authoritative |
| Browser artifact | [PR #8](https://github.com/osobytes/galactic-cup/pull/8), [`browser_build.md`](browser_build.md) | Reproducible build, pinned runtime, local serving, and smoke check available |
| Compatibility/performance | [Issue #3](https://github.com/osobytes/galactic-cup/issues/3), [PR #9](https://github.com/osobytes/galactic-cup/pull/9), [PR #15](https://github.com/osobytes/galactic-cup/pull/15), [`browser_compatibility.md`](browser_compatibility.md) | Repeatable complete-flow driver is merged; required stable-browser matrix is not complete |
| Transport seam | [PR #10](https://github.com/osobytes/galactic-cup/pull/10), [`transport_bridge.md`](transport_bridge.md) | Bounded asynchronous contract and browser loopback available |
| WebRTC proof | [Issue #5](https://github.com/osobytes/galactic-cup/issues/5), [PR #11](https://github.com/osobytes/galactic-cup/pull/11), [PR #14](https://github.com/osobytes/galactic-cup/pull/14), [`webrtc_input_proof.md`](webrtc_input_proof.md) | Passed two corrected 10-minute browser sessions, including a clean refresh, both network profiles, bounded queues, full history recovery, and explicit mismatch rejection |
| Evidence blocker | [Issue #16](https://github.com/osobytes/galactic-cup/issues/16) | Owns stable Linux Chrome/Firefox, Windows 11 Chrome/Firefox, lifecycle, gamepad, memory, and required viewport evidence |

The current merged source revision is `f07d0cb`. The browser runtime remains
the pinned `love.js` revision and artifact policy recorded in
[`browser_build.md`](browser_build.md); generated artifacts are not committed.

## Required environment matrix

The required environments and three viewport sizes remain exactly those in
issue #1. The current report contains only a partial L-C run:

| Environment | 960×540 | 1280×720 | 1920×1080 | Decision status |
| --- | --- | --- | --- | --- |
| L-C Linux Chromium | In-app Chromium/Electron proof only; stable-browser row pending | Earlier partial flow plus transport proof; stable-browser row pending | Pending | Incomplete |
| L-F Linux Firefox | Unavailable | Unavailable | Unavailable | Missing required environment |
| W-C Windows Chromium | Unavailable | Unavailable | Unavailable | Missing required environment |
| W-F Windows Firefox | Unavailable | Unavailable | Unavailable | Missing required environment |
| M-C macOS Chromium | Unavailable | Unavailable | Unavailable | Optional confidence only |

The captured compatibility run booted and reached the live match at 1280×720
without an artifact error. The transport proof records its in-app runtime as
Chrome 148 / Electron 42.1.0, but that is not the required clean stable-browser
L-C row. Required stable Chrome/Firefox, 960×540 and 1920×1080 flow
measurements, lifecycle/gamepad checks, and memory evidence remain missing, not
failures or passes.

## Criterion evaluation

The table below evaluates every metric row in issue #1. “Partial” means a
measurement exists but does not cover the required environments, viewport, or
complete flow. A missing value is never scored as zero.

| Criterion | Current evidence | Result |
| --- | --- | --- |
| Artifact boot | #2 and the captured L-C run show a clean artifact boot; other required rows are unavailable | Partial |
| Product flow | L-C reached live match, but Result and all required environments are pending | Inconclusive |
| Update time | L-C 1280×720 sample: p95 0.845 ms, max 2.870 ms; required 960×540/full-matrix sample is missing | Partial |
| Draw time | L-C 1280×720 sample: p95 3.490 ms, max 7.120 ms; required 960×540/full-matrix sample is missing | Partial |
| Frame pacing | L-C sample had 1 frame over 33 ms and none over 250 ms; required matrix and p95 report are missing | Partial |
| Input response | Instrumentation exists, but the captured report has no final p95 result | Missing |
| Browser console | No uncaught exception was observed in the captured L-C run; Electron CSP warnings were classified | Partial |
| Runtime stability | No 10-minute product run, focus/resize recovery, or complete Result transition is evidenced | Missing |
| Memory | No 0/5/10-minute task-manager or heap evidence | Missing |
| Tick cadence | Two sessions, including a clean refresh: every peer sent 36,000 ticks over 600.000 s at 60.000 Hz | Pass |
| Input delivery | Baseline received all 36,000 messages; shaped peers recovered 343/354 physical gaps and observed all 36,000 unique ticks in both sessions | Pass |
| Queue depth | Shaped queue p95 was 4 in both sessions; max was 13 then 10 (soft target 8, hard max 32) | Pass |
| Transport latency | Shaped RTT p95 was at most 127.97 ms and jitter p95 at most 19.16 ms; all valid peers completed without error | Pass |

The native comparison has recorded boot and title-to-kickoff timings (boot p50
509 ms/p95 516 ms; scripted title-to-kickoff p50 605 ms/p95 675 ms) and a 60 Hz
frame budget. A complete native Result-flow report is not linked here, so the
native baseline is a comparison point rather than an excuse to infer a browser
decision.

## Hard gates, soft targets, and decision rules

No reproducible browser hard-gate failure is claimed from the partial L-C
snapshot. The blocker is evidence completeness:

1. L-F, W-C, and W-F have no required evidence; L-C lacks accepted stable
   Chrome coverage, two viewports, and the full lifecycle/memory/input rows.
2. Issue #3 lacks the complete product flow, input, memory, lifecycle, and
   required native-versus-browser matrix.
3. Issue #5 now passes both real-browser observation profiles, the clean-refresh
   repeat, queue/cadence/latency thresholds, history recovery, and mismatch
   rejection. No transport hard gate is currently failing.
4. The missing compatibility matrix still invokes the first decision rule:
   outcome **inconclusive**.
5. The overall 80% soft-target score cannot be computed, and neither
   browser-first nor native-download may be selected under rules 3 or 4.

The thresholds, observation periods, and required evidence ownership remain
unchanged in [`omp0_acceptance.md`](omp0_acceptance.md). The next evidence
collection must attach browser versions, OS, viewport, artifact manifest,
console logs, and the measurements listed there.

## Fallback, reconsideration, and risks

The fallback is conditional, not a current product commitment: whichever path
eventually satisfies the fixed decision rule is primary, and the other remains
the fallback described above. Reconsider the decision when the missing required
matrix or WebRTC evidence is reproduced, when a supported runtime changes, or
when a new required target is added. Do not reconsider by reinterpreting a
threshold.

| Risk or limitation | Owner / follow-up | Treatment |
| --- | --- | --- |
| Missing browser matrix and complete product-flow evidence | `osobytes`; [Issue #3](https://github.com/osobytes/galactic-cup/issues/3), [Issue #16](https://github.com/osobytes/galactic-cup/issues/16) | Blocks a final platform decision; keep both issues open |
| Two-peer WebRTC evidence and network-profile diagnostics | Completed in [PR #14](https://github.com/osobytes/galactic-cup/pull/14); [Issue #5](https://github.com/osobytes/galactic-cup/issues/5) and [Issue #12](https://github.com/osobytes/galactic-cup/issues/12) closed | No longer a decision blocker; reuse the merged suite for future regression evidence |
| CSP currently includes `unsafe-eval` for the pinned WASM player | `osobytes`; review before public deployment | Accepted for the local spike only; not a production security decision |
| Manual signaling and local-only transport proof | OMP-1/OMP-2 transport work | Accepted as explicit OMP-0 scope; no signaling or STUN/TURN commitment |
| Browser persistence remains in-memory for the spike | OMP-1 compatibility follow-up | Native behavior is not declared equivalent until persistence is tested |

## OMP-1 through OMP-3 assumptions

Until this record changes from inconclusive:

- OMP-1 may assume deterministic, seeded simulation code and the existing
  transport boundary, but must not assume browser-first delivery or production
  WebRTC availability.
- Input transport stays outside `core/`, `data/`, and `sim/`; simulation code
  consumes a transport-neutral tick/input contract.
- OMP-2 may use the issue #5 input shape and diagnostics as a proof seam, but
  rollback, state hashes, signaling, and peer topology remain unproven.
- OMP-3 must keep the browser artifact reproducible and the native client
  runnable until the missing evidence and repository-owner acceptance select a
  primary distribution path.

## Acceptance state

This document is ready for review as the honest current state, but it does not
claim issue #6 complete: the repository owner still needs to accept a final
decision after [issue #3](https://github.com/osobytes/galactic-cup/issues/3) and
[issue #16](https://github.com/osobytes/galactic-cup/issues/16) produce the
missing stable-browser matrix. WebRTC is no longer missing. No hard-gate
failure is hidden as future polish; the remaining compatibility evidence is
tracked explicitly and keeps the result inconclusive.
