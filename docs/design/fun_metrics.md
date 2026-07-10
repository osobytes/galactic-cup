# Design: Fun metrics & simulation-based balance search

**Scope:** `sim/metrics.lua`, `sim/bot.lua`, `sim/headless.lua`, `sim/sweep.lua`, `main.lua`, `spec/sim/*`

CLI (all headless, exit when done):

```
love . --sim [n]          n matches at current defaults, metric report
love . --sweep [n]        per-knob min/max sensitivity, ranked by fun impact
love . --search K1,K2 [n] greedy coordinate ascent over the named knobs
love . --eval FILE [n]    a tuning blob vs defaults on held-out seeds (paired)
```

**Status (2026-07-09):** phases 1–3 done, phase 4 (tripwire) open. Candidates
A and B are validated (and re-validated after the keeper fix) and ship as F1
presets — awaiting a hands-on playtest verdict before any change to
`sim/tuning.lua` defaults.

## Why

Balance tuning today is play-by-hand with the F1 panel: change a knob, play a
match, trust your gut. That works for feel but doesn't scale to ~30 interacting
knobs, and it can't answer "did this pass buff quietly double goals per match?"
The sim is pure, deterministic (seeded `core.rng`), and headless-capable — so we
can play thousands of unattended matches and measure the *statistical signature*
of the resulting gameplay.

We cannot measure fun. We can measure whether a match produces the shape of
matches we know are fun, and flag configurations that drift out of that shape.

## The fun proxy

Each match produces a metrics table; each metric gets a **target band** — a
trapezoid desirability function worth 1.0 inside the band, falling linearly to
0.0 at the hard limits. The per-match **fun score** is the *geometric mean* of
the desirabilities, so no config can score well by maxing five metrics while
zeroing a sixth (a weighted average would happily trade a 0 for two 1.2s; the
geometric mean will not).

Provisional bands (per 120 s match, first-to-3; revisit after the baseline run):

| Metric               | What it protects                       | Good band  | Zero at    |
| -------------------- | -------------------------------------- | ---------- | ---------- |
| `goals_total`        | matches resolve, but stay scarce       | 2 – 5      | 0 / 8      |
| `shots_per_goal`     | shots feel dangerous but not automatic | 2.5 – 6    | 1 / 25     |
| `save_rate`          | keepers matter, aren't walls           | 0.45 – 0.75| 0.15 / 0.95|
| `pass_completion`    | passing is viable but contestable      | 0.55 – 0.85| 0.25 / 1.0 |
| `turnovers_per_min`  | contested but not ping-pong (settled)  | 1 – 5      | 0.3 / 10   |
| `possession_balance` | neither side steamrolls (share of max) | 0.35 – 0.65| 0.1 / 0.9  |
| `longest_drought_s`  | no dead stretches without a chance     | 0 – 35     | –  / 80    |
| `decided_late`       | tension survives into the match        | 0.4 – 1.0  | 0.05 / –   |

Zero edges sit at *catastrophic*, not merely bad — a hard-zero plateau gives a
future optimizer no gradient to climb out of. `turnovers_per_min` counts
**settled** possession changes (a team must hold the ball 0.7 s before it
"has" it): raw ownership flicker runs ~40× higher — the ball changes hands
every second or two in poke-scrambles — and measures nothing a player would
call a turnover.

`decided_late` = time of the goal that finally decided the winner, as a
fraction of the match (draws count 1.0 — undecided to the end). Caveat when
reading the per-metric table: goalless matches therefore inflate the
`decided_late` column mean. The fun score is unaffected — `goals_total`
hard-zeros those matches — but the column looks healthier than it is whenever
goalless matches are common. `lead_changes`
is reported but unbanded for now: with a 3-goal cap the honest range is 0–2 and
it's too coarse to score.

## The human proxy (the big caveat)

AI-vs-AI matches measure the AI ecosystem, not the player's hands. The
controlled slot is driven by `sim/bot.lua`, a deliberately human-ish input
driver: it re-decides only every ~0.2 s (reaction latency), adds aim noise from
its own seeded RNG, dribbles/charges/shoots/passes with simple heuristics, and
chases/jockeys off the ball. It is not a good player; it is a *predictable
mediocre* player, which is what balance work needs.

Consequence: treat all results as **relative** (config A vs config B under the
same bot), never as absolute predictions of human experience. Big metric swings
are signal; small ones are bot artifacts until verified by hand with F1.

## Determinism & variance

- Same seed ⇒ same match ⇒ identical metrics (bot RNG is derived from the
  match seed; nothing reads `math.random` or the clock).
