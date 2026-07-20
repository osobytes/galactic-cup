local t = require("spec.support.runner")
local Vec2 = require("core.vec2")
local fixed_clock = require("sim.fixed_clock")
local input_frame = require("sim.input_frame")
local match = require("sim.match")
local match_snapshot = require("sim.match_snapshot")
local teams = require("data.teams")

---@return MatchState
local function new_state()
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        duration = 2,
        max_goals = 3,
        seed = 38,
        input_ownership = match.ownership_for_teams(teams.nebula, teams.orion),
    })
end

---@param class_name string
---@param end_marker string
---@return string[]
local function declared_fields(class_name, end_marker)
    local source = assert(love.filesystem.read("sim/match.lua"))
    local start_at = assert(source:find("---@class " .. class_name, 1, true))
    local end_at = assert(source:find(end_marker, start_at, true))
    local fields = {}
    for field in source:sub(start_at, end_at - 1):gmatch("%-%-%-@field%s+([%w_]+)") do
        fields[#fields + 1] = field
    end
    return fields
end

---@param actual string[]
---@param expected string[]
local function same_fields(actual, expected)
    t.eq(#actual, #expected, "snapshot schema field count")
    for index = 1, #expected do
        t.eq(actual[index], expected[index], "snapshot schema field " .. index)
    end
end

t.describe("canonical match snapshots", function()
    t.it("pins MatchState and MatchPlayer additions to explicit versioned allowlists", function()
        same_fields(
            declared_fields("MatchPlayer", "---@class MatchInput"),
            match_snapshot.PLAYER_FIELDS
        )
        same_fields(declared_fields("MatchState", "local match = {}"), match_snapshot.MATCH_FIELDS)
    end)

    t.it("captures and restores every nested payload as independent state", function()
        local state = new_state()
        state.players[2].dive_target = Vec2.new(10, 20)
        state.players[1].keeper_1v1_target = Vec2.new(40, 285)
        state.players[2].windup_shot = {
            dir = Vec2.new(0.25, -0.75),
            speed = 456,
            vz = 123,
            spin = -8,
        }
        state.players[2].save_style = "stretch"
        state.players[2].save_tip_emitted = true
        state.players[2].keeper_anticipation = 0.75
        state.players[2].keeper_set = 0.125
        state.events[1] = {
            kind = "header",
            x = 44,
            y = 55,
            player = state.players[2].id,
            style = "header",
            outcome = "clean",
            jumping = true,
            difficulty = 0.4,
        }
        state.events[2] = {
            kind = "catch",
            x = 66,
            y = 77,
            player = state.players[1].id,
            save_style = "spread",
        }
        local snapshot = match_snapshot.capture(state)
        local restored = match_snapshot.restore(snapshot)

        state.players[2].pos.x = -100
        state.players[1].keeper_1v1_target.x = -101
        state.players[2].windup_shot.dir.y = 99
        state.events[1].x = 999
        state.events[2].save_style = "central"
        t.is_true(snapshot.state.players[2].pos.x ~= -100)
        t.eq(snapshot.state.players[1].keeper_1v1_target.x, 40)
        t.eq(snapshot.state.players[2].windup_shot.dir.y, -0.75)
        t.eq(snapshot.state.players[2].save_style, "stretch")
        t.is_true(snapshot.state.players[2].save_tip_emitted)
        t.eq(snapshot.state.players[2].keeper_anticipation, 0.75)
        t.eq(snapshot.state.players[2].keeper_set, 0.125)
        t.eq(snapshot.state.events[1].x, 44)
        t.eq(snapshot.state.events[2].save_style, "spread")

        snapshot.state.players[2].pos.y = -200
        snapshot.state.players[1].keeper_1v1_target.y = -201
        snapshot.state.players[2].windup_shot.speed = 1
        t.is_true(restored.players[2].pos.y ~= -200)
        t.eq(restored.players[1].keeper_1v1_target.y, 285)
        t.near(restored.players[1].keeper_aggression, state.players[1].keeper_aggression)
        t.near(restored.players[1].keeper_anticipation, state.players[1].keeper_anticipation)
        t.eq(restored.players[2].windup_shot.speed, 456)
        t.near(restored.players[2].windup_shot.dir:length(), math.sqrt(0.625))
        t.eq(restored.players[2].keeper_anticipation, 0.75)
        t.eq(restored.players[2].keeper_set, 0.125)
        t.eq(restored.events[2].save_style, "spread")
    end)

    t.it("converges snapshot advance restore and replay at every boundary", function()
        local live = new_state()
        local initial = match_snapshot.capture(live)
        local frames = {
            assert(input_frame.neutral(0)),
            assert(input_frame.neutral(1)),
            assert(input_frame.neutral(2)),
        }
        frames[1].slots[1] = assert(input_frame.new_sample({ move_x = 127 }))
        frames[2].slots[5] = assert(input_frame.new_sample({ move_y = -127 }))
        local hashes = { match_snapshot.hash(initial) }
        for index, frame in ipairs(frames) do
            match.step(live, fixed_clock.TICK_SECONDS, frame)
            hashes[index + 1] = match_snapshot.hash(match_snapshot.capture(live))
        end

        local restored = match_snapshot.restore(initial)
        t.is_true(restored ~= live)
        for index, frame in ipairs(frames) do
            match.step(restored, fixed_clock.TICK_SECONDS, frame)
            t.eq(
                match_snapshot.hash(match_snapshot.capture(restored)),
                hashes[index + 1],
                "restored boundary " .. index
            )
        end
        t.is_true(
            match_snapshot.first_difference(
                match_snapshot.capture(live),
                match_snapshot.capture(restored)
            ) == nil
        )
    end)

    t.it("serializes independent of table insertion order", function()
        local snapshot = match_snapshot.capture(new_state())
        local reordered_state = {}
        for index = #match_snapshot.MATCH_FIELDS, 1, -1 do
            local field = match_snapshot.MATCH_FIELDS[index]
            reordered_state[field] = snapshot.state[field]
        end
        local reordered = { state = reordered_state, version = snapshot.version }
        t.eq(match_snapshot.encode(reordered), match_snapshot.encode(snapshot))
        t.eq(match_snapshot.hash(reordered), match_snapshot.hash(snapshot))
    end)

    t.it("rejects unhandled state and player fields", function()
        local state = new_state()
        rawset(state, "future_match_field", 1)
        t.is_true(not pcall(match_snapshot.capture, state))
        rawset(state, "future_match_field", nil)
        rawset(state.players[1], "future_player_field", true)
        t.is_true(not pcall(match_snapshot.capture, state))
    end)

    t.it("rejects the prior snapshot schema instead of inventing keeper state", function()
        local snapshot = match_snapshot.capture(new_state())
        snapshot.version = match_snapshot.VERSION - 1
        t.is_true(not pcall(match_snapshot.restore, snapshot))
    end)

    t.it("uses exact canonical finite-number spelling", function()
        t.eq(match_snapshot.number_bytes(0), "z")
        t.eq(match_snapshot.number_bytes(-0.0), "Z")
        t.eq(match_snapshot.number_bytes(0.5), "p:0:33554432:0")
        t.eq(match_snapshot.number_bytes(-1), "m:1:33554432:0")
        t.is_true(
            match_snapshot.number_bytes(0.1) ~= match_snapshot.number_bytes(0.10000000000000002)
        )
        t.is_true(not pcall(match_snapshot.number_bytes, 0 / 0))
        t.is_true(not pcall(match_snapshot.number_bytes, math.huge))
    end)
end)
