-- Shared combat mechanics. Equipment presentations and player appearance point
-- here by id; they never copy these tuning values.

---@alias ActionFamilyId "unarmed"|"guard"|"light_melee"|"ranged"
---@alias ActionActivation "press"|"held"|"held_release"
---@alias ActionContactKind "melee"|"guard"|"projectile"

---@class CombatOutcomeData
---@field interruption_ticks integer
---@field displacement_px number
---@field ball_spill boolean

---@class ActionFamilyData
---@field id ActionFamilyId
---@field name string
---@field activation ActionActivation
---@field contact_kind ActionContactKind
---@field windup_ticks integer
---@field active_ticks integer?
---@field held_active boolean
---@field recovery_ticks integer
---@field cooldown_ticks integer
---@field reach_px number?
---@field projectile_speed_px_per_second number?
---@field projectile_lifetime_ticks integer?
---@field front_arc_degrees number
---@field movement_multiplier number
---@field unguarded_outcome CombatOutcomeData?
---@field guarded_recoil_px number

---@type table<ActionFamilyId, ActionFamilyData>
return {
    unarmed = {
        id = "unarmed",
        name = "Unarmed",
        activation = "press",
        contact_kind = "melee",
        windup_ticks = 6,
        active_ticks = 4,
        held_active = false,
        recovery_ticks = 12,
        cooldown_ticks = 24,
        reach_px = 30,
        front_arc_degrees = 100,
        movement_multiplier = 0.8,
        unguarded_outcome = {
            interruption_ticks = 10,
            displacement_px = 8,
            ball_spill = true,
        },
        guarded_recoil_px = 6,
    },
    guard = {
        id = "guard",
        name = "Guard",
        activation = "held",
        contact_kind = "guard",
        windup_ticks = 6,
        active_ticks = nil,
        held_active = true,
        recovery_ticks = 9,
        cooldown_ticks = 0,
        reach_px = nil,
        front_arc_degrees = 120,
        movement_multiplier = 0.55,
        unguarded_outcome = nil,
        guarded_recoil_px = 0,
    },
    light_melee = {
        id = "light_melee",
        name = "Light Melee",
        activation = "press",
        contact_kind = "melee",
        windup_ticks = 12,
        active_ticks = 5,
        held_active = false,
        recovery_ticks = 21,
        cooldown_ticks = 42,
        reach_px = 42,
        front_arc_degrees = 75,
        movement_multiplier = 0.5,
        unguarded_outcome = {
            interruption_ticks = 18,
            displacement_px = 18,
            ball_spill = true,
        },
        guarded_recoil_px = 6,
    },
    ranged = {
        id = "ranged",
        name = "Ranged",
        activation = "held_release",
        contact_kind = "projectile",
        windup_ticks = 18,
        active_ticks = 1,
        held_active = false,
        recovery_ticks = 27,
        cooldown_ticks = 60,
        reach_px = nil,
        projectile_speed_px_per_second = 300,
        projectile_lifetime_ticks = 60,
        front_arc_degrees = 20,
        movement_multiplier = 0.4,
        unguarded_outcome = {
            interruption_ticks = 12,
            displacement_px = 10,
            ball_spill = true,
        },
        guarded_recoil_px = 6,
    },
}
