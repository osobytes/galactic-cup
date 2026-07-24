-- Fixed prototype loadouts. Both family and presentation ids are stored so
-- validation can reject a mechanical/presentation mismatch before a match.

---@class FixedLoadoutData
---@field id string
---@field family_id ActionFamilyId
---@field equipment_presentation_id string

---@type table<string, FixedLoadoutData>
return {
    loadout_emberguard_shield = {
        id = "loadout_emberguard_shield",
        family_id = "guard",
        equipment_presentation_id = "medieval_heater_shield",
    },
    loadout_tournament_sword = {
        id = "loadout_tournament_sword",
        family_id = "light_melee",
        equipment_presentation_id = "medieval_tournament_sword",
    },
    loadout_vector_blade = {
        id = "loadout_vector_blade",
        family_id = "light_melee",
        equipment_presentation_id = "scifi_energy_blade",
    },
    loadout_pulse_blaster = {
        id = "loadout_pulse_blaster",
        family_id = "ranged",
        equipment_presentation_id = "scifi_pulse_blaster",
    },
    loadout_spring_gloves = {
        id = "loadout_spring_gloves",
        family_id = "unarmed",
        equipment_presentation_id = "toy_spring_gloves",
    },
    loadout_foam_champion = {
        id = "loadout_foam_champion",
        family_id = "light_melee",
        equipment_presentation_id = "toy_foam_sword",
    },
}
