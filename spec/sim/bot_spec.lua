local t = require("spec.support.runner")
local match = require("sim.match")
local bot = require("sim.bot")
local teams = require("data.teams")
local Vec2 = require("core.vec2")

local function new_match(seed)
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = seed or 42,
    })
end

t.describe("bot carrier decisions", function()
    t.it("charges and releases a shot when in range of the goal", function()
        local s = new_match()
        local me = s.players[s.controlled]
        me.pos = Vec2.new(800, 270) -- well inside shooting range
        s.ball = me.pos:add(Vec2.new(18, 0))
        local b = bot.new({ seed = 1 })
        local held, fired = false, false
        for _ = 1, 60 do
            local input = bot.input(b, s, 1 / 60)
            held = held or input.shoot_held
            if input.shoot then
                fired = true
                break
            end
        end
        t.is_true(held, "the bot builds charge before shooting")
        t.is_true(fired, "and releases the shot")
    end)

    t.it("passes when pressured far from goal", function()
        local s = new_match()
        local me = s.players[s.controlled]
        me.pos = Vec2.new(200, 270) -- own half: out of shooting range
        s.ball = me.pos:add(Vec2.new(18, 0))
        -- An opponent right on top of the carrier.
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                s.players[i].pos = Vec2.new(230, 270)
                break
            end
        end
        local b = bot.new({ seed = 1 })
        local passed = false
        for _ = 1, 30 do
            local input = bot.input(b, s, 1 / 60)
            if input.pass then
                passed = true
                break
            end
        end
        t.is_true(passed, "the pressured bot moves the ball on")
    end)

    t.it("fires one-shot actions for exactly one frame", function()
        local s = new_match()
        local b = bot.new({ seed = 1 })
        b.pass = true
        b.decide_t = 10 -- no re-decision: isolate the latch
        local first = bot.input(b, s, 1 / 60)
        local second = bot.input(b, s, 1 / 60)
        t.is_true(first.pass, "the queued pass fires")
        t.is_true(not second.pass, "and does not repeat")
    end)
end)

t.describe("bot determinism", function()
    t.it("same seed produces the identical match", function()
        local function play(seed)
            local s = new_match(seed)
            local b = bot.new({ seed = seed })
            for _ = 1, 600 do -- 10 seconds
                match.step(s, 1 / 60, bot.input(b, s, 1 / 60))
            end
            return s
        end
        local a, c = play(7), play(7)
        t.near(a.ball.x, c.ball.x, 1e-9)
        t.near(a.ball.y, c.ball.y, 1e-9)
        t.eq(a.score.home, c.score.home)
        t.eq(a.score.away, c.score.away)
        for i in ipairs(a.players) do
            t.near(a.players[i].pos.x, c.players[i].pos.x, 1e-9)
            t.near(a.players[i].pos.y, c.players[i].pos.y, 1e-9)
        end
    end)
end)

t.describe("bot plays a real match", function()
    t.it("keeps the controlled player active (not a statue)", function()
        local s = new_match(3)
        local b = bot.new({ seed = 3 })
        local moved_frames = 0
        for _ = 1, 600 do
            local input = bot.input(b, s, 1 / 60)
            if input.move.x ~= 0 or input.move.y ~= 0 then
                moved_frames = moved_frames + 1
            end
            match.step(s, 1 / 60, input)
        end
        t.is_true(moved_frames > 300, "the bot steers most frames")
    end)
end)
