local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local tactics = require("data.tactics")
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
        shoot = o.shoot or false,
        pass = o.pass or false,
        switch = o.switch or false,
        dash = o.dash or false,
    }
end

local NO_INPUT = input()

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
    t.it("shooting releases the ball toward the goal", function()
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(1, 0)
        match.step(s, 0.016, input({ shoot = true }))
        t.is_true(s.owner == nil)
        t.is_true(s.ball_vel.x > 0, "home shoots toward the right goal")
    end)

    t.it("aiming up sends the shot to the top corner", function()
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(0, -1)
        match.step(s, 0.016, input({ shoot = true }))
        t.is_true(s.owner == nil)
        t.is_true(s.ball_vel.x > 0, "still goal-ward")
        t.is_true(s.ball_vel.y < 0, "and toward the top corner")
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
        match.step(s, 0.016, input({ pass = true }))
        t.is_true(s.owner == nil, "ball should be released on a pass")
        t.near(s.ball_vel:length(), 320, 0.5, "pass speed")
    end)
end)

t.describe("match.step tackling", function()
    t.it("dashing into an opponent carrier knocks the ball loose", function()
        local s = new_match()
        local away_idx
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                away_idx = i
                break
            end
        end
        s.owner = away_idx
        local carrier = s.players[away_idx]
        local me = s.players[s.controlled]
        me.pos = Vec2.new(carrier.pos.x + 8, carrier.pos.y)
        me.dash_cd = 0
        match.step(s, 0.016, input({ dash = true }))
        t.is_true(s.owner ~= away_idx, "carrier should lose possession to the tackle")
    end)
end)

t.describe("match.step switching", function()
    t.it("cycles the controlled player among home outfielders", function()
        local s = new_match()
        local before = s.controlled
        match.step(s, 0.016, input({ switch = true }))
        t.is_true(s.controlled ~= before)
        t.is_true(s.players[s.controlled].team == "home")
        t.is_true(not s.players[s.controlled].is_keeper)
    end)
end)

t.describe("match tactics", function()
    ---@param s MatchState
    ---@return number
    local function mean_home_outfield_x(s)
        local sum, n = 0, 0
        for _, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper then
                sum = sum + p.anchor.x
                n = n + 1
            end
        end
        return sum / n
    end

    t.it("press high pushes the home shape higher up the pitch", function()
        local balanced = new_match()
        local high = match.new({
            home = teams.nebula,
            away = teams.orion,
            field = { w = 960, h = 540 },
            tactic = tactics.press_high,
        })
        t.is_true(mean_home_outfield_x(high) > mean_home_outfield_x(balanced))
    end)

    t.it("counter attack drops the home shape deeper", function()
        local balanced = new_match()
        local counter = match.new({
            home = teams.nebula,
            away = teams.orion,
            field = { w = 960, h = 540 },
            tactic = tactics.counter,
        })
        t.is_true(mean_home_outfield_x(counter) < mean_home_outfield_x(balanced))
    end)

    t.it("press high assigns two home pressers", function()
        local high = match.new({
            home = teams.nebula,
            away = teams.orion,
            field = { w = 960, h = 540 },
            tactic = tactics.press_high,
        })
        t.eq(high.press.home, 2)
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
