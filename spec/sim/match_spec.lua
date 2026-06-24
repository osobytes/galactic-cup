local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local Vec2 = require("core.vec2")

local function new_match()
    return match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
end

local NO_INPUT = { move = Vec2.new(0, 0), shoot = false, pass = false, switch = false }

t.describe("match.new", function()
    t.it("kicks off with 10 players and the home side in possession", function()
        local s = new_match()
        t.eq(#s.players, 10)
        t.is_true(s.owner == s.controlled, "controlled player should start with the ball")
        t.eq(s.score.home, 0)
        t.eq(s.score.away, 0)
        t.is_true(s.players[s.controlled].team == "home")
        t.is_true(not s.players[s.controlled].is_keeper)
    end)
end)

t.describe("match.step timer", function()
    t.it("counts down and ends at full time", function()
        local s = new_match()
        match.step(s, 10, NO_INPUT)
        t.near(s.time_left, 110, 1e-6)
        t.is_true(not s.finished)
        match.step(s, 200, NO_INPUT)
        t.is_true(s.finished)
        t.eq(s.time_left, 0)
    end)
end)

t.describe("match.step shooting & passing", function()
    t.it("shooting releases the ball with forward velocity", function()
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(1, 0)
        match.step(s, 0.016, { move = Vec2.new(0, 0), shoot = true, pass = false, switch = false })
        t.is_true(s.owner == nil)
        t.is_true(s.ball_vel:length() > 0)
    end)

    t.it("passing sends the ball toward a teammate in the aim direction", function()
        local s = new_match()
        local owner = s.players[s.controlled]
        local mate
        for i, p in ipairs(s.players) do
            if p.team == "home" and i ~= s.controlled then
                mate = p
                break
            end
        end
        owner.facing = mate.pos:sub(owner.pos):normalized()
        match.step(s, 0.016, { move = Vec2.new(0, 0), shoot = false, pass = true, switch = false })
        t.is_true(s.owner == nil, "ball should be released on a pass")
        t.near(s.ball_vel:length(), 320, 0.5, "pass speed")
    end)
end)

t.describe("match.step switching", function()
    t.it("cycles the controlled player among home outfielders", function()
        local s = new_match()
        local before = s.controlled
        match.step(s, 0.016, { move = Vec2.new(0, 0), shoot = false, pass = false, switch = true })
        t.is_true(s.controlled ~= before)
        t.is_true(s.players[s.controlled].team == "home")
        t.is_true(not s.players[s.controlled].is_keeper)
    end)
end)

t.describe("match.step scoring", function()
    t.it("a ball crossing the right line scores for home", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 1 -- keep anyone from collecting it this step
        s.ball = Vec2.new(s.field.w - 5, s.field.h / 2)
        s.ball_vel = Vec2.new(5, 0)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.score.home, 1)
        t.eq(s.score.away, 0)
    end)
end)
