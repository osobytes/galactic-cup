-- Pure match simulation: one controllable player, one ball, one goal.
-- No love, no drawing, no input gathering — `game/screens/match.lua` wraps this.
-- All state lives in MatchState; `step` advances it deterministically.

local Vec2 = require("core.vec2")
local stats = require("sim.stats")

local PLAYER_RADIUS = 12
local BALL_RADIUS = 6
local FRICTION = 1.2 -- fraction of ball velocity shed per second
local STICK_AHEAD = PLAYER_RADIUS + BALL_RADIUS -- ball offset while dribbling
local POSSESS_DIST = PLAYER_RADIUS + BALL_RADIUS + 4
local POSSESS_MAX_SPEED = 40 -- can only collect a slow-enough ball

---@class MatchInput
---@field move Vec2  -- desired movement direction (need not be normalized)
---@field shoot boolean  -- shoot requested this step

---@class MatchState
---@field field { w: number, h: number }
---@field goal { x: number, y: number, w: number, h: number }
---@field player Vec2
---@field facing Vec2
---@field ball Vec2
---@field ball_vel Vec2
---@field has_ball boolean
---@field score integer
---@field move_speed number  -- derived from player stats (M1)
---@field shot_speed number  -- derived from player stats (M1)
---@field player_radius number
---@field ball_radius number

local match = {}

---@param v number
---@param lo number
---@param hi number
---@return number
local function clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

---@param s MatchState
local function reset_kickoff(s)
    s.player = Vec2.new(s.field.w * 0.25, s.field.h / 2)
    s.facing = Vec2.new(1, 0)
    s.ball = s.player:add(s.facing:scale(STICK_AHEAD))
    s.ball_vel = Vec2.new(0, 0)
    s.has_ball = true
end

---@param p PlayerData
---@param field_w number
---@param field_h number
---@return MatchState
function match.new(p, field_w, field_h)
    assert(p and p.stats, "match.new requires player data with a stat block")
    ---@type MatchState
    local s = {
        field = { w = field_w, h = field_h },
        goal = { x = field_w - 10, y = field_h / 2 - 50, w = 10, h = 100 },
        player = Vec2.new(0, 0),
        facing = Vec2.new(1, 0),
        ball = Vec2.new(0, 0),
        ball_vel = Vec2.new(0, 0),
        has_ball = true,
        score = 0,
        move_speed = stats.move_speed(p.stats),
        shot_speed = stats.shot_speed(p.stats),
        player_radius = PLAYER_RADIUS,
        ball_radius = BALL_RADIUS,
    }
    reset_kickoff(s)
    return s
end

---@param s MatchState
---@return boolean
local function ball_in_goal_mouth(s)
    return s.ball.y >= s.goal.y and s.ball.y <= s.goal.y + s.goal.h
end

---@param s MatchState
---@param dt number
---@param input MatchInput
---@return MatchState
function match.step(s, dt, input)
    -- Move the player.
    if input.move.x ~= 0 or input.move.y ~= 0 then
        local dir = input.move:normalized()
        s.player = s.player:add(dir:scale(s.move_speed * dt))
        s.player.x = clamp(s.player.x, s.player_radius, s.field.w - s.player_radius)
        s.player.y = clamp(s.player.y, s.player_radius, s.field.h - s.player_radius)
        s.facing = dir
    end

    if s.has_ball then
        -- Ball is glued slightly ahead of the player.
        s.ball = s.player:add(s.facing:scale(STICK_AHEAD))
        s.ball_vel = Vec2.new(0, 0)
        if input.shoot then
            s.has_ball = false
            s.ball_vel = s.facing:scale(s.shot_speed)
        end
    else
        -- Free ball: integrate, decay, bounce.
        s.ball = s.ball:add(s.ball_vel:scale(dt))
        s.ball_vel = s.ball_vel:scale(math.max(0, 1 - FRICTION * dt))

        if s.ball.y < s.ball_radius then
            s.ball.y = s.ball_radius
            s.ball_vel.y = -s.ball_vel.y
        elseif s.ball.y > s.field.h - s.ball_radius then
            s.ball.y = s.field.h - s.ball_radius
            s.ball_vel.y = -s.ball_vel.y
        end
        if s.ball.x < s.ball_radius then
            s.ball.x = s.ball_radius
            s.ball_vel.x = -s.ball_vel.x
        elseif s.ball.x > s.field.w - s.ball_radius and not ball_in_goal_mouth(s) then
            s.ball.x = s.field.w - s.ball_radius
            s.ball_vel.x = -s.ball_vel.x
        end

        -- Collect a slow ball that is close enough.
        if s.player:dist(s.ball) <= POSSESS_DIST and s.ball_vel:length() < POSSESS_MAX_SPEED then
            s.has_ball = true
        end
    end

    -- Goal: ball reaches the goal line within the mouth.
    if s.ball.x + s.ball_radius >= s.goal.x and ball_in_goal_mouth(s) then
        s.score = s.score + 1
        reset_kickoff(s)
    end

    return s
end

return match
