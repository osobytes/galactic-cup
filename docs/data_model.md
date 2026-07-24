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
---@field planet string       -- current showcase identity copy
---@field position Position
---@field species string      -- current showcase mechanical id; neutral in shipped content
---@field presentation_species string? -- current showcase UI/pitch identity
---@field stats StatBlock
---@field trait string       -- reserved post-showcase trait id
```

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

## Post-showcase GOLISEO identity separation

The current showcase keeps presentation species directly on `PlayerData`.
Post-showcase GOLISEO work will generalize this without coupling stats to a
specific model:

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

The first combat and rendering proofs use authored player records. A later
roster generator may create them from a deterministic seed, but it must
materialize and persist the resolved values. Stats, names, or cosmetics do not
reroll per match or per load. Generated stat profiles use bounded budgets and
position-weighted archetypes rather than five independent random values.

This separation is authoritative direction but not an implemented
`PlayerData` change. The prototype content contract and randomness guardrails
live in `docs/design/prototype_theme_roster.md`.

## Parked after the showcase

- `data/traits.lua` — `TraitData` (id, name, trigger, effect)
- RPG fields layered onto a runtime `PlayerState` (xp, level, morale, fatigue) — kept separate
  from immutable `PlayerData`.
- Deterministic generated-roster materialization and cosmetic variant fields.

These shapes are not part of the active showcase scope. See `docs/showcase_release.md`.