- Configs are compared on the **same seed set** (common random numbers), so
  differences come from the knobs, not seed luck.
- Metrics are reported as mean ± sd over N seeds; single matches are anecdotes.

## Roadmap

1. **Baseline — done.** `love . --sim [n]` plays n seeded matches on the
   default knobs and prints the metric distribution + fun score. This is the
   reference signature and a manual regression tool for any future sim change.
2. **Knob sweep — done.** `--sweep` perturbs every knob to its min and max
   over common seeds and ranks by paired fun impact. Results below.
3. **Search — done.** `--search` runs greedy coordinate ascent over chosen
   knobs; `--eval` re-checks any blob on held-out seeds. Candidates below —
   verified by humans, never auto-shipped (Goodhart's law: an optimizer will
   happily invent coin-flip keepers to farm `decided_late`).
4. **Tripwire — open.** A tiny-N smoke batch in `scripts/check.sh` that fails
   loudly when a sim change moves a banded metric outside its band at defaults.

## Baseline signature (defaults)

`love . --sim 100`, all knobs at defaults, 2026-07-09 (post keeper-fix — the
original 2026-07-05 table is superseded; the shift is recorded in the drift
log below):

```
metric                     mean        sd       min       max   desir  band
fun                       0.246     0.373     0.000     0.950       -
goals_total               0.930     0.832     0.000     3.000    0.45  [2 .. 5]
shots_per_goal           20.379     7.905     6.667    38.000    0.31  [2.5 .. 6] (n=65)
save_rate                 0.820     0.219     0.000     1.000    0.42  [0.45 .. 0.75]
pass_completion           0.522     0.054     0.367     0.658    0.88  [0.55 .. 0.85]
turnovers_per_min         1.090     0.889     0.000     3.000    0.71  [1 .. 5]
possession_balance        0.325     0.056     0.208     0.461    0.85  [0.35 .. 0.65]
longest_drought_s        17.240     5.496     9.067    38.783    1.00  [0 .. 35]
decided_late              0.719     0.331     0.046     1.000    0.88  [0.4 .. 1]
lead_changes              0.020     0.141     0.000     1.000       -
margin                    0.750     0.744     0.000     3.000       -
shots                    25.590     4.486    17.000    39.000       -
passes                   84.360     6.576    68.000   106.000       -
```

What the baseline says (under this bot — relative claims only):

- **Scoring is the weak dimension.** 0.93 goals/match against a 2–5 target,
  and 20 shots per goal: teams shoot plenty (~26/match) but conversion is dire
  and the keeper fix made it worse. 35 of 100 matches were goalless. The three
  worst desirabilities (goals 0.45, conversion 0.31, save rate 0.42) are the
  same underlying issue: shots rarely threaten.
- **The bot's team holds ~33% possession** — the human proxy is weaker than
  the AI it replaces, as expected. Keep it fixed while comparing configs.
- **Flow metrics are healthy**: droughts, decided-late, and settled turnovers
  all sit in or near band. The game's problem is not stagnation, it's payoff.
- `lead_changes` ≈ 0 follows directly from goal scarcity; it will only become
  meaningful once goals_total lives in its band.

## Phase 2: sensitivity sweep (2026-07-05)

`love . --sweep 30` — every knob to its min and max, paired against the
default baseline (fun 0.238, goals 1.10) on seeds 1–30. Knobs that matter,
ranked by paired ΔFun (±se ≈ 0.08–0.11):

| Knob                 | Best direction    | ΔFun   | Goals there |
| -------------------- | ----------------- | ------ | ----------- |
| `AI_SHOOT_RANGE`     | max (340)         | +0.56  | 3.50        |
| `AI_PASS_PRESSURE`   | min (30)          | +0.32  | 2.07        |
| `AI_STEAL_CD`        | max (2.5)         | +0.26  | 1.27        |
| `AI_HEADER_RANGE`    | max (300)         | +0.23  | 1.97        |
| `CARRIER_SETTLE`     | min (0)           | +0.20  | 1.80        |
| `JOCKEY_SLOW`        | min (0.5)         | +0.20  | 1.47        |
| `SAVE_SPEED_REF`     | min (700)         | +0.14  | 2.20        |
| `KEEPER_RESPECT_DIST`| **max is BAD**    | −0.15  | 0.53        |

Sanity checks that the harness is honest: knobs the sim ignores for an all-AI
match (`REPLAY_*`, `PASS_CHARGE_RATE`, `KEEPER_HOLD_HUMAN`, `PUNT_MAX`) came
back at *exactly* 0.000 — the pairing removes all seed noise. The story is
one-directional: everything that lets attacks finish (shoot earlier, header
from further, press less, poke less) helps, because the baseline's failure
mode is attacks that never resolve.

