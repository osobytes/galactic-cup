# Data model

All shapes are declared as LuaCATS types so data files are statically checked. The canonical
declarations live next to their data; this file is the human-readable overview.

## Implemented

### PlayerData (`data/players.lua`)

```lua
---@alias Position "keeper"|"defender"|"midfielder"|"forward"

---@class StatBlock
---@field pace integer       -- movement speed, acceleration, sprint expression
---@field strength integer   -- shot speed and physical duels
---@field technique integer  -- passing, ball control, and aerial reception
---@field stamina integer    -- sprint-tank capacity and recovery
---@field mental integer     -- positioning, composure, and keeper reading

---@class PlayerData
---@field id string          -- stable unique key
---@field name string
---@field number integer
---@field position Position
---@field stats StatBlock
---@field presentation_id string
---@field cosmetic_variant_id string?
---@field loadout_id string? -- nil for protected keepers
```

Galactic Cup's `planet`, neutral mechanical `species`,
`presentation_species`, and reserved `trait` values live in
`data/showcase_player_compatibility.lua`. That explicit compatibility table
keeps the shipped showcase presentation and simulation seam intact without
making its theme fields part of persistent GOLISEO player identity.

### Derived quantities (`sim/stats.lua`)

- `move_speed(stats)` = `BASE_MOVE + pace * MOVE_PER_PACE` (px/s)
- `shot_speed(stats)` = `BASE_SHOT + strength * SHOT_PER_STRENGTH` (px/s)
- `keeper_reach(stats)` derives defensive reach from `mental` + `pace`; defensive
  ability is not a sixth authored attribute.

These formulas bridge manager-facing stats to pitch behavior. Tune constants here.

### TeamData (`data/teams.lua`)

`id, name, color {r,g,b}, formation` (key into formations), `roster` (5 player ids,
exactly one keeper; the other 4 in formation line order defence→attack).

### FormationData (`data/formations.lua`)

`id, name, keeper Anchor, outfield Anchor[4]`. An `Anchor` is normalized `{x, y}` in an
attacking-right frame; `sim/placement.lua` converts to absolute coords and mirrors for away.

### MatchPlayer / MatchState / MatchInput (`sim/match.lua`)

The full pure 5v5 simulation: per-player runtime entity, the whole match state (players, ball,
owner, score, timer), and per-step input. See the `---@class` annotations in the file.

### TacticData (`data/tactics.lua`)

`id, name, press` (how many off-ball players hunt the ball), `line_shift` (anchor depth
bias along the attack axis, fraction of pitch), `stamina_drain` (a currently unused,
post-showcase multiplier).
Applied in `sim/match.lua`: `line_shift` adjusts outfield anchors at build time, `press`
sets `MatchState.press` which drives how many players chase per team.

### Widget / Layout (`game/ui/hit.lua`)

A `Layout` is an ordered `Widget[]` (`id, rect, kind, text, selected, data`). Pure screen defs
(`game/screens/squad|formation|tactic.lua`) build a Layout from state; `game/ui/draw.lua`
renders it; `hit.at`/`hit.find` do pure hit-testing. See AGENTS.md §9.

## GOLISEO identity and content separation

`PlayerData` owns persistent identity and authored match attributes without
coupling them to a specific model or item appearance:

```text
PlayerData
    stable identity, name, number, position, stats, loadout
        |
        +-- presentation_id --> reusable character mesh/material/rig package
        |
        +-- cosmetic variant --> palette, head/face, safe accessory choices
```

Ten persistent players may therefore reference six reusable presentation
packages while retaining different names, positions, stats, and loadouts.
Presentation choice never grants stats or a theme passive.

The reusable tables are:

- `data/character_presentations.lua` — six semantic character/rig packages;
- `data/cosmetic_variants.lua` — material, head, and safe-accessory ids;
- `data/equipment_presentations.lua` — six item appearances mapped to family ids;
- `data/action_families.lua` — the four shared mechanical tuning records;
- `data/loadouts.lua` — fixed family/equipment pairs; and
- `sim/content_validation.lua` — pure programmer-error validation for catalogs
  and the default one-of-each fixture.

Tournament Sword, Vector Blade, and Foam Champion all resolve through the same
`light_melee` table. Equipment and character presentation records contain no
stats or copied action tuning.

The first combat and rendering proofs use the existing authored player ids and
stats. A later roster generator may create them from a deterministic seed, but it must
materialize and persist the resolved values. Stats, names, or cosmetics do not
reroll per match or per load. Generated stat profiles use bounded budgets and
position-weighted archetypes rather than five independent random values.

The prototype content contract and randomness guardrails live in
`docs/design/prototype_theme_roster.md`. Runtime combat state, content identity
in snapshots/replays, and asset loading remain downstream work.

## Parked after the showcase

- `data/traits.lua` — `TraitData` (id, name, trigger, effect)
- RPG fields layered onto a runtime `PlayerState` (xp, level, morale, fatigue) — kept separate
  from immutable `PlayerData`.
- Deterministic generated-roster materialization.

These shapes are not part of the active showcase scope. See `docs/showcase_release.md`.
