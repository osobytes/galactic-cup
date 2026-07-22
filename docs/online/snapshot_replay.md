# OMP-1 canonical snapshot and input-tape replay

`sim.match_snapshot`, `sim.input_tape`, and `sim.replay` provide the pure
start-of-tick artifacts used to reproduce a fixed-slot match. They are
diagnostic and rollback-ready building blocks; they do not implement
prediction, transport, late-input correction, or restore-to-present
resimulation.

## Boundary and state ownership

A snapshot may be captured only between calls to `sim.match.step`. In slot
mode, `MatchState.input_tick` is the next causal `InputFrame.tick` to consume.
The hash at boundary `N` therefore describes state after input `N - 1` and
before input `N`.

Snapshot version 5 explicitly lists every `MatchState` and `MatchPlayer` field
in canonical order. It includes match RNG, ball/player action state, fixed
tick metadata, input ownership, both slot mappings, marking hysteresis,
optional wind-up/dive payloads, and the current event list. Capture and restore
deep-copy all tables, and restore reconstructs every `Vec2` metatable.

Version 2 adds the keeper's transient `save_style` and one-shot tip-event guard
to `MatchPlayer`, plus optional `save_style` data on catch/parry events.
Version 3 adds the keeper's derived `keeper_anticipation` and transient
`keeper_set` duration. Version 4 adds the keeper's derived
`keeper_aggression` and optional locked `keeper_1v1_target`. Version 5 replaces
that lock with the explicit `keeper_state` / state timer and captured
release-state, movement, shot-kind, and depth fields. Wind-up payloads now carry
the shot type; shot/save events may carry shot type, on-target status, keeper
state, and depth for deterministic telemetry. Snapshots and tapes carrying
snapshot version 4 or earlier are intentionally rejected rather than silently
restored without this behavior state. The input-tape envelope remains version 1.

The allowlists reject unknown fields, and a spec compares them with the
LuaCATS declarations in `sim/match.lua`. Adding a state field must therefore
make a conscious snapshot-version decision. Snapshot state excludes LÖVE,
render/audio objects, transport state, the fixed clock's render accumulator,
and upstream bot policy/RNG. Some captured simulation fields, such as pose
timers and events, currently feed presentation; retaining the complete
declared sim shape prevents restore from silently producing a structurally
different match.

## Canonical bytes and hash

The byte stream starts with `GCMS;` and snapshot version 5. Record names and
strings are length-prefixed; nil, booleans, strings, and numbers have distinct
tags. Arrays and sparse index maps are emitted in their declared numeric
ranges. Records use the checked-in field arrays, never `pairs` iteration.
Changing a field name, order, numeric format, or nested shape requires a new
snapshot version.

Every finite Lua number is encoded exactly from `math.frexp` as:

```text
sign : binary exponent : high 26 significand bits : low 27 significand bits
```

Positive and negative zero have separate spellings. NaN and infinities are
rejected. The significand split uses only ordinary exact double arithmetic;
the format does not depend on locale, decimal formatting, `string.pack`, FFI,
`bit`, native libraries, or integers wider than 53 exact bits.

Canonical bytes are hashed with FNV-1a-64. `core.fnv1a64` carries the value as
two 32-bit limbs and spells the digest as 16 lowercase hexadecimal characters.
Multiplication by the FNV prime is decomposed into exact limb operations below
2^53. Published vectors for empty input, `a`, `foobar`, and `hello` pin the
implementation.

## Tape identity and replay

Input tape version 1 owns deep copies of:

- its initial snapshot;
- every contiguous, already-materialized effective `InputFrame`;
- hashes for the initial and every resulting boundary; and
- immutable identity values for tape/input/snapshot versions, build, source,
  content, exact tuning, configuration, fixture, seed, 60 Hz tick rate, roster,
  and slot ownership.

Callers choose the identity strings and must derive them from immutable build
and content artifacts. The exact `sim.tuning.serialize()` value is mandatory:
tape construction and replay reject a different active tuning state. A tape
never stores bot policy or bot RNG because bot/neutral/frame producers are
upstream; only their materialized eight-row frame is replayable evidence.

`replay.run` returns every boundary hash and a newly restored final state. It
reports frozen-hash tampering without conflating it with identity rejection.
`replay.compare` drives reference and candidate tapes side by side and reports
the first difference with:

- causal input tick and resulting boundary tick/hash;
- first differing canonical state path and values; and
- both canonical input-frame wires for that causal tick.

Build/content/config/tuning/fixture/seed/tick-rate/ownership mismatches return
`identity_mismatch` before the simulation is stepped. They are not labeled
simulation divergence.

## Measurement command

Run a native-process diagnostic from a clean checkout:

```sh
./scripts/measure_snapshot.sh 1000
```

The command warms one fixed-slot match to boundary tick 120, then reports the
canonical byte size plus repeated encode, hash-including-encode, and restore
CPU cost. Timing uses `os.clock` only in the `main.lua` command entrypoint;
the core and sim modules contain no clock or I/O calls.

The numbers are machine/runtime observations for OMP-1 issue #39. They are not
native/browser equality evidence or a performance guarantee. Native and
love.js must be measured separately before making a cross-runtime cost claim.

The latest version 5 measurement was recorded by the final native determinism
gate on the project development machine:

```text
snapshot_measure version=5 tick=120 bytes=18197 iterations=100 hash=d1f7e58ef54570ea
snapshot_measure encode_ms_total=27.001 encode_us_each=270.010
snapshot_measure hash_with_encode_ms_total=154.650 hash_with_encode_us_each=1546.500
snapshot_measure restore_ms_total=12.518 restore_us_each=125.180
```

This is a reference report shape and local baseline for #39, not a threshold.
The version 5 schema is not comparable byte-for-byte with version 4 because it
replaces the locked keeper target with explicit behavior/release state. Its
authoritative complete-match final snapshot is 19,413 bytes.

## OMP-1 evidence

Issue #39 made the `nearest_n` ranking total: equal distances now break in
descending match-player index order, preserving the existing native result.
It also canonicalized negative zero at the
input quantization boundary so every valid effective frame has a decodable
canonical wire.

The complete-match repeated-run, per-tick hash, restore-window, supported
runtime, performance, and offline compatibility evidence is recorded in
[`omp1_determinism.md`](omp1_determinism.md). This snapshot/tape layer remains
diagnostic only; rollback and network behavior are still deferred to OMP-2.

Snapshot-v5 also has a bounded synthetic replay regression for the goal window
missing from the frozen 0-0 match. It constructs a real `InputTape` at the
pre-goal boundary with all keeper behavior/release fields populated, replays
three neutral frames through the goal, kickoff reset, and a post-kickoff
boundary, checks every canonical hash, and compares an independently restored
tape through `sim.replay`.