## Phase 3: candidates (validated on held-out seeds 1001–1060)

**Candidate A — "direct play" (the ascent winner, fun 0.912 on search seeds):**

```
AI_SHOOT_RANGE=340
AI_HEADER_RANGE=300
AI_PASS_PRESSURE=75
SAVE_SPEED_REF=700
AI_STEAL_CD=1.5
CARRIER_SETTLE=0.6
```

Held-out: **fun 0.770 vs 0.302 at defaults — paired ΔFun +0.468 ± 0.065**
(~7 se; survives the overfit haircut from 0.912). Goals 3.68, save rate 0.60,
all banded metrics ≥ 0.75 desirability.

**Candidate B — "one-knob sweet spot":**

```
AI_SHOOT_RANGE=300
```

Held-out: **ΔFun +0.388 ± 0.062** (fun 0.690, goals 2.53). One change buys
~80% of Candidate A's gain — the low-risk first ship.

Caveats before shipping either:

- ~~**Range-edge optima.**~~ Resolved by round 2 (below): with widened ranges
  the ascent kept `AI_SHOOT_RANGE=340` and `SAVE_SPEED_REF=700` — both are
  interior optima, not fence artifacts.
- **Matches got shorter.** Under A the 3-goal cap ends matches at ~78 s mean
  (min 21 s); under B ~106 s. If full-length matches matter, raise `max_goals`
  or prefer B.
- **Bot-relative.** All numbers are under the `sim/bot.lua` proxy. Verify by
  playing: both candidates ship as F1-panel presets (`data/tuning_presets.lua`,
  F4 cycles Defaults → A → B; F2 persists the choice across runs). Defaults in
  `sim/tuning.lua` stay untouched until a candidate survives hands-on play.
- `pass_completion` (~0.49) stays just below its band in every config tested —
  no knob in the current panel moves it much. If passing should feel more
  reliable, that's a *mechanics* change (lead, receiver magnetism), not a knob.

## Round 2: the optimum is real (2026-07-05)

Round 1's winner sat on three range fences, so the fences moved:
`AI_SHOOT_RANGE` max 340→480, `AI_HEADER_RANGE` max 300→420,
`SAVE_SPEED_REF` min 700→400 (the F1 sliders widened accordingly). A second
ascent then warm-started **from Candidate A** over twelve knobs — round 1's
eight plus `WHIFF_STUMBLE`, `CHARGE_RATE`, `KEEPER_RESPECT_DIST`,
`CATCH_EVEN_QUALITY` (`--search ... 30 /tmp/candidate_a.tune`).

Result: **the search found nothing.** One accepted move in two passes
(`AI_HEADER_RANGE` 300→350, +0.005 on search seeds), which a paired held-out
head-to-head (`--eval A' 60 A`) measured at **+0.009 ± 0.058 — noise**.
`AI_SHOOT_RANGE` refused 400 and 480 despite now being allowed there;
`SAVE_SPEED_REF` refused 400; none of the four new knobs improved on A.

Conclusions:

- **Candidate A is a converged local optimum**, robust to a wider search
  space. `AI_SHOOT_RANGE≈340` and `SAVE_SPEED_REF≈700` are interior sweet
  spots, not clipped values.
- The fun ridge around A is flat (~0.91 ± 0.07 on search seeds): nearby knob
  nudges neither help nor hurt much, which is what you want from a shipped
  balance — it won't be fragile to small future tweaks.
- Further gains now require either **new mechanics** (the stuck
  `pass_completion`), **a better human proxy**, or **band revisions** — not
  more knob search. Ship A (or B), play it, and recalibrate the bands against
  how it actually feels.

## Baseline drift log

Sim changes move the baseline; re-run `love . --sim 100` after touching
`sim/match.lua` and log meaningful shifts here (this is the manual tripwire
until phase 4 automates it).

- **2026-07-08 — keeper dive/save sync fix.** Saves now resolve only at glove
  contact, dives launch timed to the ball's friction-true arrival and stop at
  the intercept point, and shots that die short release to the claim logic
  (previously they were vacuumed mid-air — the "invisible wall"). Keepers got
  honestly better: baseline goals 1.30 → 0.93, save_rate 0.775 → 0.82, fun
  0.35 → 0.25. Candidate A re-validated post-fix: **ΔFun +0.466 ± 0.069** on
  held-out seeds (unchanged), goals 3.37, all bands ≥ 0.65. The scoring
  drought at defaults is worse than first measured, which strengthens the
  case for shipping a candidate.
