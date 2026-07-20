local Vec2 = require("core.vec2")

---@alias SaveStyle "spread"|"central"|"stretch"

---@class KeeperPositionContext
---@field keeper_pos Vec2
---@field ball_pos Vec2
---@field goal Rect
---@field team "home"|"away"
---@field aggression number
---@field in_1v1 boolean

local CLAIM_DEPTH = 160
-- The issue's fixed context deliberately omits field dimensions. Galactic Cup's canonical
-- 960px pitch therefore supplies the 480px goal-line-to-midfield half-depth.
local MIDFIELD_DEPTH = 480
local KEEPER_GUARD = 28
local SMOTHER_DISTANCE = 26
local SPREAD_DISTANCE = 78
local CENTRAL_REACH_FRACTION = 0.4

---@class KeeperResolver
local keeper = {}

---@param value number
---@param minimum number
---@param maximum number
---@return number
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

---@param context KeeperPositionContext
---@return Vec2
function keeper.arc_target(context)
    local goal_line_x
    local infield_direction
    if context.team == "home" then
        goal_line_x = context.goal.x + context.goal.w
        infield_direction = 1
    else
        goal_line_x = context.goal.x
        infield_direction = -1
    end

    local goal_center = Vec2.new(goal_line_x, context.goal.y + context.goal.h / 2)
    local ball_depth = (context.ball_pos.x - goal_line_x) * infield_direction
    if not context.in_1v1 and ball_depth >= MIDFIELD_DEPTH then
        return goal_center
    end

    local approach = clamp((MIDFIELD_DEPTH - ball_depth) / (MIDFIELD_DEPTH - CLAIM_DEPTH), 0, 1)
    local target_depth = math.max(context.aggression, 0) * (context.in_1v1 and 1 or approach)
    if target_depth == 0 then
        return goal_center
    end

    local ray = context.ball_pos:sub(goal_center)
    if ray:length() == 0 then
        ray = context.keeper_pos:sub(goal_center)
    end
    if ray:length() == 0 or ray.x * infield_direction <= 0 then
        ray = Vec2.new(infield_direction, 0)
    end

    local target = goal_center:add(ray:normalized():scale(target_depth))
    return Vec2.new(
        target.x,
        clamp(target.y, goal_center.y - KEEPER_GUARD, goal_center.y + KEEPER_GUARD)
    )
end

---@param dist_to_keeper number
---@param dive_dist number
---@param reach number
---@return SaveStyle
function keeper.save_style(dist_to_keeper, dive_dist, reach)
    assert(
        dist_to_keeper > SMOTHER_DISTANCE,
        "save_style only classifies saves beyond the smother distance"
    )
    if dist_to_keeper <= SPREAD_DISTANCE then
        return "spread"
    end
    if dive_dist <= reach * CENTRAL_REACH_FRACTION then
        return "central"
    end
    return "stretch"
end

---@param anticipation number
---@param windup_duration number
---@return number seconds
function keeper.commit_lead(anticipation, windup_duration)
    return clamp(anticipation, 0, 1) * math.max(windup_duration, 0)
end

return keeper
