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

-- Aerial actions reuse the authored five-stat vocabulary. Pace determines
-- whether a player reaches the ball; these factors resolve contact quality.

---@param s StatBlock
---@return number  -- 0..1 reception quality
function stats.first_touch(s)
    return math.min(1, (s.technique * 0.75 + s.mental * 0.25) / 10)
end

---@param s StatBlock
---@return number  -- 0..1 header contact quality
function stats.header(s)
    return math.min(1, (s.technique * 0.35 + s.mental * 0.35 + s.strength * 0.30) / 10)
end

---@param s StatBlock
---@return number  -- 0..1 volley contact quality
function stats.volley(s)
    return math.min(1, (s.technique * 0.65 + s.mental * 0.20 + s.strength * 0.15) / 10)
end

---@param s StatBlock
---@return number  -- 0..1 bicycle-kick contact quality
function stats.bicycle(s)
    return math.min(1, (s.technique * 0.70 + s.mental * 0.20 + s.strength * 0.10) / 10)
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

-- Conservative first-pass positioning depth. Canonical 0..10 stats produce
-- 18..58 px, leaving later fixed-seed calibration to the goalkeeper milestone.
local BASE_KEEPER_AGGRESSION = 18 -- px at pace 0 and mental 0
local KEEPER_AGGRESSION_PER_PACE = 2 -- px per pace point
local KEEPER_AGGRESSION_PER_MENTAL = 2 -- px per mental point

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

---@param s StatBlock
---@return number anticipation  -- 0..1 mental-led shot-reading quality
function stats.keeper_anticipation(s)
    return math.max(0, math.min(1, s.mental / 10))
end

---@param s StatBlock
---@return number pixels  -- positive positioning-depth cap; 18..58 for canonical stats
function stats.keeper_aggression(s)
    return BASE_KEEPER_AGGRESSION
        + s.pace * KEEPER_AGGRESSION_PER_PACE
        + s.mental * KEEPER_AGGRESSION_PER_MENTAL
end

---@param s StatBlock
---@return number accuracy  -- 0..1 technique-led hand-distribution accuracy
function stats.keeper_distribution_accuracy(s)
    return math.max(0, math.min(1, s.technique / 10))
end

return stats
