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

-- Keeper-specific derivations. The generic StatBlock maps onto GK roles the way
-- other soccer games separate them: `defense` is reflexes/positioning (reach),
-- `speed` is diving range, `technique` is handling (clean catch vs spill/parry).
local BASE_REACH = 22 -- dive radius (px) at defense 0
local REACH_PER_DEFENSE = 6 -- px per defense point
local REACH_PER_SPEED = 2 -- px per speed point (diving range)

---@param s StatBlock
---@return number px  -- how far the keeper can get a hand to a shot
function stats.keeper_reach(s)
    return BASE_REACH + s.defense * REACH_PER_DEFENSE + s.speed * REACH_PER_SPEED
end

---@param s StatBlock
---@return number  -- 0..1 clean-handling factor (higher = catches harder shots)
function stats.keeper_handling(s)
    return math.min(1, s.technique / 10)
end

return stats
