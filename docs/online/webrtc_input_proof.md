# OMP-0 WebRTC input proof

This is the issue #5 spike. It proves the browser transport shape needed by a
later rollback client without putting WebRTC or JavaScript in `core/`, `data/`,
or `sim/`. It does not drive a real match, provide signaling, or select
production STUN/TURN services.

## Artifact and API

Build and serve the pinned browser artifact in a secure context:

```sh
scripts/web_build.sh build/web
scripts/web_serve.sh build/web 8000
```

The generated `player.js` exposes `window.GalacticCupWebRTCProof`. It uses the
version-1 envelope from `game.transport`:

```text
version | type | seq | tick-or-empty | percent-escaped payload
```

The proof host creates two channels:

| Channel | Delivery | Use |
| --- | --- | --- |
| `control` | reliable, ordered | handshake, ping/pong, lifecycle, rejection |
| `input` | unordered, `maxRetransmits: 0` | compact tick-numbered input samples |

The input payload is at most 128 bytes and contains a six-tick recovery
history. The host refuses to add input when its observed `bufferedAmount` would
exceed a 64-message queue budget; drops and queue depth remain visible in
`diagnostics()`.

The pure Lua contract in `game/webrtc_proof.lua` mirrors the handshake, input
limits, mismatch codes, and diagnostic counters for headless tests. The
browser-only implementation lives in `scripts/webrtc_proof_host.js` and is
embedded into `player.js` by `scripts/web_build.py`.

## Manual two-context runbook

Open the same served artifact in two clean browser contexts. Keep the console
open in both contexts. The examples below use `host` and `guest` as console
variables; reload both contexts before a repeat.

1. In context A, create the host and export its offer:

   ```js
   host = GalacticCupWebRTCProof.create({ role: "host" });
   offer = await host.create_offer();
   copy(JSON.stringify(offer));
   ```

2. In context B, paste the offer, create the guest, and export its answer:

   ```js
   guest = GalacticCupWebRTCProof.create({ role: "guest" });
   answer = await guest.accept_offer(JSON.parse(prompt("Paste host offer")));
   copy(JSON.stringify(answer));
   ```

3. Back in context A, paste the answer and wait for both handshakes:

   ```js
   await host.accept_answer(JSON.parse(prompt("Paste guest answer")));
   await Promise.all([host.wait_for_handshake(), guest.wait_for_handshake()]);
   ```

4. Start the fixed 60 Hz proof for the ten-minute OMP-0 observation period in
   both contexts:

   ```js
   host.start_input({ hz: 60, duration_ms: 600000 });
   guest.start_input({ hz: 60, duration_ms: 600000 });
   ```

5. Export diagnostics at the end, then repeat after a clean refresh:

   ```js
   console.table(host.diagnostics());
   copy(JSON.stringify(host.diagnostics(), null, 2));
   console.table(guest.diagnostics());
   copy(JSON.stringify(guest.diagnostics(), null, 2));
   ```

The expected report includes handshake/build identity, role, send and receive
rates, unique ticks, history retransmits, sequence gaps, out-of-order samples,
drops, current and maximum queue depth, RTT p50/p95/max, jitter p50/p95/max,
and disconnect reason. `GC_WEBRTC|...` console markers provide a line-oriented
capture alongside the JSON diagnostics.

## Mismatch proof

Repeat the offer/answer flow with a deliberately incompatible guest. The host
must report a useful error and must not set `handshake_complete`:

```js
guest = GalacticCupWebRTCProof.create({ role: "guest", build_id: "mismatch" });
```

Use `protocol_version: 2` instead to exercise the version rejection. These are
expected failures; do not continue to input traffic after rejection.

## Evidence status

The repository contains the executable proof host, pure contract tests, build
smoke assertions, and this runbook. The current development environment does
not provide two independent browser contexts plus the required 10-minute local
and 100 ms / 1% loss runs, so no WebRTC pass is claimed here. Record browser
versions, artifact `manifest.json`, both JSON summaries, console exports, and
the clean-refresh repeat on issue #5 when the run is executed.
