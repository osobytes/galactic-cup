local Vec2 = require("core.vec2")
local fixed_clock = require("sim.fixed_clock")
local match = require("sim.match")
local teams = require("data.teams")
local t = require("spec.support.runner")

---@return MatchInput
local function no_input()
    return {
        move = Vec2.new(0, 0),
        shoot = false,
        shoot_held = false,
        pass = false,
        pass_held = false,
        switch = false,
        dash = false,
        dodge = false,
        lob = false,
        sprint = false,
        jockey = false,
    }
end

---@param pattern number[]
---@return FixedClockState
---@return integer[]
local function drive(pattern)
    local clock = fixed_clock.new()
    local consumed = {}
    for _, dt in ipairs(pattern) do
        fixed_clock.advance(clock, dt, function(tick)
            return tick
        end, function(tick, input)
            t.eq(input, tick, "provider input belongs to the consumed tick")
            consumed[#consumed + 1] = tick
        end)
    end
    return clock, consumed
end

---@param pattern number[]
---@return MatchState
---@return FixedClockState
local function play_script(pattern)
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 41,
    })
    local clock = fixed_clock.new()
    for _, dt in ipairs(pattern) do
        fixed_clock.advance(clock, dt, function(_)
            return no_input()
        end, function(_, input)
            match.step(state, fixed_clock.TICK_SECONDS, input)
            return not state.finished
        end)
    end
    return state, clock
end

---@param a MatchState
---@param b MatchState
local function assert_same_state(a, b)
    t.eq(a.time_left, b.time_left, "time left")
    t.eq(a.score.home, b.score.home, "home score")
    t.eq(a.score.away, b.score.away, "away score")
    t.eq(a.owner, b.owner, "ball owner")
    t.near(a.ball.x, b.ball.x, 1e-9, "ball x")
    t.near(a.ball.y, b.ball.y, 1e-9, "ball y")
    t.near(a.ball_z, b.ball_z, 1e-9, "ball z")
    t.near(a.ball_vel.x, b.ball_vel.x, 1e-9, "ball velocity x")
    t.near(a.ball_vel.y, b.ball_vel.y, 1e-9, "ball velocity y")
    for i, player in ipairs(a.players) do
        local other = b.players[i]
        t.near(player.pos.x, other.pos.x, 1e-9, "player x " .. i)
        t.near(player.pos.y, other.pos.y, 1e-9, "player y " .. i)
        t.near(player.vel.x, other.vel.x, 1e-9, "player velocity x " .. i)
        t.near(player.vel.y, other.vel.y, 1e-9, "player velocity y " .. i)
    end
end

t.describe("fixed simulation clock", function()
    t.it("numbers inputs from zero and advances exact ticks at common render cadences", function()
        local at_30, input_30 = drive((function()
            local result = {}
            for i = 1, 30 do
                result[i] = 1 / 30
            end
            return result
        end)())
        local at_60, input_60 = drive((function()
            local result = {}
            for i = 1, 60 do
                result[i] = 1 / 60
            end
            return result
        end)())
        local at_120, input_120 = drive((function()
            local result = {}
            for i = 1, 120 do
                result[i] = 1 / 120
            end
            return result
        end)())

        t.eq(at_30.tick, 60)
        t.eq(at_60.tick, 60)
        t.eq(at_120.tick, 60)
        t.eq(#input_30, 60)
        t.eq(#input_60, 60)
        t.eq(#input_120, 60)
        t.eq(input_30[1], 0)
        t.eq(input_30[#input_30], 59)
    end)

    t.it(
        "keeps gameplay state equivalent across 30/60/120 Hz and irregular render cadences",
        function()
            local at_30 = {}
            for i = 1, 30 do
                at_30[i] = 1 / 30
            end
            local regular = {}
            for i = 1, 60 do
                regular[i] = 1 / 60
            end
            local at_120 = {}
            for i = 1, 120 do
                at_120[i] = 1 / 120
            end
            local irregular = {}
            for cycle = 1, 15 do
                local start = (cycle - 1) * 4
                irregular[start + 1] = 1 / 120
                irregular[start + 2] = 1 / 40
                irregular[start + 3] = 1 / 120
                irregular[start + 4] = 1 / 40
            end

            local at_30_state, at_30_clock = play_script(at_30)
            local regular_state, regular_clock = play_script(regular)
            local at_120_state, at_120_clock = play_script(at_120)
            local irregular_state, irregular_clock = play_script(irregular)
            t.eq(at_30_clock.tick, 60)
            t.eq(regular_clock.tick, 60)
            t.eq(at_120_clock.tick, 60)
            t.eq(irregular_clock.tick, 60)
            assert_same_state(regular_state, at_30_state)
            assert_same_state(regular_state, at_120_state)
            assert_same_state(regular_state, irregular_state)
        end
    )

    t.it("reports zero and multiple tick render updates", function()
        local clock = fixed_clock.new()
        local calls = 0
        local first = fixed_clock.advance(clock, 1 / 120, function(tick)
            return tick
        end, function()
            calls = calls + 1
        end)
        t.eq(first.ticks, 0)
        t.eq(calls, 0)

        local second = fixed_clock.advance(clock, 1 / 120, function(tick)
            return tick
        end, function()
            calls = calls + 1
        end)
        t.eq(second.ticks, 1)
        t.eq(second.first_tick, 0)
        t.eq(second.last_tick, 0)

        local third = fixed_clock.advance(clock, 1 / 20, function(tick)
            return tick
        end, function()
            calls = calls + 1
        end)
        t.eq(third.ticks, 3)
        t.eq(third.first_tick, 1)
        t.eq(third.last_tick, 3)
        t.eq(calls, 4)
    end)

    t.it("drops only whole excess tick debt and keeps the fractional remainder", function()
        local clock = fixed_clock.new()
        local result = fixed_clock.advance(
            clock,
            fixed_clock.TICK_SECONDS * (fixed_clock.MAX_TICKS_PER_UPDATE + 3.5),
            function(tick)
                return tick
            end,
            function() end
        )
        t.eq(result.ticks, fixed_clock.MAX_TICKS_PER_UPDATE)
        t.eq(result.dropped_ticks, 3)
        t.eq(clock.dropped_ticks, 3)
        t.eq(clock.overloads, 1)
        t.near(clock.accumulator, fixed_clock.TICK_SECONDS / 2, 1e-9)

        local remainder = fixed_clock.advance(clock, fixed_clock.TICK_SECONDS / 2, function(tick)
            return tick
        end, function() end)
        t.eq(remainder.ticks, 1)
        t.eq(remainder.first_tick, fixed_clock.MAX_TICKS_PER_UPDATE)
        t.near(clock.accumulator, 0, 1e-9)
    end)

    t.it("lets a step callback stop a finished simulation without retaining debt", function()
        local clock = fixed_clock.new()
        local result = fixed_clock.advance(clock, 1 / 10, function(tick)
            return tick
        end, function()
            return false
        end)
        t.eq(result.ticks, 1)
        t.is_true(result.stopped)
        t.eq(clock.tick, 1)
        t.near(clock.accumulator, 0, 1e-9)
    end)
end)
