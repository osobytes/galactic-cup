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

### MatchState / MatchInput (`sim/match.lua`)

The full pure simulation state and per-step input. See the `---@class` annotations in the file.

## Planned (not yet built)

- `data/teams.lua` — `TeamData` (id, name, color palette, roster of player ids)
- `data/formations.lua` — `FormationData` (id, name, normalized position anchors)
- `data/tactics.lua` — `TacticData` (id, name, behavior modifiers)
- `data/traits.lua` — `TraitData` (id, name, trigger, effect)
- RPG fields layered onto a runtime `PlayerState` (xp, level, morale, fatigue) — kept separate
  from immutable `PlayerData`.
