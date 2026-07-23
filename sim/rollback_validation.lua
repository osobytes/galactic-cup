-- Pure OMP-2 validation campaign and deterministic scenario registry adapter.
-- Runtime clocks, process memory, browser identity, and game-layer consumers
-- remain outside this module.

local fnv1a64 = require("core.fnv1a64")
local Vec2 = require("core.vec2")
local config = require("data.omp2_rollback_validation")
local network_profiles = require("data.network_profiles")
local teams = require("data.teams")
local determinism_evidence = require("sim.determinism_evidence")
local fixed_clock = require("sim.fixed_clock")
local input_frame = require("sim.input_frame")
local input_tape = require("sim.input_tape")
local match = require("sim.match")
local match_snapshot = require("sim.match_snapshot")
local rollback_lab = require("sim.rollback_lab")
local tuning = require("sim.tuning")

---@alias RollbackValidationSuite
---| "native"
---| "browser-full"
---| "browser-stress"
---| "late-window"
---| "soak"

---@class RollbackValidationOptions
---@field profile_name string?
---@field network_seed integer?
---@field measure RollbackSessionMeasure?

---@class RollbackValidationCaseSpec
---@field id string
---@field scenario string
---@field tape InputTape
---@field options RollbackLabOptions
---@field expected_failure boolean
---@field sample string?

---@class RollbackValidationCompletedCase
---@field id string
---@field scenario string
---@field initial_snapshot MatchSnapshot
---@field result RollbackLabResult
---@field expected_failure boolean
---@field accepted boolean
---@field hidden_progress boolean
---@field scenario_pass boolean
---@field sample string?

---@class RollbackValidationCampaign
---@field suite RollbackValidationSuite
---@field cases RollbackValidationCaseSpec[]
---@field next_case integer
---@field active RollbackLabCampaign?
---@field active_spec RollbackValidationCaseSpec?
---@field completed integer
---@field failed boolean
---@field logical Fnv1a64State
---@field result RollbackValidationResult?

---@class RollbackValidationResult
---@field schema integer
---@field suite RollbackValidationSuite
---@field success boolean
---@field case_count integer
---@field logical_digest string

---@class RollbackValidationModule
local rollback_validation = {}

rollback_validation.SCHEMA = 1

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
end

---@return RollbackInputSource[]
local function sources()
    local result = { "local" }
    for slot = 2, input_frame.SLOT_COUNT do
        result[slot] = "remote"
    end
    return result
end

---@param source InputTape
---@param first_boundary integer
---@return MatchState
local function state_at(source, first_boundary)
    local state = match_snapshot.restore(source.initial)
    for index = 1, first_boundary do
        match.step(state, fixed_clock.TICK_SECONDS, source.frames[index])
    end
    return state
end

---@param source InputTape
---@param first_boundary integer
---@param last_boundary integer
---@param scenario string
---@return InputTape
local function normalized_window(source, first_boundary, last_boundary, scenario)
    assert(
        first_boundary >= 0 and last_boundary > first_boundary and last_boundary <= #source.frames,
        "rollback validation window is outside the frozen tape"
    )
    local state = state_at(source, first_boundary)
    state.input_tick = 0
    state.events = {}
    local initial = match_snapshot.capture(state)
    local frames = {}
    for boundary = first_boundary, last_boundary - 1 do
        local frame = assert(input_frame.copy(source.frames[boundary + 1]))
        frame.tick = #frames
        assert(input_frame.validate(frame))
        frames[#frames + 1] = frame
    end
    local identity = input_tape.copy_identity(source.identity)
    identity.build = "omp2-rollback-validation-v1"
    identity.source = "omp2-normalized-" .. scenario
    identity.fixture = "omp2-" .. scenario
    identity.config = identity.config .. ";normalized_boundary=" .. first_boundary
    return input_tape.new(identity, initial, frames)
end

---@param source InputTape
---@param predicate fun(before: MatchState, after: MatchState): boolean
---@return integer
local function scan_tick(source, predicate)
    local state = match_snapshot.restore(source.initial)
    for index, frame in ipairs(source.frames) do
        local before = match_snapshot.restore(match_snapshot.capture(state))
        match.step(state, fixed_clock.TICK_SECONDS, frame)
        if predicate(before, state) then
            return index - 1
        end
    end
    assert(false, "rollback validation scan predicate was not covered")
    return 0
end

---@param state MatchState
---@return string?
local function owner_id(state)
    return state.owner and state.players[state.owner].id or nil
end

---@param source InputTape
---@param scenario Omp2RollbackScenario
---@return InputTape
local function scanned_window(source, scenario)
    local tick
    if scenario.id == "possession_change" then
        tick = scan_tick(source, function(before, after)
            local prior = owner_id(before)
            local current = owner_id(after)
            return prior ~= nil and current ~= prior
        end)
    else
        local expected = assert(scenario.event_kind)
        tick = scan_tick(source, function(_, after)
            for _, event in ipairs(after.events) do
                if event.kind == expected then
                    return true
                end
            end
            return false
        end)
    end
    local first = math.max(0, tick - 2)
    local last = math.min(#source.frames, tick + 3)
    return normalized_window(source, first, last, scenario.id)
end

---@return InputTape
local function synthetic_goal_tape()
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion)
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        duration = 2,
        max_goals = 3,
        seed = 83,
        input_ownership = ownership,
    })
    local away_keeper = state.players[6]
    away_keeper.keeper_state = "retreat"
    away_keeper.keeper_state_timer = 0.1
    away_keeper.keeper_release_state = "advance"
    away_keeper.keeper_release_motion = 0.5
    away_keeper.keeper_release_kind = "chip"
    away_keeper.keeper_release_depth = 42
    away_keeper.receive_timer = 1
    state.owner = nil
    state.ball = Vec2.new(965, 270)
    state.ball_vel = Vec2.new(600, 0)
    state.ball_z = 0
    state.ball_vz = 0
    state.pickup_cd = 1
    state.block_grace = 1
    local frames = {
        assert(input_frame.neutral(0)),
        assert(input_frame.neutral(1)),
        assert(input_frame.neutral(2)),
    }
    local identity = {
        tape_version = input_tape.VERSION,
        input_version = input_frame.VERSION,
        snapshot_version = match_snapshot.VERSION,
        build = "omp2-rollback-validation-v1",
        source = "omp2-synthetic-goal-kickoff-v1",
        content = "nebula-orion-showcase-content-v1",
        tuning = tuning.serialize(),
        config = "field=960x540;duration=2;max_goals=3;tick_rate=60",
        fixture = "omp2-goal-kickoff",
        seed = 83,
        tick_rate = fixed_clock.TICK_RATE,
        ownership = ownership,
    }
    return input_tape.new(identity, match_snapshot.capture(state), frames)
