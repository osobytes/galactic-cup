---@alias PlayerPoseId
---| "keeper_dive"
---| "aerial_bicycle"
---| "aerial_action"
---| "combat_knockback"
---| "combat_stagger"
---| "combat_guard"
---| "combat_active"
---| "combat_windup"
---| "combat_aim"
---| "combat_recovery"
---| "soccer_windup"
---| "slide"
---| "locomotion"

---@alias PlayerPoseSource "soccer"|"combat"|"locomotion"

---@class PlayerPoseSelection
---@field id PlayerPoseId
---@field priority integer
---@field source PlayerPoseSource

---@class PlayerPoseModule
local player_pose = {}

-- One authority owns overlap precedence. Outfield presentation work extends
-- this ordered contract instead of adding renderer-local condition chains.
player_pose.PRIORITY = {
    keeper_dive = 100,
    aerial_bicycle = 95,
    aerial_action = 94,
    combat_knockback = 90,
    combat_stagger = 89,
    combat_guard = 84,
    combat_active = 83,
    combat_windup = 82,
    combat_aim = 81,
    combat_recovery = 80,
    soccer_windup = 70,
    slide = 60,
    locomotion = 0,
}

---@param id PlayerPoseId
---@param source PlayerPoseSource
---@return PlayerPoseSelection
local function selection(id, source)
    return { id = id, priority = assert(player_pose.PRIORITY[id]), source = source }
end

---@param player MatchPlayer
---@param combat CombatPlayerPresentation?
---@return PlayerPoseSelection
function player_pose.select(player, combat)
    if player.is_keeper and player.dive_timer > 0 then
        return selection("keeper_dive", "soccer")
    elseif player.aerial_timer > 0 and player.aerial_style == "bicycle" then
        return selection("aerial_bicycle", "soccer")
    elseif player.aerial_timer > 0 and player.aerial_style ~= nil then
        return selection("aerial_action", "soccer")
    elseif combat and combat.forced_state == "knockback" and combat.forced_ticks > 0 then
        return selection("combat_knockback", "combat")
    elseif combat and combat.forced_state == "stagger" and combat.forced_ticks > 0 then
        return selection("combat_stagger", "combat")
    elseif combat and combat.phase == "guard" then
        return selection("combat_guard", "combat")
    elseif combat and combat.phase == "active" then
        return selection("combat_active", "combat")
    elseif combat and combat.phase == "windup" then
        return selection("combat_windup", "combat")
    elseif combat and combat.phase == "aim" then
        return selection("combat_aim", "combat")
    elseif combat and combat.phase == "recovery" then
        return selection("combat_recovery", "combat")
    elseif player.windup_timer > 0 then
        return selection("soccer_windup", "soccer")
    elseif player.slide_timer > 0 then
        return selection("slide", "soccer")
    end
    return selection("locomotion", "locomotion")
end

return player_pose
