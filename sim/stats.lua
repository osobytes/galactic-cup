-- Derives concrete physical quantities from a player's effective stat block.
-- `sim.species.apply` owns the first attribute-modifying readability layer and
-- match construction calls it exactly once before these mappings. Arenas own
-- the reserved second layer; this module must not stack either layer itself.

local stats = {}

local BASE_MOVE = 60 -- px/s at pace 0
local MOVE_PER_PACE = 20 -- px/s per pace point

local BASE_SHOT = 150 -- px/s at strength 0
local SHOT_PER_STRENGTH = 50 -- px/s per strength point

---@param s StatBlock
---@return number px_per_second
function stats.move_speed(s)
    return BASE_MOVE + s.pace * MOVE_PER_PACE
end

---@param s StatBlock
---@return number px_per_second
function stats.shot_speed(s)
    return BASE_SHOT + s.strength * SHOT_PER_STRENGTH
end

-- Dribble control: how tightly a carrier keeps the ball at their feet as they
-- move. Technique is touch quality — a higher-technique player takes cleaner,
-- closer touches, so the ball rides less far ahead and is harder to nick.
local BASE_DRIBBLE = 0.25 -- control factor (0..1) at technique 0
local DRIBBLE_PER_TECH = 0.065 -- extra control per technique point

---@param s StatBlock
---@return number  -- 0..1 control factor (higher = ball stays tighter to the feet)
function stats.dribble(s)
    return math.min(1, BASE_DRIBBLE + s.technique * DRIBBLE_PER_TECH)
end

-- Sprint: the hold-to-run burst. Stamina sets how long a full tank lasts.
local BASE_SPRINT = 2.2 -- seconds of sprint at stamina 0
local SPRINT_PER_STAMINA = 0.25 -- extra seconds per stamina point

---@param s StatBlock
---@return number seconds
function stats.sprint_duration(s)
    return BASE_SPRINT + s.stamina * SPRINT_PER_STAMINA
end

-- Keeper-specific derivations. Mental represents composure and positioning (reach),
-- pace contributes diving range, and technique controls clean handling. Defensive
-- ability remains derived from the canonical attributes rather than authored separately.
local BASE_REACH = 22 -- dive radius (px) at mental 0
local REACH_PER_MENTAL = 6 -- px per mental point
local REACH_PER_PACE = 2 -- px per pace point (diving range)

---@param s StatBlock
---@return number px  -- how far the keeper can get a hand to a shot
function stats.keeper_reach(s)
    return BASE_REACH + s.mental * REACH_PER_MENTAL + s.pace * REACH_PER_PACE
end

---@param s StatBlock
---@return number  -- 0..1 clean-handling factor (higher = catches harder shots)
function stats.keeper_handling(s)
    return math.min(1, s.technique / 10)
end

return stats
