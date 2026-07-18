# Transport bridge

This document is the public Lua contract for issue #5. Issue #4 supplies a
bounded, asynchronous loopback seam; it does not negotiate WebRTC, synchronize
match state, predict input, or implement rollback.

## Lua API

The entry point is `require("game.transport")`:

```lua
local transport = require("game.transport")

local link = transport.fake() -- or transport.browser()
assert(link:initialize())

local input = assert(link:enqueue({
    version = 1,
    type = "input",
    seq = 0,
    tick = 120,
    payload = "opaque input payload",
}))

local received = link:poll() -- nil when the bounded queue is empty
local event = link:poll_event() -- state/error event, or nil
local metrics = link:diagnostics()
assert(link:shutdown())
```

Both adapters expose the same operations:

| Operation | Result | Semantics |
| --- | --- | --- |
| `initialize()` | `true` or `nil, error, code` | Opens the adapter and emits a `connected` state event. |
| `shutdown()` | `true` or `nil, error, code` | Clears queued messages and emits `closed`. |
| `enqueue(message)` / `send(message)` | `true` or `nil, error, code` | Validates and queues one outbound message; it never waits for a peer. |
| `poll()` | `message` or `nil, error, code` | Removes at most one inbound message, preserving insertion order. |
| `poll_event()` | `TransportEvent?` | Removes one connection/error event without throwing. |
| `state()` | `TransportState` | Returns `new`, `connected`, `disconnected`, or `closed`. |
| `diagnostics()` | `TransportDiagnostics` | Returns queue depth, bounded-capacity, counters, and the last error. |

`disconnect(reason?)` is available on both adapters for tests and host-level
disconnect reporting. It emits a `disconnected` state event followed by a
`disconnected` error event. A disconnect does not turn into a successful
reconnect implicitly; call `initialize()` again when the next transport layer
is ready.

## Envelope version 1

The Lua shape is:

```lua
---@class TransportMessage
---@field version integer -- exactly 1
---@field type "input"|"event"|"state"
---@field seq integer -- non-negative transport sequence
---@field tick integer? -- required when type == "input"
---@field payload string -- opaque UTF-8 bytes for the next protocol layer
```

The wire representation is five pipe-separated, percent-escaped fields:

```text
version | type | seq | tick-or-empty | payload
```

Only unreserved URI characters remain unescaped. Consequently, payloads may
contain pipes, newlines, percent signs, and binary-looking UTF-8 without
confusing the delimiter parser. The bridge treats payload contents as opaque;
issue #5 owns the input payload schema and any later binary encoding.

The maximum payload is 1,024 bytes. A message must have a non-negative integer
`seq`; input messages must also have a non-negative integer `tick`. Malformed
messages, unsupported versions, and oversized payloads are rejected before
queue insertion and increment diagnostics counters.

## Queueing and backpressure

The default queue limit is 64 messages per direction, and the state/error event
queue uses the same bound. Adapters accept a `queue_limit` from 1 through 256
for deterministic tests and can report the effective limit through
`diagnostics()`.

The fake adapter loops outbound messages into its inbound queue immediately,
while preserving order. If its inbound queue is full, accepted outbound
messages remain in a bounded outbound queue until `poll()` makes room. The
browser host uses the same two queues but schedules one loopback delivery with
`queueMicrotask` (or `setTimeout` as a fallback), so browser delivery is
asynchronous and never waits on a network operation in the LÖVE update call.

When the outbound queue is full, `enqueue` returns code `overflow`; the message
is dropped and `dropped_outbound`/`overflow` are incremented. Inbound injection
in the fake adapter reports the equivalent `dropped_inbound` case. There is no
unbounded buffering and no retry loop inside the adapter. If the event queue is
full, its oldest event is dropped and the newest state/error event is retained;
the `overflow` counter and `last_error` make that loss observable. Issue #5
must decide whether to drop, coalesce, or stop sampling input after observing
backpressure.

`diagnostics()` includes `outbound_depth`, `inbound_depth`, `event_depth`,
`queue_limit`, `sent`, `received`, `dropped_outbound`, `dropped_inbound`,
`malformed`, `unsupported_version`, `overflow`, and `last_error`.

## Generated browser host

`scripts/web_build.py` emits `player.js` with the maintained host object
`window.GalacticCupTransportBridge`. The Lua browser adapter calls its small
method surface through the pinned runtime's existing `love.js.eval` hook:

```text
initialize(queue_limit) -> "state|connected"
shutdown()              -> "state|closed"
enqueue(wire)           -> "ok" or "error|code|detail"
poll()                  -> wire or ""
poll_event()            -> "state|...", "error|...", or ""
disconnect(reason?)     -> "state|disconnected"
diagnostics()           -> pipe-separated diagnostic fields
```

The `GalacticCupTransportBridge` host remains a bounded loopback seam. Issue #5
adds a separate `GalacticCupWebRTCProof` host for manual peer connections while
reusing this envelope shape; it does not turn the loopback adapter into a
production network client. No JavaScript module is imported by `core/`, `data/`,
or `sim/`, and no generated artifact is checked in. The browser build smoke
check verifies both hosts are present in generated `player.js`.

## Observability contract

Expected failures are returned as `nil, message, code` and are also visible via
`poll_event()` and diagnostics. The important codes are:

- `malformed` — invalid fields or payload shape;
- `unsupported_version` — an envelope version other than 1;
- `payload_too_large` — payload over 1,024 bytes;
- `overflow` — bounded queue capacity was reached;
- `disconnected` — the host reported a peer/connection loss;
- `not_initialized`, `not_connected`, and `closed` — lifecycle misuse.

The adapter does not throw for those expected transport failures. Programmer
configuration errors such as an invalid queue limit remain assertions.
