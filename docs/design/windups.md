# Design: Wind-up telegraphs for shots & punts

## Why

Shots resolve the same frame the input lands: nothing is readable, nothing can
be anticipated or blocked on reaction. Real games give strikes a short wind-up
that telegraphs them.

## Player-facing behavior

- Committing a **shot/chip** (human release or AI decision) or a **keeper
  punt** starts a **0.15s wind-up**: the striker plants (moves at 30% speed,
  visible back-swing pose), then the ball releases with the parameters chosen
  at commit time.
- During the wind-up the ball is still at their feet and **can be poked away**
  — a defender who reads the shot is rewarded; the wind-up then cancels.
- Passes, headers and volleys stay instant (passing must feel snappy; aerials
  are reactions).

## Mechanics

- `MatchPlayer` gains `windup_timer number` and a pending-action payload, e.g.
  `windup_shot { dir = Vec2, speed = number, vz = number, spin = number }`
  (annotate; init in `build_team`; reset in `place_kickoff`; decrement with the
  other timers in `step`).
- In `update_ball`: where a shot/punt currently calls `release_shot`/the punt
  block, instead store the payload and set `windup_timer = SHOT_WINDUP (0.15)`.
  While `windup_timer > 0` and the player still owns the ball, inputs are
  ignored for that carrier; when it reaches 0 and they STILL own it, perform
  the stored release exactly as today. If possession was lost meanwhile, clear
  the payload silently (the tackle beat the shot).
- Movement: a player with `windup_timer > 0` moves at `0.3×` (controlled and AI
  paths).
- AI shots (space-charged, square-ball fallthrough) go through the same
  wind-up. Keeper punt too. Keeper THROWS stay instant (hands).
- Renderer: `pitch.lua` passes `windup = clamp(p.windup_timer / 0.15)` into
  `player_renderer.draw` opts; `player_renderer.lua` adds a minimal back-swing
  (lean the torso/leg trapezoid opposite `facing` by a few px × windup). Keep
  it cheap and stub-safe.

## Watch out for

- MANY existing specs fire a shot and assert same-frame release ("shooting
  releases the ball", chip specs, AI shooting spec, keeper punt spec,
  auto-fire specs, save specs that begin from a manual ball). Prefer updating
  them to step `math.ceil(0.15 * 60) + 1` frames after the shot input; do not
  delete assertions.
- `attempt_steals` must keep working on the carrier during the wind-up — that
  is the feature's risk half. Add the cancel-on-dispossession spec.
- Auto-fire at full charge should enter the wind-up exactly like a manual
  release (no double-release when the key is later released: the ball is gone
  or the payload pending — guard `windup_timer > 0` from re-commits).

## Acceptance

1. Spec: a shot input releases the ball after ~0.15s, not the same frame, with
   the charge captured at commit time.
2. Spec: a poke landing during the wind-up cancels the shot (no shot event,
   possession lost, no ball launch).
3. Spec: AI shots also wind up (telegraph is universal).
4. Full `./scripts/check.sh` green.
