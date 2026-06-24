-- The starting squad for Nebula FC. Content, not logic — see AGENTS.md §8.

---@alias Position "keeper"|"defender"|"midfielder"|"forward"

---@class StatBlock
---@field speed integer
---@field power integer
---@field technique integer
---@field defense integer
---@field stamina integer

---@class PlayerData
---@field id string
---@field name string
---@field planet string
---@field position Position
---@field stats StatBlock
---@field trait string

---@type PlayerData[]
return {
    {
        id = "zyro_vex",
        name = "Zyro Vex",
        planet = "Kairon-9",
        position = "forward",
        stats = { speed = 8, power = 6, technique = 7, defense = 2, stamina = 5 },
        trait = "comet_first_touch",
    },
    {
        id = "mika_olu",
        name = "Mika Olu",
        planet = "Vega Prime",
        position = "forward",
        stats = { speed = 7, power = 5, technique = 8, defense = 3, stamina = 6 },
        trait = "nebula_vision",
    },
    {
        id = "rok_tann",
        name = "Rok Tann",
        planet = "Titan Reach",
        position = "midfielder",
        stats = { speed = 5, power = 7, technique = 6, defense = 5, stamina = 7 },
        trait = "quantum_pass",
    },
    {
        id = "sela_dwin",
        name = "Sela Dwin",
        planet = "Andromeda Fringe",
        position = "midfielder",
        stats = { speed = 6, power = 4, technique = 7, defense = 6, stamina = 6 },
        trait = "solar_flare_sprint",
    },
    {
        id = "brakka",
        name = "Brakka",
        planet = "Orion Belt",
        position = "defender",
        stats = { speed = 4, power = 8, technique = 3, defense = 8, stamina = 7 },
        trait = "meteor_tackle",
    },
    {
        id = "veil_nyx",
        name = "Veil Nyx",
        planet = "Europa Deep",
        position = "defender",
        stats = { speed = 5, power = 6, technique = 4, defense = 7, stamina = 6 },
        trait = "gravity_anchor",
    },
    {
        id = "ozzo",
        name = "Ozzo",
        planet = "Kairon-9",
        position = "keeper",
        stats = { speed = 4, power = 5, technique = 4, defense = 8, stamina = 8 },
        trait = "zero_g_reflex",
    },
    {
        id = "tib_quell",
        name = "Tib Quell",
        planet = "Mars Colony",
        position = "midfielder",
        stats = { speed = 6, power = 6, technique = 6, defense = 5, stamina = 5 },
        trait = "comet_first_touch",
    },

    -- Orion Miners: a physical asteroid-colony team (low technique, high power/defense).
    {
        id = "gax_oru",
        name = "Gax Oru",
        planet = "Orion Belt",
        position = "keeper",
        stats = { speed = 4, power = 6, technique = 3, defense = 8, stamina = 8 },
        trait = "gravity_anchor",
    },
    {
        id = "drell",
        name = "Drell",
        planet = "Orion Belt",
        position = "defender",
        stats = { speed = 4, power = 9, technique = 2, defense = 8, stamina = 7 },
        trait = "meteor_tackle",
    },
    {
        id = "morv",
        name = "Morv",
        planet = "Ceres Outpost",
        position = "midfielder",
        stats = { speed = 5, power = 7, technique = 4, defense = 6, stamina = 7 },
        trait = "meteor_tackle",
    },
    {
        id = "krag",
        name = "Krag",
        planet = "Orion Belt",
        position = "forward",
        stats = { speed = 6, power = 8, technique = 4, defense = 3, stamina = 6 },
        trait = "comet_first_touch",
    },
    {
        id = "tox_vren",
        name = "Tox Vren",
        planet = "Ceres Outpost",
        position = "forward",
        stats = { speed = 7, power = 7, technique = 5, defense = 3, stamina = 5 },
        trait = "solar_flare_sprint",
    },
}
