local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local tuning = require("sim.tuning")
local Vec2 = require("core.vec2")

local function new_match()
    return match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
end

---@param o table?
---@return MatchInput
local function input(o)
    o = o or {}
    return {
        move = o.move or Vec2.new(0, 0),
        shoot = false,
        shoot_held = false,
        pass = false,
        pass_held = false,
        switch = false,
        dash = o.dash or false,
        dodge = false,
        lob = false,
        sprint = false,
        jockey = o.jockey or false,
    }
end

local function has_event(s, kind)
    for _, e in ipairs(s.events) do
        if e.kind == kind then
            return true
        end
    end
    return false
end

local function first_home_outfield(s)
    for i, p in ipairs(s.players) do
        if p.team == "home" and not p.is_keeper then
            return i
        end
    end
end

t.describe("aerial striking", function()
    t.it("lets a human meet a dropping cross for a volley toward goal", function()
        tuning.reset()
        local s = new_match()
        local hp = first_home_outfield(s)
        s.controlled = hp
        s.owner = nil
        s.pickup_cd = 0
        local p = s.players[hp]
        p.pos = Vec2.new(700, 270)
        p.header_cd = 0
        s.ball = Vec2.new(710, 270) -- within reach
        s.ball_z = 30 -- volley band
        s.ball_vz = -60 -- descending
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 1 / 60, input({ jockey = true })) -- "go up for it"
        t.is_true(has_event(s, "volley") or has_event(s, "header"), "the striker connects")
        t.is_true(s.ball_vel.x > 0, "and drives it toward the opponent goal")
    end)

    t.it("connects with the generous assist reach, not just point-blank", function()
        tuning.reset()
        local s = new_match()
        local hp = first_home_outfield(s)
        s.controlled = hp
        s.owner = nil
        s.pickup_cd = 0
        local p = s.players[hp]
        p.pos = Vec2.new(700, 270)
        p.header_cd = 0
        -- 40px away: outside the 24px AI reach, inside the human assist reach.
        s.ball = Vec2.new(740, 270)
        s.ball_z = 30
        s.ball_vz = -60
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 1 / 60, input({ jockey = true }))
        t.is_true(has_event(s, "volley") or has_event(s, "header"), "the assist reach connects")
    end)

    t.it("hands control to the best-placed attacker as a cross flies in", function()
        tuning.reset()
        local s = new_match()
        local att = first_home_outfield(s)
        -- Control someone else; the aid should switch to the attacker on the ball.
        local other
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= att then
                other = i
                break
            end
        end
        s.controlled = other
        s.owner = nil
        s.players[att].pos = Vec2.new(760, 260)
        s.ball = Vec2.new(770, 260)
        s.ball_z = 40 -- lofted cross into the attacking third
        s.ball_vz = -20
        s.ball_vel = Vec2.new(20, 0)
        match.step(s, 1 / 60, input())
        t.eq(s.controlled, att)
    end)
end)
