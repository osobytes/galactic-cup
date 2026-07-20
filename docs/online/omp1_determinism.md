# OMP-1 determinism evidence

Status: **implemented; authoritative Linux runtime results recorded below**.

This report closes the OMP-1 evidence line. It proves that one complete,
recorded eight-slot fixture has a stable state boundary after every fixed
tick, that selected restore/replay windows converge, and that the existing
offline product flow remains covered. It does not implement prediction,
rollback, transport, rooms, or network presentation.

## Authoritative fixture

The checked-in `data.omp1_determinism` table is the immutable tape artifact.
It contains 7,201 canonical `InputFrame` wires (all eight stable outfield rows
on every frame), the matching 7,202 start-of-tick snapshot hashes, identity,
event counts, and restore windows. The source bot policy and its RNG are not
used during verification; they only materialize a replacement recording when
the explicit refresh command is invoked.

| Identity field | Frozen value |
| --- | --- |
| Fixture | `omp1-nebula-orion-eight-streams-v1` |
| Tape / input / snapshot versions | `1 / 1 / 1` |
| Build | `omp1-determinism-v1` |
| Source | `issue-39-canonical-recording-v1` |
| Content | `nebula-orion-showcase-content-v1` |
| Configuration | `field=960x540;duration=120;max_goals=3;tick_rate=60` |
| Tuning | Exact default blob (the canonical serialization is empty) |
| Match seed | `19` |
| Recorded source seeds | `1997, 2094, 2191, 2288, 2385, 2482, 2579, 2676` |
| Ownership | Nebula and Orion five-player rosters; four fixed outfield slots per side |

The nominal 120-second match consumes input ticks `0..7200`, then finishes at
boundary `7201`. The extra terminal tick comes from the existing repeated
floating-point countdown rather than a change to the 60 Hz authority. OMP-2
must preserve this recorded boundary or deliberately replace the countdown
with an integer tick budget and version the fixture.

## Hash and repeated-run result

Every boundary is encoded with canonical snapshot version 1 and hashed with
the browser-safe FNV-1a-64 implementation. Verification performs these three
checks:

1. Two independently constructed matches agree at every boundary.
2. Each observed boundary agrees with its literal checked-in hash.
3. FNV-1a-64 over the ordered newline-delimited boundary hashes agrees with
   the pinned sequence digest.

The authoritative values are:

```text
boundaries=7202
final_hash=b379a3a3ab5d7682
sequence_digest=0ff53075e3e626e0
score=0-1
outcome=away
final_snapshot_bytes=16859
```

The complete match produced:

```text
block=3 catch=6 claim=2 header=13 parry=1 pass=8
shot=5 tackle=421 touch=493 volley=8
```

`sim.determinism_evidence` reports the causal tick and expected/actual hash on
the first mismatch. A normal verification cannot regenerate its expectation.
The deliberate refresh command is separate:

```sh
love . --determinism-refresh
```

Refreshing the recording is a snapshot/input contract change. Review the
identity, every changed wire/hash, event counts, score, and restore windows
before committing it.

## Restore/replay windows

The complete pass captures start-of-window snapshots. Each window is later
restored independently, advanced with the same frozen wires, and compared
against every pinned boundary:

| Scenario | Start boundary | Last boundary | Required transition |
| --- | ---: | ---: | --- |
| Tackle | 23 | 26 | `tackle` at causal tick 24 |
| Keeper | 1692 | 1697 | `catch` at causal tick 1694 |
| Aerial | 1788 | 1793 | `header` at causal tick 1790 |
| Goal / kickoff | 3730 | 3735 | Away goal and home kickoff at causal tick 3732 |
| Full time | 7198 | 7201 | `finished`, zero time at causal tick 7200 |

This covers routine play in the uninterrupted complete run and the adversarial
boundaries required before rollback work. The harness uses the same canonical
identity, effective-frame, snapshot, and boundary-hash shapes as
`sim.input_tape` and `sim.replay`, while exposing a bounded incremental step
API so love.js yields to the browser between batches.

## Commands and measurements

The native gate launches two fresh LÖVE processes, compares their complete
result markers, and then reports the existing snapshot microbenchmark:

```sh
./scripts/check_determinism.sh
```

On the development machine (Zorin OS 18.1, Linux x86_64, native LÖVE 11.5),
1,000 operations at boundary tick 120 measured:

```text
snapshot_measure version=1 tick=120 bytes=15411 iterations=1000 hash=752916a99d0b62e8
snapshot_measure encode_us_each=185.695
snapshot_measure hash_with_encode_us_each=1342.830
snapshot_measure restore_us_each=85.426
```

These are observations, not thresholds. The complete two-state native
verification took approximately 25 seconds on that machine. Browser evidence
records wall-clock duration per fresh process because WebAssembly timings are
not interchangeable with native `os.clock` measurements.

For the actual love.js runtime matrix:

```sh
./scripts/web_build.sh /tmp/omp1-web
python3 scripts/browser_determinism.py \
    --artifact /tmp/omp1-web \
    --output /tmp/omp1-browser-determinism.json
```

The runner requires a clean artifact, the pinned love.js 11.5 runtime, one
result marker and no loader/runtime errors. It launches two fresh profiles per
required browser and fails, rather than skips, if Chrome or Firefox is missing.

## Supported runtime matrix

| Runtime | Executions | Result |
| --- | ---: | --- |
| Linux native LÖVE 11.5 | Two fresh processes plus in-process independent-state comparison | Pass |
| Linux Chrome / pinned love.js 11.5 | Two fresh browser profiles | Recorded by the issue #39 PR check |
| Linux Firefox / pinned love.js 11.5 | Two fresh browser profiles | Recorded by the issue #39 PR check |

All runtime rows use the one checked-in per-tick baseline. There are no
per-runtime expected hashes.

## Offline-product compatibility

The deterministic gate is additive and runs before the normal product
bootstrap only when its explicit flag is present. Native evidence disables
window/audio modules; browser evidence retains the ordinary love.js window and
yields through `love.update`.

The full headless suite continues to cover the title → squad → formation →
tactic → result → rematch loop, repeated rematches, result exits, the real
match adapter, and browser compatibility flow. The required compatibility
commands are:

```sh
love . --test
./scripts/web_smoke.sh
```

No offline input mapping, screen route, match request/result contract, or
browser artifact packaging path is replaced by this evidence work.

## Remaining OMP-2 risks

- Evidence is authoritative for the accepted Linux native/Chrome/Firefox
  scope, not Windows, macOS, or cross-architecture floating-point behavior.
- The full-time boundary currently depends on floating countdown semantics
  and consumes 7,201 inputs for a nominal 7,200-tick duration.
- Canonical snapshots intentionally include all declared simulation state and
  are about 15–17 KiB here. OMP-2 needs memory/bandwidth policy before keeping
  rollback history.
- The 850 KiB fixture favors auditability and exact per-tick regression
  diagnosis over repository size. A future compressed format must preserve
  canonical decoded bytes and versioning.
- The now-total nearest-player comparator uses descending player index for an
  exact-distance tie to preserve the existing native outcome, and quantization
  now canonicalizes negative zero. Other new
  rankings and numeric boundaries still need explicit total ordering and
  cross-runtime evidence.
- This suite proves deterministic replay only. It says nothing about late
  input policy, prediction quality, resimulation cost, network packet shape,
  state repair, or transport behavior.
