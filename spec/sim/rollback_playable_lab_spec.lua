local t = require("spec.support.runner")
local Vec2 = require("core.vec2")
local fixed_clock = require("sim.fixed_clock")
local input_frame = require("sim.input_frame")
local match = require("sim.match")
local match_snapshot = require("sim.match_snapshot")
local rollback_playable_lab = require("sim.rollback_playable_lab")
local teams = require("data.teams")

---@param duration number?
---@return MatchSnapshot
local function initial_snapshot(duration)
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion)
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        duration = duration or 2,
        max_goals = 99,
        seed = 74,
        input_ownership = ownership,
    })
    return match_snapshot.capture(state)
end

---@return MatchSnapshot
local function preventable_goal_snapshot()
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion)
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        duration = 1,
        max_goals = 1,
        seed = 733,
        input_ownership = ownership,
    })
    local carrier_index = state.slot_players[1]
    local carrier = state.players[carrier_index]
    carrier.pos = Vec2.new(900, 270)
    carrier.vel = Vec2.new(0, 0)
    carrier.run_vel = Vec2.new(0, 0)
    carrier.facing = Vec2.new(1, 0)
    carrier.windup_timer = fixed_clock.TICK_SECONDS
    carrier.windup_shot = {
        dir = Vec2.new(1, 0),
        speed = 900,
        vz = 0,
        spin = 0,
        shot_type = "ground",
    }
    state.owner = carrier_index
    state.ball = Vec2.new(918, 270)
    state.ball_vel = Vec2.new(0, 0)
    state.ball_z = 0
    state.ball_vz = 0
    state.pickup_cd = 2
    state.block_grace = 2
    for index, player in ipairs(state.players) do
        if index ~= carrier_index then
            player.pos = Vec2.new(index < 6 and 200 or 100, 40 + index)
            player.vel = Vec2.new(0, 0)
            player.run_vel = Vec2.new(0, 0)
        end
    end
    local defender = state.players[state.slot_players[5]]
    defender.pos = Vec2.new(910, 240)
    defender.facing = Vec2.new(-1, 0)
    return match_snapshot.capture(state)
end

---@param delay integer
---@param loss number?
---@return NetworkProfile
local function fixed_profile(delay, loss)
    return {
        base_delay_ticks = delay,
        jitter_min_ticks = 0,
        jitter_max_ticks = 0,
        independent_loss_rate = loss or 0,
        duplication_rate = 0,
        burst_start_rate = 0,
        burst_length_ticks = 0,
    }
end

---@param lab RollbackPlayableLab
---@param maximum integer?
---@return RollbackPlayableLabDebugModel
local function run_to_terminal(lab, maximum)
    local limit = maximum or 512
    for _ = 1, limit do
        local before = rollback_playable_lab.debug_model(lab)
        if before.status ~= "active" and before.status ~= "settling" then
            return before
        end
        local sample = rollback_playable_lab.needs_local_sample(lab)
                and input_frame.neutral_sample()
            or nil
        rollback_playable_lab.advance(lab, before.transport_tick, sample)
    end
    return rollback_playable_lab.debug_model(lab)
end

