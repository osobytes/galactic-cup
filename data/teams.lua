-- Teams for Slice 0. A roster lists exactly 5 player ids and must contain exactly
-- one keeper; the remaining 4 are listed in formation line order (defence -> attack),
-- to match the chosen formation's `outfield` order (see data/formations.lua).

---@class TeamData
---@field id string
---@field name string
---@field color number[]  -- {r, g, b} in 0..1
---@field formation string  -- key into data/formations.lua
---@field roster string[]  -- 5 player ids from data/players.lua
---@field squad string[]?  -- eligible player ids; defaults to roster

---@type table<string, TeamData>
return {
    nebula = {
        id = "nebula",
        name = "Nebula FC",
        color = { 0.3, 0.7, 1.0 },
        formation = "2-1-1",
        roster = { "ozzo", "brakka", "veil_nyx", "rok_tann", "zyro_vex" },
        squad = {
            "ozzo",
            "brakka",
            "veil_nyx",
            "rok_tann",
            "zyro_vex",
            "mika_olu",
            "sela_dwin",
            "tib_quell",
        },
    },
    orion = {
        id = "orion",
        name = "Orion Miners",
        color = { 1.0, 0.5, 0.3 },
        formation = "1-1-2",
        roster = { "gax_oru", "drell", "morv", "krag", "tox_vren" },
    },
}
