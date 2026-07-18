-- The starting squad for Nebula FC. Content, not logic — see AGENTS.md §8.

---@alias Position "keeper"|"defender"|"midfielder"|"forward"

---@class StatBlock
---@field pace integer
---@field strength integer
---@field technique integer
---@field stamina integer
---@field mental integer

---@class PlayerData
---@field id string
---@field name string
---@field planet string
---@field position Position
---@field species string Mechanical species; remains neutral until species gameplay ships.
---@field presentation_species string? Showcase identity used by non-match UI.
---@field stats StatBlock
---@field trait string

---@type PlayerData[]
return {
    {
        id = "zyro_vex",
        name = "Zyro Vex",
        planet = "Kairon-9",
        position = "forward",
        species = "neutral",
        presentation_species = "voltari",
        stats = { pace = 8, strength = 6, technique = 7, stamina = 5, mental = 2 },
        trait = "comet_first_touch",
    },
    {
        id = "mika_olu",
        name = "Mika Olu",
        planet = "Vega Prime",
        position = "forward",
        species = "neutral",
        presentation_species = "myceloid",
        stats = { pace = 7, strength = 5, technique = 8, stamina = 6, mental = 3 },
        trait = "nebula_vision",
    },
    {
        id = "rok_tann",
        name = "Rok Tann",
        planet = "Titan Reach",
        position = "midfielder",
        species = "neutral",
        presentation_species = "terran",
        stats = { pace = 5, strength = 7, technique = 6, stamina = 7, mental = 5 },
        trait = "quantum_pass",
    },
    {
        id = "sela_dwin",
        name = "Sela Dwin",
        planet = "Andromeda Fringe",
        position = "midfielder",
        species = "neutral",
        presentation_species = "voltari",
        stats = { pace = 6, strength = 4, technique = 7, stamina = 6, mental = 6 },
        trait = "solar_flare_sprint",
    },
    {
        id = "brakka",
        name = "Brakka",
        planet = "Orion Belt",
        position = "defender",
        species = "neutral",
        presentation_species = "gravling",
        stats = { pace = 4, strength = 8, technique = 3, stamina = 7, mental = 8 },
        trait = "meteor_tackle",
    },
    {
        id = "veil_nyx",
        name = "Veil Nyx",
        planet = "Europa Deep",
        position = "defender",
        species = "neutral",
        presentation_species = "gravling",
        stats = { pace = 5, strength = 6, technique = 4, stamina = 6, mental = 7 },
        trait = "gravity_anchor",
    },
    {
        id = "ozzo",
        name = "Ozzo",
        planet = "Kairon-9",
        position = "keeper",
        species = "neutral",
        presentation_species = "terran",
        stats = { pace = 4, strength = 5, technique = 4, stamina = 8, mental = 8 },
        trait = "zero_g_reflex",
    },
    {
        id = "tib_quell",
        name = "Tib Quell",
        planet = "Mars Colony",
        position = "midfielder",
        species = "neutral",
        presentation_species = "myceloid",
        stats = { pace = 6, strength = 6, technique = 6, stamina = 5, mental = 5 },
        trait = "comet_first_touch",
    },

    -- Orion Miners: a physical asteroid-colony team (low technique, high strength/mental).
    {
        id = "gax_oru",
        name = "Gax Oru",
        planet = "Orion Belt",
        position = "keeper",
        species = "neutral",
        presentation_species = "gravling",
        stats = { pace = 4, strength = 6, technique = 3, stamina = 8, mental = 8 },
        trait = "gravity_anchor",
    },
    {
        id = "drell",
        name = "Drell",
        planet = "Orion Belt",
        position = "defender",
        species = "neutral",
        presentation_species = "gravling",
        stats = { pace = 4, strength = 9, technique = 2, stamina = 7, mental = 8 },
        trait = "meteor_tackle",
    },
    {
        id = "morv",
        name = "Morv",
        planet = "Ceres Outpost",
        position = "midfielder",
        species = "neutral",
        presentation_species = "terran",
        stats = { pace = 5, strength = 7, technique = 4, stamina = 7, mental = 6 },
        trait = "meteor_tackle",
    },
    {
        id = "krag",
        name = "Krag",
        planet = "Orion Belt",
        position = "forward",
        species = "neutral",
        presentation_species = "gravling",
        stats = { pace = 6, strength = 8, technique = 4, stamina = 6, mental = 3 },
        trait = "comet_first_touch",
    },
    {
        id = "tox_vren",
        name = "Tox Vren",
        planet = "Ceres Outpost",
        position = "forward",
        species = "neutral",
        presentation_species = "voltari",
        stats = { pace = 7, strength = 7, technique = 5, stamina = 5, mental = 3 },
        trait = "solar_flare_sprint",
    },
}
