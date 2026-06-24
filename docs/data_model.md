# Data model

All shapes are declared as LuaCATS types so data files are statically checked. The canonical
declarations live next to their data; this file is the human-readable overview.

## Implemented

### PlayerData (`data/players.lua`)

```lua
---@alias Position "keeper"|"defender"|"midfielder"|"forward"

---@class StatBlock
---@field speed integer      -- movement speed on the pitch
---@field power integer      -- shot speed / physical duels
---@field technique integer  -- ball control, passing (M4)
---@field defense integer    -- tackling, interceptions (M4)
---@field stamina integer    -- fatigue resistance (M4)

---@class PlayerData
---@field id string          -- stable unique key
---@field name string
---@field planet string
---@field position Position
---@field stats StatBlock
---@field trait string       -- trait id (M4)
```

### Derived quantities (`sim/stats.lua`)

- `move_speed(stats)` = `BASE_MOVE + speed * MOVE_PER_SPEED` (px/s)
- `shot_speed(stats)` = `BASE_SHOT + power * SHOT_PER_POWER` (px/s)

These are the M1 bridge from manager stats to pitch behavior. Tune constants here.

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
bias along the attack axis, fraction of pitch), `stamina_drain` (multiplier; stub for M4).
Applied in `sim/match.lua`: `line_shift` adjusts outfield anchors at build time, `press`
sets `MatchState.press` which drives how many players chase per team.

### Widget / Layout (`game/ui/hit.lua`)

A `Layout` is an ordered `Widget[]` (`id, rect, kind, text, selected, data`). Pure screen defs
(`game/screens/squad|formation|tactic.lua`) build a Layout from state; `game/ui/draw.lua`
renders it; `hit.at`/`hit.find` do pure hit-testing. See AGENTS.md §9.

## Planned (not yet built)

- `data/traits.lua` — `TraitData` (id, name, trigger, effect)
- RPG fields layered onto a runtime `PlayerState` (xp, level, morale, fatigue) — kept separate
  from immutable `PlayerData`.
