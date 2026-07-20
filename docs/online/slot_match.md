# OMP-1 fixed-slot match adapter

`sim.match` has a slot mode for an `InputOwnership` fixture. Its state retains
the validated ownership record, `slot_players` (canonical frame index to match
player index), the inverse `slot_for_player`, the source policy, and the next
expected input tick. Those values are fixture diagnostics: they do not change
after kickoff, a goal, a turnover, an aerial contact, or a legacy
`controlled` metadata change.

In slot mode `match.step` accepts only a valid, complete `InputFrame` whose
tick matches `input_tick`. A legacy `MatchInput` is rejected loudly. Every
outfielder is routed from its permanent slot; neither possession nor selected
player state participates in the routing. Both keepers have no slot and stay
under deterministic keeper AI.

## Explicit empty-slot policy

Every frame still carries all eight samples. The fixture also records one
source for each canonical slot:

- `frame` consumes the corresponding recorded `InputFrame` sample;
- `bot` replaces that row with the deterministic bot stream seeded by that
  source's required integer `seed`; and
- `neutral` replaces it with the canonical neutral sample.

Only a slot explicitly configured as `bot` receives bot behavior. Each bot
owns its own RNG state, so changing one bot's decisions does not consume or
perturb another slot's seed stream. Source kind and seed live in
`slot_input_state` alongside the ownership record and must travel with an
input tape's fixture identity.

## Offline showcase adapter

`game.match_input_adapter` remains the only user of the legacy render-side
`MatchInput`. It emits that one local stream into the stable `home_4` row of a
complete frame; the match screen explicitly configures deterministic bots for
the other seven rows. This preserves the title-to-match-to-result/rematch
product path without letting a legacy selected-player mutation alter sim slot
ownership.
