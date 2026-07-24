-- Reusable character presentation identities. Runtime meshes and materials stay
-- in game/; these records carry no stat or action-family data.

---@alias PrototypeThemeId "medieval_fantasy"|"galactic_scifi"|"toybox"

---@class CharacterPresentationData
---@field id string
---@field name string
---@field theme_id PrototypeThemeId
---@field rig_id "rig_medium"

---@type table<string, CharacterPresentationData>
return {
    medieval_rook_emberguard = {
        id = "medieval_rook_emberguard",
        name = "Rook Emberguard",
        theme_id = "medieval_fantasy",
        rig_id = "rig_medium",
    },
    medieval_bramble_quickstep = {
        id = "medieval_bramble_quickstep",
        name = "Bramble Quickstep",
        theme_id = "medieval_fantasy",
        rig_id = "rig_medium",
    },
    scifi_nova_quell = {
        id = "scifi_nova_quell",
        name = "Nova Quell",
        theme_id = "galactic_scifi",
        rig_id = "rig_medium",
    },
    scifi_axi = {
        id = "scifi_axi",
        name = 'AX-7 "Axi"',
        theme_id = "galactic_scifi",
        rig_id = "rig_medium",
    },
    toy_moxie_modular = {
        id = "toy_moxie_modular",
        name = "Moxie Modular",
        theme_id = "toybox",
        rig_id = "rig_medium",
    },
    toy_tock = {
        id = "toy_tock",
        name = "Tock",
        theme_id = "toybox",
        rig_id = "rig_medium",
    },
}
