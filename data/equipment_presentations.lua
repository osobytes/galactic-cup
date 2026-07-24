-- Equipment appearance maps onto shared action families. Runtime models,
-- sockets, effects, and audio stay outside data/.

---@alias EquipmentAttachment "left_hand"|"right_hand"|"both_hands"

---@class EquipmentPresentationData
---@field id string
---@field name string
---@field theme_id PrototypeThemeId
---@field family_id ActionFamilyId
---@field attachment EquipmentAttachment

---@type table<string, EquipmentPresentationData>
return {
    medieval_heater_shield = {
        id = "medieval_heater_shield",
        name = "Emberguard Shield",
        theme_id = "medieval_fantasy",
        family_id = "guard",
        attachment = "left_hand",
    },
    medieval_tournament_sword = {
        id = "medieval_tournament_sword",
        name = "Tournament Sword",
        theme_id = "medieval_fantasy",
        family_id = "light_melee",
        attachment = "right_hand",
    },
    scifi_energy_blade = {
        id = "scifi_energy_blade",
        name = "Vector Blade",
        theme_id = "galactic_scifi",
        family_id = "light_melee",
        attachment = "right_hand",
    },
    scifi_pulse_blaster = {
        id = "scifi_pulse_blaster",
        name = "Pulse Blaster",
        theme_id = "galactic_scifi",
        family_id = "ranged",
        attachment = "right_hand",
    },
    toy_spring_gloves = {
        id = "toy_spring_gloves",
        name = "Spring Gloves",
        theme_id = "toybox",
        family_id = "unarmed",
        attachment = "both_hands",
    },
    toy_foam_sword = {
        id = "toy_foam_sword",
        name = "Foam Champion",
        theme_id = "toybox",
        family_id = "light_melee",
        attachment = "right_hand",
    },
}
