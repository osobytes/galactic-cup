local t = require("spec.support.runner")
local match = require("sim.match")
local Vec2 = require("core.vec2")

---@param speed integer
---@param power integer
---@return PlayerData
local function player(speed, power)
    return {
        id = "test",
        name = "Test",
        planet = "Testworld",
        position = "forward",
        stats = { speed = speed, power = power, technique = 5, defense = 5, stamina = 5 },
        trait = "none",
    }
end

local NO_MOVE = { move = Vec2.new(0, 0), shoot = false }

t.describe("match.new", function()
    t.it("starts with the ball, no score", function()
        local s = match.new(player(5, 5), 960, 540)
        t.is_true(s.has_ball)
        t.eq(s.score, 0)
    end)
end)

t.describe("match.step movement (M1: speed stat -> motion)", function()
    t.it("moving right increases player x", function()
        local s = match.new(player(5, 5), 960, 540)
        local x0 = s.player.x
        match.step(s, 0.1, { move = Vec2.new(1, 0), shoot = false })
        t.is_true(s.player.x > x0)
    end)

    t.it("a faster player covers more ground in the same time", function()
        local slow = match.new(player(2, 5), 960, 540)
        local fast = match.new(player(8, 5), 960, 540)
        local sx, fx = slow.player.x, fast.player.x
        local input = { move = Vec2.new(1, 0), shoot = false }
        match.step(slow, 0.1, input)
        match.step(fast, 0.1, input)
        t.is_true((fast.player.x - fx) > (slow.player.x - sx), "higher speed -> larger delta")
    end)
end)

t.describe("match.step shooting (M1: power stat -> shot)", function()
    t.it("shooting releases the ball with forward velocity", function()
        local s = match.new(player(5, 5), 960, 540)
        match.step(s, 0.016, { move = Vec2.new(0, 0), shoot = true })
        t.is_true(not s.has_ball)
        t.is_true(s.ball_vel.x > 0)
    end)

    t.it("a stronger player shoots faster", function()
        local weak = match.new(player(5, 2), 960, 540)
        local strong = match.new(player(5, 8), 960, 540)
        match.step(weak, 0.016, { move = Vec2.new(0, 0), shoot = true })
        match.step(strong, 0.016, { move = Vec2.new(0, 0), shoot = true })
        t.is_true(strong.ball_vel:length() > weak.ball_vel:length())
    end)
end)

t.describe("match.step scoring", function()
    t.it("a ball entering the goal mouth increments the score and resets", function()
        local s = match.new(player(5, 9), 960, 540)
        -- Aim the player at the goal centre and shoot.
        s.player = Vec2.new(s.goal.x - 30, s.goal.y + s.goal.h / 2)
        s.facing = Vec2.new(1, 0)
        s.ball = s.player:add(s.facing:scale(s.ball_radius + s.player_radius))
        match.step(s, 0.016, { move = Vec2.new(0, 0), shoot = true })
        -- Advance until the ball reaches the line.
        local scored = false
        for _ = 1, 120 do
            match.step(s, 0.016, NO_MOVE)
            if s.score > 0 then
                scored = true
                break
            end
        end
        t.is_true(scored, "ball should have entered the goal")
        t.is_true(s.has_ball, "should reset to kickoff with possession")
    end)
end)