end

---@return InputTape
local function late_window_tape()
    local source = determinism_evidence.fixture_tape()
    local initial = match_snapshot.capture(match_snapshot.restore(source.initial))
    local frames = {}
    for tick = 0, 39 do
        local slots = {}
        for slot = 1, input_frame.SLOT_COUNT do
            slots[slot] = input_frame.neutral_sample()
        end
        slots[2] = assert(input_frame.new_sample({
            move_x = tick % 2 == 0 and input_frame.MOVE_SCALE or -input_frame.MOVE_SCALE,
        }))
        frames[#frames + 1] = assert(input_frame.new(tick, slots))
    end
    local identity = input_tape.copy_identity(source.identity)
    identity.build = "omp2-rollback-validation-v1"
    identity.source = "omp2-late-window-v1"
    identity.fixture = "omp2-late-window"
    identity.config = "field=960x540;duration=120;max_goals=3;tick_rate=60;ticks=40"
    return input_tape.new(identity, initial, frames)
end

---@param profile_name string
---@param network_seed integer
---@param measure RollbackSessionMeasure?
---@return RollbackLabOptions
local function lab_options(profile_name, network_seed, measure)
    return {
        profile_name = profile_name,
        network_seed = network_seed,
        sources = sources(),
        measure = measure,
    }
end

---@param id string
---@param scenario string
---@param tape InputTape
---@param options RollbackLabOptions
---@param expected_failure boolean?
---@param sample string?
---@return RollbackValidationCaseSpec
local function case_spec(id, scenario, tape, options, expected_failure, sample)
    return {
        id = id,
        scenario = scenario,
        tape = tape,
        options = options,
        expected_failure = expected_failure == true,
        sample = sample,
    }
end

---@param measure RollbackSessionMeasure?
---@param profile_name string
---@param network_seed integer
---@return RollbackValidationCaseSpec[]
local function scenario_cases(measure, profile_name, network_seed)
    local source = determinism_evidence.fixture_tape()
    local goal = synthetic_goal_tape()
    local cases = {}
    for _, scenario in ipairs(config.scenarios) do
        local tape
        if scenario.kind == "synthetic_goal" then
            tape = goal
        elseif scenario.kind == "scan" then
            tape = scanned_window(source, scenario)
        else
            tape = normalized_window(
                source,
                assert(scenario.first_boundary),
                assert(scenario.last_boundary),
                scenario.id
            )
        end
        cases[#cases + 1] = case_spec(
            ("scenario-%s-%s-%d"):format(scenario.id, profile_name, network_seed),
            scenario.id,
            tape,
            lab_options(profile_name, network_seed, measure)
        )
    end
    return cases
end

---@param target RollbackValidationCaseSpec[]
---@param added RollbackValidationCaseSpec[]
local function append_cases(target, added)
    for _, row in ipairs(added) do
        target[#target + 1] = row
    end
end

---@param suite RollbackValidationSuite
---@param options RollbackValidationOptions
---@return RollbackValidationCaseSpec[]
local function plan_cases(suite, options)
    local cases = {}
    local full = determinism_evidence.fixture_tape()
    if suite == "native" then
        for _, profile_name in ipairs(config.full_profiles) do
            for _, network_seed in ipairs(config.network_seeds) do
                cases[#cases + 1] = case_spec(
                    ("full-%s-%d"):format(profile_name, network_seed),
                    "complete_fixture",
                    full,
                    lab_options(profile_name, network_seed, options.measure)
                )
            end
        end
        for _, network_seed in ipairs(config.network_seeds) do
            append_cases(
                cases,
                scenario_cases(options.measure, config.stress_profile, network_seed)
            )
        end
    elseif suite == "browser-full" then
        local profile_name = assert(options.profile_name, "browser-full requires a profile")
        local network_seed = assert(options.network_seed, "browser-full requires a network seed")
        cases[1] = case_spec(
            ("full-%s-%d"):format(profile_name, network_seed),
            "complete_fixture",
            full,
            lab_options(profile_name, network_seed, options.measure)
        )
    elseif suite == "browser-stress" then
        local profile_name = options.profile_name or config.stress_profile
        local network_seed = assert(options.network_seed, "browser-stress requires a network seed")
        append_cases(cases, scenario_cases(options.measure, profile_name, network_seed))
    elseif suite == "late-window" then
        local tape = late_window_tape()
        for _, delay in ipairs({ 30, 31 }) do
            local profile = {
                base_delay_ticks = delay,
                jitter_min_ticks = 0,
                jitter_max_ticks = 0,
                independent_loss_rate = 0,
                duplication_rate = 0,
                burst_start_rate = 0,
                burst_length_ticks = 0,
            }
            local case_options = lab_options("delay_" .. delay, delay, options.measure)
            case_options.profile = profile
            cases[#cases + 1] =
                case_spec("delay-" .. delay, "late_window", tape, case_options, delay == 31)
        end
    elseif suite == "soak" then
        for index, network_seed in ipairs(config.soak_network_seeds) do
            cases[#cases + 1] = case_spec(
                ("soak-%d-%d"):format(index, network_seed),
                "complete_fixture",
                full,
                lab_options("playable", network_seed, options.measure),
                false,
                config.soak_samples[index]
            )
        end
    end
    assert(#cases > 0, "rollback validation suite has no cases")
    return cases
end

---@param result RollbackLabResult
---@param scenario string
---@return boolean
local function scenario_covered(result, scenario)
    if scenario == "complete_fixture" or scenario == "late_window" then
        return true
    end
    if scenario == "repeated_rollback" then
        return result.metrics.rollback_count >= 2
    end
    local previous_owner = nil
    for _, row in ipairs(result.event_trace) do
        if row.kind == "reference_confirmed" then
            local step = assert(row.step)
            if scenario == "possession_change" then
                local current = step.state.owner_id
                if previous_owner ~= nil and current ~= previous_owner then
                    return true
                end
                previous_owner = current
            end
            for _, event in ipairs(step.match_events) do
                local kind = event.payload.kind
                if
                    (scenario == "tackle" and kind == "tackle")
                    or (scenario == "shot" and kind == "shot")
                    or (scenario == "aerial" and kind == "header")
                    or (scenario == "keeper_action" and kind == "catch")
                then
                    return true
                end
            end
            for _, event in ipairs(step.lifecycle_events) do
                local kind = event.payload.kind
                if
                    (scenario == "goal" and kind == "goal")
                    or (scenario == "kickoff" and kind == "kickoff")
                    or (scenario == "full_time" and kind == "full_time")
                then
                    return true
                end
            end
        end
    end
    return false
end

---@param spec RollbackValidationCaseSpec
---@param result RollbackLabResult
---@return RollbackValidationCompletedCase
local function complete_case(spec, result)
    local expected_terminal = spec.expected_failure
        and not result.success
        and result.status == "late_input_unrecoverable"
        and result.late_input_tick == 0
    local scenario_pass = scenario_covered(result, spec.scenario)
    local accepted = (result.success or expected_terminal) and scenario_pass
    return {
        id = spec.id,
        scenario = spec.scenario,
        initial_snapshot = spec.tape.initial,
        result = result,
        expected_failure = spec.expected_failure,
        accepted = accepted,
        hidden_progress = false,
        scenario_pass = scenario_pass,
        sample = spec.sample,
    }
end

---@param suite RollbackValidationSuite
---@param options RollbackValidationOptions?
---@return RollbackValidationCampaign
function rollback_validation.new_campaign(suite, options)
    options = options or {}
    assert(
        suite == "native"
            or suite == "browser-full"
            or suite == "browser-stress"
            or suite == "late-window"
            or suite == "soak",
        "unknown rollback validation suite"
    )
    if options.network_seed ~= nil then
        assert(is_integer(options.network_seed), "rollback validation network seed must be integer")
    end
    return {
        suite = suite,
        cases = plan_cases(suite, options),
        next_case = 1,
        active = nil,
        active_spec = nil,
        completed = 0,
        failed = false,
        logical = fnv1a64.new(),
        result = nil,
    }
end

---@param campaign RollbackValidationCampaign
---@param max_ticks integer
---@return RollbackValidationResult?
---@return RollbackValidationCompletedCase?
function rollback_validation.step_campaign(campaign, max_ticks)
    assert(is_integer(max_ticks) and max_ticks > 0, "validation step must be positive")
    if campaign.result then
        return campaign.result, nil
    end
    if campaign.active == nil then
        local spec = assert(campaign.cases[campaign.next_case])
        campaign.active_spec = spec
        campaign.active = rollback_lab.new_campaign(spec.tape, spec.options)
    end
    local result = rollback_lab.step_campaign(assert(campaign.active), max_ticks)
    if result == nil then
        return nil, nil
    end
    local spec = assert(campaign.active_spec)
    local completed = complete_case(spec, result)
    campaign.completed = campaign.completed + 1
    campaign.failed = campaign.failed or not completed.accepted
    fnv1a64.update(
        campaign.logical,
        completed.id .. "\n" .. rollback_lab.logical_marker(result) .. "\n"
    )
    campaign.next_case = campaign.next_case + 1
    campaign.active = nil
    campaign.active_spec = nil
    if campaign.next_case > #campaign.cases then
        campaign.result = {
            schema = rollback_validation.SCHEMA,
            suite = campaign.suite,
            success = not campaign.failed,
            case_count = campaign.completed,
            logical_digest = fnv1a64.hex(campaign.logical),
        }
    end
    return campaign.result, completed
end

---@param completed RollbackValidationCompletedCase
---@return string
function rollback_validation.case_marker(completed)
    local result = completed.result
    local metrics = result.metrics
    local events = result.event_metrics
    return table.concat({
        "GC_ROLLBACK_VALIDATION",
        "case",
        "schema=1",
        "case=" .. completed.id,
        "scenario=" .. completed.scenario,
        "fixture=" .. result.fixture,
        "profile=" .. result.profile,
        "network_seed=" .. result.network_seed,
        "success=" .. (completed.accepted and "1" or "0"),
        "lab_success=" .. (result.success and "1" or "0"),
        "expected_failure=" .. (completed.expected_failure and "1" or "0"),
        "status=" .. result.status,
        "late_tick=" .. tostring(result.late_input_tick or "none"),
        "hidden_progress=" .. (completed.hidden_progress and "1" or "0"),
        "scenario_pass=" .. (completed.scenario_pass and "1" or "0"),
        "tape_digest=" .. result.tape_digest,
        "reference_hash=" .. result.reference_final_hash,
        "client_hash=" .. result.client_final_hash,
        "rollbacks=" .. metrics.rollback_count,
        "max_depth=" .. metrics.max_rollback_depth,
        "resimulated=" .. metrics.resimulated_ticks,
        "peak_snapshots=" .. metrics.peaks.snapshot_count,
        "peak_snapshot_bytes=" .. metrics.peaks.snapshot_bytes,
        "peak_history_bytes=" .. metrics.peaks.history_bytes,
        "event_reference_digest=" .. events.reference_digest,
        "event_confirmed_digest=" .. events.confirmed_digest,
        "event_residue=" .. events.speculative_residue,
        "sample=" .. tostring(completed.sample or "none"),
    }, "|")
end

---@param result RollbackValidationResult
---@return string
function rollback_validation.result_marker(result)
    return table.concat({
        "GC_ROLLBACK_VALIDATION",
        "result",
        "schema=" .. result.schema,
        "suite=" .. result.suite,
        "success=" .. (result.success and "1" or "0"),
        "logical_digest=" .. result.logical_digest,
        "case_count=" .. result.case_count,
    }, "|")
end

---@return Omp2RollbackValidationData
function rollback_validation.config()
    return config
end

---@return string
function rollback_validation.profile_digest()
    local state = fnv1a64.new()
    for _, name in ipairs(config.full_profiles) do
        local profile = assert(network_profiles[name])
        fnv1a64.update(state, table.concat({
            name,
            tostring(profile.base_delay_ticks),
            tostring(profile.jitter_min_ticks),
            tostring(profile.jitter_max_ticks),
            tostring(profile.independent_loss_rate),
            tostring(profile.duplication_rate),
            tostring(profile.burst_start_rate),
            tostring(profile.burst_length_ticks),
        }, "|") .. "\n")
    end
    return fnv1a64.hex(state)
end

return rollback_validation
