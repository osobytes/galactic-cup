# OMP-2 authoritative-reference rollback laboratory

`sim.rollback_lab` is the transport-free convergence runner for OMP-2. It runs
one no-delay reference match beside one impaired rollback client and proves
that both consume the same checked-in authoritative input stream. It has no
LÖVE, display, socket, browser, or wall-clock dependency.

The runner accepts only a validated `InputTape`. The tape already contains
materialized eight-slot `InputFrame` rows and a canonical initial snapshot.
Authoritative decisions therefore belong to the tape/reference side and can
never read predicted or corrected client state. `sim.determinism_evidence`
publishes `fixture_tape()` as the narrow public seam for the frozen OMP-1
complete-match fixture; the laboratory does not reach into campaign internals
or invoke the bots that originally produced the recording.

## Execution order

For every tape frame, the laboratory:

1. steps the reference with the original frame and retains its next boundary
   in a bounded snapshot ring;
2. inserts configured local client rows immediately and sends configured
   remote rows through `sim.network_conditions`;
3. polls the current transport tick, feeds every delivery's redundant history
   oldest first, processes the whole batch, and reconciles once;
4. advances the client only to the reference's current boundary;
5. compares every newly confirmed client output boundary with the retained
   reference boundary.

Rows below the retained input floor are not filtered as “redundant.” An
`outside_window` result is an explicit `late_input_unrecoverable` failure, and
the rest of that delivery batch is still processed so the report preserves
the earliest causal late tick.

After the final input, the runner asks the network simulator to recover the
last row for every remote slot. Drain deliveries are grouped by their actual
arrival tick, with one reconciliation per group. The client catches up only to
the final reference boundary. This recovers a lost final row without
inventing more match time.

A run succeeds only when all of these are true:

- drain completed and the transport queue is empty;
- every row through the final input tick is confirmed;
- confirmed output reaches the reference's final output;
- client and reference final boundaries and hashes match;
- every initial/confirmed boundary was compared;
- no late-window or unconfirmed-below-floor failure occurred.

If confirmation falls behind the monotonic input floor, the result records
`unconfirmed_authority` even if later rows or the final drain arrive. A
completed final-row request cannot hide an older loss.

## Public API and result

`rollback_lab.run(tape, options)` returns a timing-free logical result.
Options select a named or injected network profile, network-only seed, eight
local/remote source rows, rollback window, bounded drain, optional corruption,
and an optional measurement observer.

`rollback_lab.logical_marker(result)` emits a fixed-order
`GC_ROLLBACK_LAB|result|...` line. It includes fixture/profile/seeds, source
pattern, outcome and hashes, confirmation, comparisons, prediction,
correction, rollback and resimulation totals, a sorted depth histogram,
current/peak snapshot count and bytes, bounded input/network diagnostics,
network impairment counters, and drain/late-window status.

`rollback_lab.summary(result)` provides the corresponding human-readable
report.

Intentional corruption changes one client-only input sample. The reference
continues to consume the original tape. The failed result names the causal
input tick, expected and actual boundary hashes, and the first differing
canonical snapshot path.

## Timing isolation

Pure lab/session state never reads a clock and the logical result contains no
duration. `rollback_session.new` accepts an optional injected
`measure(label, operation)` observer. The normal default calls the operation
directly. The headless runner owns `os.clock`, uses that observer for capture,
restore, resimulation, and total rollback phases, and prints a separate
`GC_ROLLBACK_LAB|timing|...` observation. Timings may vary between runs and
must never be used in marker equality or simulation decisions.

## Headless report

Run the complete frozen fixture with the fixed OMP-0 parity profile:

```sh
love . --rollback-lab omp0_parity 7302
```

Run it twice in fresh processes and compare only the logical marker:

```sh
love . --rollback-lab omp0_parity 7302 | sed -n '/^GC_ROLLBACK_LAB|result|/p'
love . --rollback-lab omp0_parity 7302 | sed -n '/^GC_ROLLBACK_LAB|result|/p'
```

The two result lines must be identical. The separate timing lines are
observations and are expected to differ.

To prove divergence diagnostics fail loudly, append `corrupt`:

```sh
love . --rollback-lab clean 7302 corrupt
```

That command intentionally exits non-zero after reporting the causal mismatch.
