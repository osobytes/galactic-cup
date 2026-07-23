local t = require("spec.support.runner")
local Vec2 = require("core.vec2")
local teams = require("data.teams")
local correction_smoothing = require("game.render.correction_smoothing")
local view_state = require("game.render.view_state")
local match_sim = require("sim.match")
local match_snapshot = require("sim.match_snapshot")

---@return MatchState
local function new_match()
    return match_sim.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
    })
end

---@param state MatchState
---@return MatchState
local function copy_match(state)
    return match_snapshot.restore(match_snapshot.capture(state))
end

---@param state MatchState
---@return string
local function state_hash(state)
    return match_snapshot.hash(match_snapshot.capture(state))
end

---@param state MatchState
---@param player_dx number
---@param ball_dx number
---@return MatchState
local function corrected_match(state, player_dx, ball_dx)
    local corrected = copy_match(state)
    local player = corrected.players[1]
    player.pos = Vec2.new(player.pos.x + player_dx, player.pos.y)
    corrected.ball = Vec2.new(corrected.ball.x + ball_dx, corrected.ball.y)
    return corrected
end

t.describe("render correction smoothing", function()
    t.it("starts at the previous pose and converges monotonically in 100 ms", function()
        local authoritative = new_match()
        local source_hash = state_hash(authoritative)
        local model = correction_smoothing.new(authoritative)
        local original_pose = correction_smoothing.pose(model)
        local corrected = corrected_match(authoritative, 80, 40)
        local corrected_hash = state_hash(corrected)

        local smoothing = correction_smoothing.correct(model, corrected)
        local pose = correction_smoothing.pose(smoothing)
        local player_id = corrected.players[1].id
        t.near(pose.players[player_id].x, original_pose.players[player_id].x)
        t.near(pose.ball.x, original_pose.ball.x)
        t.eq(correction_smoothing.diagnostics(smoothing).active_count, 2)

        local previous_distance = math.huge
        for _ = 1, 4 do
            smoothing = correction_smoothing.advance(smoothing, corrected, 0.025)
            pose = correction_smoothing.pose(smoothing)
            local distance = corrected.players[1].pos.x - pose.players[player_id].x
            t.is_true(distance >= 0)
            t.is_true(distance < previous_distance)
            previous_distance = distance
        end
        t.near(pose.players[player_id].x, corrected.players[1].pos.x)
        t.near(pose.ball.x, corrected.ball.x)
        t.eq(correction_smoothing.diagnostics(smoothing).active_count, 0)

        t.eq(state_hash(authoritative), source_hash)
        t.eq(state_hash(corrected), corrected_hash)
        t.eq(correction_smoothing.diagnostics(model).active_count, 0)
        t.near(
            correction_smoothing.pose(model).players[player_id].x,
            original_pose.players[player_id].x
        )
    end)

    t.it("composes repeated corrections without a displayed discontinuity", function()
        local authoritative = new_match()
        local player_id = authoritative.players[1].id
        local model = correction_smoothing.new(authoritative)
        local first = corrected_match(authoritative, 80, 0)
        model = correction_smoothing.correct(model, first)
        model = correction_smoothing.advance(model, first, 0.025)
        local before = correction_smoothing.pose(model).players[player_id]

        local second = corrected_match(authoritative, 100, 0)
        model = correction_smoothing.correct(model, second)
        local after = correction_smoothing.pose(model).players[player_id]
        t.near(after.x, before.x)
        t.near(after.y, before.y)
        local diagnostics = correction_smoothing.diagnostics(model)
        t.eq(diagnostics.active_count, 1)
        t.is_true(diagnostics.maximum_magnitude < correction_smoothing.DEFAULT_HARD_SNAP_DISTANCE)

        model = correction_smoothing.advance(model, second, 0.1)
        t.near(correction_smoothing.pose(model).players[player_id].x, second.players[1].pos.x)
        t.eq(correction_smoothing.diagnostics(model).active_count, 0)
    end)

    t.it("hard-snaps corrections at the 160-world-unit threshold", function()
        local authoritative = new_match()
        local corrected = corrected_match(authoritative, 160, 160)
        local model =
            correction_smoothing.correct(correction_smoothing.new(authoritative), corrected)
        local pose = correction_smoothing.pose(model)
        t.near(pose.players[corrected.players[1].id].x, corrected.players[1].pos.x)
        t.near(pose.ball.x, corrected.ball.x)
        t.eq(correction_smoothing.diagnostics(model).active_count, 0)
    end)

    t.it("uses render dt consistently across different render rates", function()
        local authoritative = new_match()
        local corrected = corrected_match(authoritative, 90, 0)
        local player_id = corrected.players[1].id

        ---@param dt number
        ---@param count integer
        ---@return CorrectionSmoothingState
        local function run(dt, count)
            local model =
                correction_smoothing.correct(correction_smoothing.new(authoritative), corrected)
            for _ = 1, count do
                model = correction_smoothing.advance(model, corrected, dt)
            end
            return model
        end

        local slow = run(0.05, 1)
        local fast = run(0.01, 5)
        t.near(
            correction_smoothing.pose(slow).players[player_id].x,
            correction_smoothing.pose(fast).players[player_id].x
        )
        t.near(
            correction_smoothing.diagnostics(slow).maximum_magnitude,
            correction_smoothing.diagnostics(fast).maximum_magnitude
        )

        slow = run(0.05, 2)
        fast = run(0.01, 10)
        t.near(correction_smoothing.pose(slow).players[player_id].x, corrected.players[1].pos.x)
        t.near(correction_smoothing.pose(fast).players[player_id].x, corrected.players[1].pos.x)
    end)

    t.it("clears offsets immediately at lifecycle discontinuities", function()
        local authoritative = new_match()
        local corrected = corrected_match(authoritative, 70, 30)
        local model =
            correction_smoothing.correct(correction_smoothing.new(authoritative), corrected)
        t.is_true(correction_smoothing.diagnostics(model).active_count > 0)

        model = correction_smoothing.clear(model, corrected)
        local pose = correction_smoothing.pose(model)
        t.eq(correction_smoothing.diagnostics(model).active_count, 0)
        t.near(pose.players[corrected.players[1].id].x, corrected.players[1].pos.x)
        t.near(pose.ball.x, corrected.ball.x)
    end)

    t.it("derives bounded gait and lean from the smoothed trajectory", function()
        local authoritative = new_match()
        local corrected = corrected_match(authoritative, 60, 0)
        local corrected_hash = state_hash(corrected)
        local player_id = corrected.players[1].id
        local model = correction_smoothing.new(authoritative)
        view_state.reset()
        view_state.update(authoritative.players, 0, correction_smoothing.pose(model))

        model = correction_smoothing.correct(model, corrected)
        view_state.update(corrected.players, 1 / 60, correction_smoothing.pose(model))
        for _ = 1, 7 do
            model = correction_smoothing.advance(model, corrected, 1 / 60)
            view_state.update(corrected.players, 1 / 60, correction_smoothing.pose(model))
        end

        local view = assert(view_state.get(player_id))
        t.is_true(view.speed > 0)
        t.is_true(view.speed <= view_state.MAX_DISPLAY_SPEED)
        t.is_true(view.lean >= -1 and view.lean <= 1)
        t.is_true(view.phase > 0)
        t.eq(state_hash(corrected), corrected_hash)
        view_state.reset()
    end)
end)
