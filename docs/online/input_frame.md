# OMP-1 input-frame and slot-ownership contract

`sim.input_frame` is the pure, versioned input record for the fixed-tick
simulation. It does not gather keyboard/gamepad input, send packets, predict a
remote player, or step `sim.match`. Those adapters are deliberately deferred
to later OMP-1 and OMP-2 work.

The 60 Hz authority, tick numbering, and overload policy are documented in
[`fixed_tick.md`](fixed_tick.md). This record defines the data supplied to that
tick boundary; it does not own the render-time accumulator.

## Stable outfield ownership

A fixture has exactly eight human-input slots. Their order is canonical and
never changes during that fixture:

| Frame index | Slot id | Team | Outfield position |
| --- | --- | --- | --- |
| 1 | `home_1` | home | 1 |
| 2 | `home_2` | home | 2 |
| 3 | `home_3` | home | 3 |
| 4 | `home_4` | home | 4 |
| 5 | `away_1` | away | 1 |
| 6 | `away_2` | away | 2 |
| 7 | `away_3` | away | 3 |
| 8 | `away_4` | away | 4 |

`InputOwnership` records the selected fixture rosters as separate ordered
`rosters.home` and `rosters.away` lists before tick zero. Those lists contain
exactly the five-player fixture side, including exactly one AI keeper; the
eight slot assignments then name one outfielder from the matching side.
`input_frame.validate_ownership` requires all eight rows in canonical order,
validates the selected roster IDs against the content player index, rejects a
player selected for both sides, and rejects an assignment from the other side's
roster. It also rejects duplicate input owners and `position == "keeper"`
assignments. A session later assigns an input producer to each slot, but
neither that producer identity nor a mutable selected-player identity belongs
in this contract. Ownership does not move when possession changes. Keepers
remain AI-only and have no input slot.

An absent human source must still contribute its row: use the deterministic
neutral sample or replace the row with deterministic bot input. A frame never
omits slots. The implemented fixture source policy, bot seed identity, and
offline adapter are documented in [`slot_match.md`](slot_match.md).

## One frame per simulation tick

`InputFrame` version 1 contains a non-negative `tick` and one `InputSample`
per canonical slot. The supported tick range is `0` through `2147483647`.
The module constructs a neutral frame with:

```lua
local input_frame = require("sim.input_frame")

local frame = assert(input_frame.neutral(120))
```

Every neutral sample has zero axes, no held actions, and no edge actions. The
frame is self-contained: a recorder, bot, or transport adapter must supply all
eight samples for every tick and may not infer a missing input from render
time, the previous selected player, or hidden latch state.

## Movement quantization

Movement is two independent signed integers, `move_x` and `move_y`, each in
`[-127, 127]`. Raw normalized axes are saturated to `[-1, 1]`, multiplied by
`127`, and rounded half away from zero. The decode rule is exactly
`axis / 127`; no dead zone, normalization, or diagonal correction is hidden in
the wire format. Any gameplay-specific vector normalization remains the
responsibility of the later simulation adapter.

Use `input_frame.quantize_move(raw_x, raw_y)` at an input boundary and
`input_frame.dequantize_move(sample)` at the simulation boundary. Invalid or
non-finite axis values are rejected. This stores only integer input state, so
recording/replay and future wire parsing do not depend on platform analog-float
representation.

## Holds and edges

`held` and `edges` are independent bitmasks. A held bit describes the state
for this tick; it remains set on every tick while the source is down. An edge
bit is supplied by the input producer and is true only for the tick containing
that transition. Edges are **not** derived by replaying consecutive frames, so
a tape remains valid if a history starts at any tick.

| Mask | Held action | Meaning |
| --- | --- | --- |
| 1 | `shoot` | Charge/action button currently down. |
| 2 | `pass` | Pass/charge button currently down. |
| 4 | `sprint` | Sprint currently down. |
| 8 | `jockey` | Jockey currently down. |
| 16 | `lob` | Loft modifier currently down. |
| 32 | `aerial_strike` | First-time aerial intent currently down. |
| 64 | `aerial_acrobatic` | Acrobatic aerial modifier currently down. |

| Mask | Edge action | Meaning |
| --- | --- | --- |
| 1 | `shoot` | Shot release/commit occurred during this tick. |
| 2 | `pass` | Pass release/commit occurred during this tick. |
| 4 | `switch` | Legacy offline switch press occurred during this tick. |
| 8 | `dash` | Tackle/dash press occurred during this tick. |
| 16 | `dodge` | Juke/dodge press occurred during this tick. |

The edge names intentionally match existing match verbs, but this module does
not decide how a future multi-slot match consumes the legacy `switch` edge.
Online ownership will later make switching inapplicable without changing the
recording format. No action has implicit edge semantics: every recorder must
set the applicable `edges` bit explicitly and clear it on the next frame.

## Canonical bounded wire form

`input_frame.encode(frame)` validates and emits one ASCII form:

```text
version|tick|move_x,move_y,held,edges|... eight slot samples total
```

The field count, slot count, slot order, number spelling, axis/mask bounds,
and version are all strict. Integers have no leading zeroes (except `0`), and
`-0` is invalid. Version 1 can never exceed 148 bytes, including the largest
supported tick and all eight maximal samples. `decode` rejects a longer wire,
noncanonical number spelling, unsupported versions, missing/extra fields, and
out-of-range values. Encoding the same valid frame always produces the same
bytes; decoding then encoding a valid canonical wire reproduces those bytes.

This is an input payload candidate only. If it is later placed in the OMP-0
transport envelope, its `InputFrame.tick` must agree with that envelope's
input-message tick; the transport layer continues to treat this payload as
opaque.

## Recording identity beside a tape

An input tape is not meaningful with frames alone. Store this metadata beside
the tape or snapshot, never in an individual frame or transport envelope:

- input-frame version;
- simulation build/source identity;
- content identity for the authored player/team/formation/species data;
- gameplay configuration identity, including tuning and fixture rules;
- initial deterministic RNG seed;
- the canonical `InputOwnership` selected home/away rosters and slot mapping; and
- the fixed tick rate once issue #35 establishes it.

OMP-2 replay and rollback work must compare this identity before claiming a
hash mismatch is a simulation divergence. It is deliberately independent of
WebRTC, room, packet, or browser identities.
