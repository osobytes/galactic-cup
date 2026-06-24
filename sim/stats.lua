-- Derives concrete physical quantities from a player's stat block.
-- This is the M1 bridge: manager-facing stats -> on-pitch behavior.

local stats = {}

local BASE_MOVE = 60 -- px/s at speed 0
local MOVE_PER_SPEED = 20 -- px/s per speed point

local BASE_SHOT = 150 -- px/s at power 0
local SHOT_PER_POWER = 50 -- px/s per power point

---@param s StatBlock
---@return number px_per_second
function stats.move_speed(s)
    return BASE_MOVE + s.speed * MOVE_PER_SPEED
end

---@param s StatBlock
---@return number px_per_second
function stats.shot_speed(s)
    return BASE_SHOT + s.power * SHOT_PER_POWER
end

return stats
