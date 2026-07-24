-- Authored player identities for the showcase and prototype fixtures.
-- Content, not logic — see AGENTS.md §8.

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
---@field number integer
---@field position Position
---@field stats StatBlock
---@field presentation_id string Reusable character presentation; never contributes stats.
---@field cosmetic_variant_id string? Persistent presentation-only variation.
---@field loadout_id string? Fixed prototype loadout; keepers have none.

---@type PlayerData[]
return {
    {
        id = "zyro_vex",
        name = "Zyro Vex",
        number = 9,
        position = "forward",
        stats = { pace = 8, strength = 6, technique = 7, stamina = 5, mental = 2 },
        presentation_id = "medieval_bramble_quickstep",
        cosmetic_variant_id = "bramble_berry",
        loadout_id = "loadout_spring_gloves",
    },
    {
        id = "mika_olu",
        name = "Mika Olu",
        number = 11,
        position = "forward",
        stats = { pace = 7, strength = 5, technique = 8, stamina = 6, mental = 3 },
        presentation_id = "toy_tock",
        cosmetic_variant_id = "tock_cherry",
        loadout_id = "loadout_foam_champion",
    },
    {
        id = "rok_tann",
        name = "Rok Tann",
        number = 8,
        position = "midfielder",
        stats = { pace = 5, strength = 7, technique = 6, stamina = 7, mental = 5 },
        presentation_id = "scifi_nova_quell",
        cosmetic_variant_id = "nova_cyan",
        loadout_id = "loadout_pulse_blaster",
    },
    {
        id = "sela_dwin",
        name = "Sela Dwin",
        number = 10,
        position = "midfielder",
        stats = { pace = 6, strength = 4, technique = 7, stamina = 6, mental = 6 },
        presentation_id = "scifi_axi",
        cosmetic_variant_id = "axi_orange",
        loadout_id = "loadout_emberguard_shield",
    },
    {
        id = "brakka",
        name = "Brakka",
        number = 4,
        position = "defender",
        stats = { pace = 4, strength = 8, technique = 3, stamina = 7, mental = 8 },
        presentation_id = "medieval_rook_emberguard",
        cosmetic_variant_id = "rook_ember",
        loadout_id = "loadout_emberguard_shield",
    },
    {
        id = "veil_nyx",
        name = "Veil Nyx",
        number = 5,
        position = "defender",
        stats = { pace = 5, strength = 6, technique = 4, stamina = 6, mental = 7 },
        presentation_id = "toy_moxie_modular",
        cosmetic_variant_id = "moxie_ocean",
        loadout_id = "loadout_tournament_sword",
    },
    {
        id = "ozzo",
        name = "Ozzo",
        number = 1,
        position = "keeper",
        stats = { pace = 4, strength = 5, technique = 4, stamina = 8, mental = 8 },
        presentation_id = "scifi_axi",
        cosmetic_variant_id = "axi_blue",
        loadout_id = nil,
    },
    {
        id = "tib_quell",
        name = "Tib Quell",
        number = 6,
        position = "midfielder",
        stats = { pace = 6, strength = 6, technique = 6, stamina = 5, mental = 5 },
        presentation_id = "medieval_bramble_quickstep",
        cosmetic_variant_id = "bramble_moss",
        loadout_id = "loadout_pulse_blaster",
    },

    -- Orion Miners: a physical asteroid-colony team (low technique, high strength/mental).
    {
        id = "gax_oru",
        name = "Gax Oru",
        number = 13,
        position = "keeper",
        stats = { pace = 4, strength = 6, technique = 3, stamina = 8, mental = 8 },
        presentation_id = "toy_tock",
        cosmetic_variant_id = "tock_brass",
        loadout_id = nil,
    },
    {
        id = "drell",
        name = "Drell",
        number = 2,
        position = "defender",
        stats = { pace = 4, strength = 9, technique = 2, stamina = 7, mental = 8 },
        presentation_id = "medieval_rook_emberguard",
        cosmetic_variant_id = "rook_steel",
        loadout_id = "loadout_emberguard_shield",
    },
    {
        id = "morv",
        name = "Morv",
        number = 7,
        position = "midfielder",
        stats = { pace = 5, strength = 7, technique = 4, stamina = 7, mental = 6 },
        presentation_id = "scifi_axi",
        cosmetic_variant_id = "axi_orange",
        loadout_id = "loadout_vector_blade",
    },
    {
        id = "krag",
        name = "Krag",
        number = 14,
        position = "forward",
        stats = { pace = 6, strength = 8, technique = 4, stamina = 6, mental = 3 },
        presentation_id = "toy_moxie_modular",
        cosmetic_variant_id = "moxie_sun",
        loadout_id = "loadout_pulse_blaster",
    },
    {
        id = "tox_vren",
        name = "Tox Vren",
        number = 17,
        position = "forward",
        stats = { pace = 7, strength = 7, technique = 5, stamina = 5, mental = 3 },
        presentation_id = "scifi_nova_quell",
        cosmetic_variant_id = "nova_magenta",
        loadout_id = "loadout_spring_gloves",
    },
}