t.describe("playable rollback controller", function()
    t.it("constructs stable slot ownership and copied boundary zero", function()
        local lab = rollback_playable_lab.new(initial_snapshot(), {
            local_slot = 6,
            profile_name = "clean",
        })
        local current = rollback_playable_lab.current_snapshot(lab)
        t.is_true(current.state.slot_mode)
        t.eq(current.state.controlled, current.state.slot_players[6])
        local boundary = rollback_playable_lab.snapshot(lab, 0)
        t.eq(boundary.status, "present")
        t.eq(assert(boundary.snapshot).state.controlled, current.state.controlled)

        current.state.score.home = 9
        t.eq(rollback_playable_lab.current_snapshot(lab).state.score.home, 0)
        local debug = rollback_playable_lab.debug_model(lab)
        t.eq(debug.reference_tick, 0)
        t.eq(debug.current_tick, 0)
        t.eq(debug.transport_tick, 0)
        t.eq(debug.local_slot, 6)
        debug.convergence.status = "diverged"
        t.eq(rollback_playable_lab.debug_model(lab).convergence.status, "matched")
    end)

    t.it("submits one local row immediately and predicts seven networked rows", function()
        local lab = rollback_playable_lab.new(initial_snapshot(), {
            local_slot = 4,
            profile = fixed_profile(2),
            profile_name = "two_tick",
        })
        local batch = rollback_playable_lab.advance(lab, 0, input_frame.neutral_sample())
        t.eq(#batch.outputs, 1)
        local record = batch.outputs[1].input
        t.eq(record.tick, 0)
        t.eq(#record.slots, input_frame.SLOT_COUNT)
        for slot = 1, input_frame.SLOT_COUNT do
            if slot == 4 then
                t.eq(record.slots[slot].source, "local")
                t.eq(record.slots[slot].status, "authoritative")
            else
                t.eq(record.slots[slot].source, "remote")
                t.eq(record.slots[slot].status, "predicted")
            end
        end
        local debug = rollback_playable_lab.debug_model(lab)
        t.eq(debug.reference_tick, 1)
        t.eq(debug.current_tick, 1)
        t.eq(debug.transport_tick, 1)
        t.eq(debug.predicted_slot_samples, 7)
    end)

    t.it("performs real rollback and converges to the independent reference", function()
        local lab = rollback_playable_lab.new(initial_snapshot(8 * fixed_clock.TICK_SECONDS), {
            local_slot = 1,
            profile = fixed_profile(2),
            profile_name = "scripted",
            network_seed = 19,
            bot_seed = 91,
        })
        local saw_correction = false
        for _ = 1, 64 do
            local debug = rollback_playable_lab.debug_model(lab)
            if debug.status ~= "active" and debug.status ~= "settling" then
                break
            end
            local sample = rollback_playable_lab.needs_local_sample(lab)
                    and input_frame.neutral_sample()
                or nil
            local batch = rollback_playable_lab.advance(lab, debug.transport_tick, sample)
            if #batch.corrections > 0 then
                saw_correction = true
                batch.corrections[1].causal_tick = 999
            end
        end
        local debug = rollback_playable_lab.debug_model(lab)
        t.is_true(saw_correction, "the impaired remote bots must correct prediction")
        t.eq(debug.status, "converged")
        t.is_true(debug.rollback_count > 0)
        t.is_true(debug.resimulated_ticks > 0)
        t.eq(debug.convergence.status, "matched")
        t.eq(debug.reference_tick, debug.current_tick)
        t.eq(debug.confirmed_input_tick, debug.reference_tick - 1)
        t.is_true(
            not (debug.convergence.boundary == 999),
            "mutating a returned correction cannot change controller diagnostics"
        )
    end)

    t.it("settles transport incrementally without post-finish match frames", function()
        local lab = rollback_playable_lab.new(initial_snapshot(fixed_clock.TICK_SECONDS), {
            local_slot = 1,
            profile = fixed_profile(3),
            settlement_ticks = 16,
        })
        local first = rollback_playable_lab.advance(lab, 0, input_frame.neutral_sample())
        local after_finish = rollback_playable_lab.debug_model(lab)
        t.eq(after_finish.status, "settling")
        t.eq(#first.outputs, 1)
        local reference_tick = after_finish.reference_tick

        local second = rollback_playable_lab.advance(lab, 1, nil)
        local after_settle = rollback_playable_lab.debug_model(lab)
        t.eq(after_settle.reference_tick, reference_tick)
        t.eq(after_settle.transport_tick, 2)
        for _, output in ipairs(second.outputs) do
            t.is_true(output.tick < reference_tick, "settlement may only replay existing ticks")
        end
        local final = run_to_terminal(lab, 32)
        t.eq(final.status, "converged")
        t.eq(final.reference_tick, reference_tick)
    end)

    t.it("keeps producing reference authority after a predicted early finish", function()
        local lab = rollback_playable_lab.new(preventable_goal_snapshot(), {
            local_slot = 1,
            profile = fixed_profile(6),
            profile_name = "predicted_early_finish",
            bot_seed = rollback_playable_lab.DEFAULT_BOT_SEED,
            settlement_ticks = 64,
        })
        local saw_predicted_finish = false
        local reference_advanced_after_finish = false
        local predicted_reference_tick = nil
        for _ = 1, 128 do
            local before = rollback_playable_lab.debug_model(lab)
            if before.status ~= "active" and before.status ~= "settling" then
                break
            end
            local sample = rollback_playable_lab.needs_local_sample(lab)
                    and input_frame.neutral_sample()
                or nil
            rollback_playable_lab.advance(lab, before.transport_tick, sample)
            local after = rollback_playable_lab.debug_model(lab)
            if after.predicted_early_finish then
                saw_predicted_finish = true
                predicted_reference_tick = predicted_reference_tick or after.reference_tick
            elseif
                predicted_reference_tick ~= nil
                and after.reference_tick > predicted_reference_tick
            then
                reference_advanced_after_finish = true
            end
        end
        local final = rollback_playable_lab.debug_model(lab)
        t.is_true(saw_predicted_finish)
        t.is_true(reference_advanced_after_finish)
        t.eq(final.status, "converged")
        t.eq(final.convergence.status, "matched")
        t.eq(final.current_tick, final.reference_tick)
    end)

    t.it("confirms before appending at the exact event-window capacity", function()
        local lab = rollback_playable_lab.new(initial_snapshot(31 * fixed_clock.TICK_SECONDS), {
            local_slot = 1,
            profile = fixed_profile(30),
            max_rollback_ticks = 30,
            settlement_ticks = 64,
        })
        for tick = 0, 30 do
            local batch = rollback_playable_lab.advance(lab, tick, input_frame.neutral_sample())
            t.is_true(
                batch.status ~= "unconfirmed_window_exceeded",
                "delivery at the supported limit must free capacity before the new output"
            )
        end
        local debug = rollback_playable_lab.debug_model(lab)
        t.eq(debug.event_status, "active")
        t.is_true(debug.confirmed_output_tick >= 0)
    end)

    t.it("stops explicitly when event confirmation exceeds the bounded window", function()
        local lab = rollback_playable_lab.new(initial_snapshot(40 * fixed_clock.TICK_SECONDS), {
            local_slot = 1,
            profile = fixed_profile(31),
            max_rollback_ticks = 30,
        })
        local debug = run_to_terminal(lab, 40)
        t.eq(debug.status, "unconfirmed_window_exceeded")
        t.eq(debug.event_status, "unconfirmed_window_exceeded")
        local stopped_tick = debug.transport_tick
        local batch = rollback_playable_lab.advance(lab, stopped_tick, nil)
        t.eq(batch.status, "unconfirmed_window_exceeded")
        t.eq(rollback_playable_lab.debug_model(lab).transport_tick, stopped_tick)
    end)

    t.it("reports bounded drain failure instead of looping or inventing input", function()
        local lab = rollback_playable_lab.new(initial_snapshot(fixed_clock.TICK_SECONDS), {
            local_slot = 1,
            profile = fixed_profile(0, 1),
            settlement_ticks = 3,
        })
        local debug = run_to_terminal(lab, 8)
        t.eq(debug.status, "drain_incomplete")
        t.eq(debug.settlement_ticks, 3)
        t.eq(debug.reference_tick, 1)
        t.eq(debug.current_tick, 1)
        t.eq(debug.confirmed_input_tick, -1)
    end)
end)
