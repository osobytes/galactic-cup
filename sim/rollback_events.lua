-- Pure stable-event timeline for rollback presentation and confirmed consumers.
-- Identity is derived from simulation causality and never enters MatchState.

local input_frame = require("sim.input_frame")
local match_snapshot = require("sim.match_snapshot")

---@alias RollbackEventDomain
---| "lifecycle/goal"
---| "lifecycle/kickoff"
---| "lifecycle/full_time"
---| string

---@alias RollbackLifecycleKind "goal"|"kickoff"|"full_time"

---@class RollbackLifecyclePayload
---@field kind RollbackLifecycleKind
---@field team InputTeam?
---@field score { home: integer, away: integer }

---@class RollbackWrappedMatchEvent
---@field id string
---@field tick integer
---@field domain RollbackEventDomain
---@field ordinal integer
---@field payload MatchEvent

---@class RollbackWrappedLifecycleEvent
---@field id string
---@field tick integer
---@field domain RollbackEventDomain
---@field ordinal integer
---@field payload RollbackLifecyclePayload

---@alias RollbackWrappedEvent RollbackWrappedMatchEvent|RollbackWrappedLifecycleEvent

---@class RollbackEventReplacement
---@field before RollbackWrappedEvent
---@field after RollbackWrappedEvent

---@class RollbackEventDiff
---@field added RollbackWrappedEvent[]
---@field revoked RollbackWrappedEvent[]
---@field replaced RollbackEventReplacement[]

---@class RollbackEventStepInput
---@field output RollbackTickOutput
---@field snapshot MatchSnapshot -- Canonical post-step boundary.

---@class RollbackEventStep
---@field tick integer
---@field start_boundary integer
---@field end_boundary integer
---@field snapshot MatchSnapshot
---@field match_events RollbackWrappedMatchEvent[]
---@field lifecycle_events RollbackWrappedLifecycleEvent[]

---@class RollbackEventTimeline
---@field _confirmed_tick integer
---@field _confirmed_boundary integer
---@field _confirmed_snapshot MatchSnapshot
---@field _steps table<integer, RollbackEventStep>

---@class RollbackEventsModule
local rollback_events = {}

---@param value any
---@return any
local function copy_value(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[copy_value(key)] = copy_value(child)
    end
    return result
end

---@param snapshot MatchSnapshot
---@return MatchSnapshot
local function copy_snapshot(snapshot)
    return match_snapshot.capture(match_snapshot.restore(snapshot))
end

---@param left any
---@param right any
---@return boolean
local function equal_value(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not equal_value(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

---@param timeline RollbackEventTimeline
local function assert_timeline(timeline)
    assert(type(timeline) == "table", "rollback event timeline is required")
    assert(type(timeline._confirmed_tick) == "number", "rollback event confirmed cursor is missing")
    assert(
        type(timeline._confirmed_boundary) == "number",
        "rollback event confirmed boundary is missing"
    )
    assert(
        type(timeline._confirmed_snapshot) == "table",
        "rollback event confirmed snapshot is missing"
    )
    assert(type(timeline._steps) == "table", "rollback event speculative steps are missing")
end

---@param tick integer
---@param domain RollbackEventDomain
---@param ordinal integer
---@return string
local function event_id(tick, domain, ordinal)
    assert(
        tick >= 0 and tick <= input_frame.MAX_TICK,
        "rollback event tick is outside the input range"
    )
    assert(#domain <= 999, "rollback event domain is too long")
    assert(ordinal >= 1 and ordinal <= 9999, "rollback event ordinal is outside the ID range")
    return ("%010d|%03d:%s|%04d"):format(tick, #domain, domain, ordinal)
end

---@param event MatchEvent
---@return MatchEvent
local function copy_match_event(event)
    local result = {}
    for key, value in pairs(event) do
        assert(type(value) ~= "table", "rollback match event payloads must contain scalars")
        result[key] = value
    end
    ---@cast result MatchEvent
    return result
end

---@param event RollbackWrappedEvent
---@return RollbackWrappedEvent
local function copy_wrapped_event(event)
    return {
        id = event.id,
        tick = event.tick,
        domain = event.domain,
        ordinal = event.ordinal,
        payload = copy_value(event.payload),
    }
end

---@param events RollbackWrappedMatchEvent[]
---@return RollbackWrappedMatchEvent[]
local function copy_match_wrappers(events)
    local result = {}
    for index, event in ipairs(events) do
        result[index] = copy_wrapped_event(event)
    end
    ---@cast result RollbackWrappedMatchEvent[]
    return result
end

---@param events RollbackWrappedLifecycleEvent[]
---@return RollbackWrappedLifecycleEvent[]
local function copy_lifecycle_wrappers(events)
    local result = {}
    for index, event in ipairs(events) do
        result[index] = copy_wrapped_event(event)
    end
    ---@cast result RollbackWrappedLifecycleEvent[]
    return result
end

---@param step RollbackEventStep
---@return RollbackEventStep
local function copy_step(step)
    return {
        tick = step.tick,
        start_boundary = step.start_boundary,
        end_boundary = step.end_boundary,
        snapshot = copy_snapshot(step.snapshot),
        match_events = copy_match_wrappers(step.match_events),
        lifecycle_events = copy_lifecycle_wrappers(step.lifecycle_events),
    }
end

---@param tick integer
---@param events MatchEvent[]
---@return RollbackWrappedMatchEvent[]
local function wrap_match_events(tick, events)
    local counts = {}
    local wrapped = {}
    for index, event in ipairs(events) do
        local domain = "match/" .. event.kind
        local ordinal = (counts[domain] or 0) + 1
        counts[domain] = ordinal
        wrapped[index] = {
            id = event_id(tick, domain, ordinal),
            tick = tick,
            domain = domain,
            ordinal = ordinal,
            payload = copy_match_event(event),
        }
    end
    return wrapped
end

---@param tick integer
---@param domain RollbackEventDomain
---@param payload RollbackLifecyclePayload
---@return RollbackWrappedLifecycleEvent
local function lifecycle_event(tick, domain, payload)
    return {
        id = event_id(tick, domain, 1),
        tick = tick,
        domain = domain,
        ordinal = 1,
        payload = copy_value(payload),
    }
end

---@param tick integer
---@param before MatchSnapshot
---@param after MatchSnapshot
---@return RollbackWrappedLifecycleEvent[]
local function derive_lifecycle_events(tick, before, after)
    local pre = before.state
    local post = after.state
    local score = { home = post.score.home, away = post.score.away }
    local events = {}
    local scoring_team = nil
    if post.score.home == pre.score.home + 1 and post.score.away == pre.score.away then
        scoring_team = "home"
    elseif post.score.away == pre.score.away + 1 and post.score.home == pre.score.home then
        scoring_team = "away"
    else
        assert(
            post.score.home == pre.score.home and post.score.away == pre.score.away,
            "rollback lifecycle score transition must contain at most one goal"
        )
    end

    if scoring_team then
        events[#events + 1] = lifecycle_event(tick, "lifecycle/goal", {
            kind = "goal",
            team = scoring_team,
            score = score,
        })
        if not post.finished then
            events[#events + 1] = lifecycle_event(tick, "lifecycle/kickoff", {
                kind = "kickoff",
                team = scoring_team == "home" and "away" or "home",
                score = score,
            })
        end
    end
    if not pre.finished and post.finished then
        events[#events + 1] = lifecycle_event(tick, "lifecycle/full_time", {
            kind = "full_time",
            score = score,
        })
    else
        assert(not pre.finished or post.finished, "rollback lifecycle cannot return from full time")
    end
    return events
end

---@param output RollbackTickOutput
---@param snapshot MatchSnapshot
local function assert_step_coherent(output, snapshot)
    assert(type(output) == "table", "rollback event output is required")
    assert(type(snapshot) == "table", "rollback event post-step snapshot is required")
    assert(output.tick == output.start_boundary, "rollback event output start boundary is invalid")
    assert(output.end_boundary == output.tick + 1, "rollback event output must advance one tick")
    assert(
        snapshot.state.input_tick == output.end_boundary,
        "rollback event snapshot boundary does not match output"
    )
    assert(
        output.state.score.home == snapshot.state.score.home,
        "rollback output home score differs"
    )
    assert(
        output.state.score.away == snapshot.state.score.away,
        "rollback output away score differs"
    )
    assert(output.state.time_left == snapshot.state.time_left, "rollback output time differs")
    assert(output.state.finished == snapshot.state.finished, "rollback output finish differs")
    assert(output.finished == snapshot.state.finished, "rollback output finish flag differs")
    assert(
        equal_value(output.events, snapshot.state.events),
        "rollback output events differ from post-step snapshot"
    )
end

---@param timeline RollbackEventTimeline
---@return integer
local function latest_speculative_tick(timeline)
    local latest = timeline._confirmed_tick
    for tick in pairs(timeline._steps) do
        latest = math.max(latest, tick)
    end
    return latest
end

---@param timeline RollbackEventTimeline
---@param tick integer
---@return MatchSnapshot
local function snapshot_before(timeline, tick)
    if tick == timeline._confirmed_boundary then
        return timeline._confirmed_snapshot
    end
    local previous = assert(
        timeline._steps[tick - 1],
        ("rollback event step %d is missing its previous boundary"):format(tick)
    )
    assert(
        previous.end_boundary == tick,
        ("rollback event step %d has a noncontiguous previous boundary"):format(tick)
    )
    return previous.snapshot
end

---@param output RollbackTickOutput
---@param snapshot MatchSnapshot
---@param before MatchSnapshot
---@return RollbackEventStep
local function make_step(output, snapshot, before)
    assert_step_coherent(output, snapshot)
    local canonical = copy_snapshot(snapshot)
    return {
        tick = output.tick,
        start_boundary = output.start_boundary,
        end_boundary = output.end_boundary,
        snapshot = canonical,
        match_events = wrap_match_events(output.tick, output.events),
        lifecycle_events = derive_lifecycle_events(output.tick, before, canonical),
    }
end

---@param steps table<integer, RollbackEventStep>
---@param from_tick integer
---@param through_tick integer
---@return RollbackWrappedEvent[]
local function ordered_events(steps, from_tick, through_tick)
    local events = {}
    for tick = from_tick, through_tick do
        local step = steps[tick]
        if step then
            for _, event in ipairs(step.match_events) do
                events[#events + 1] = event
            end
            for _, event in ipairs(step.lifecycle_events) do
                events[#events + 1] = event
            end
        end
    end
    return events
end

---@param old_events RollbackWrappedEvent[]
---@param new_events RollbackWrappedEvent[]
---@return RollbackEventDiff
local function diff_events(old_events, new_events)
    local old_by_id = {}
    local new_by_id = {}
    for _, event in ipairs(old_events) do
        assert(old_by_id[event.id] == nil, "rollback event identity collision in stale timeline")
        old_by_id[event.id] = event
    end
    for _, event in ipairs(new_events) do
        assert(
            new_by_id[event.id] == nil,
            "rollback event identity collision in corrected timeline"
        )
        new_by_id[event.id] = event
    end

    local diff = { added = {}, revoked = {}, replaced = {} }
    for _, event in ipairs(new_events) do
        local old = old_by_id[event.id]
        if old == nil then
            diff.added[#diff.added + 1] = copy_wrapped_event(event)
        elseif not equal_value(old.payload, event.payload) then
            diff.replaced[#diff.replaced + 1] = {
                before = copy_wrapped_event(old),
                after = copy_wrapped_event(event),
            }
        end
    end
    for _, event in ipairs(old_events) do
        if new_by_id[event.id] == nil then
            diff.revoked[#diff.revoked + 1] = copy_wrapped_event(event)
        end
    end
    return diff
end

---@param initial_snapshot MatchSnapshot Canonical boundary zero.
---@return RollbackEventTimeline
function rollback_events.new(initial_snapshot)
    local canonical = copy_snapshot(initial_snapshot)
    assert(canonical.state.input_tick == 0, "rollback event timeline requires boundary zero")
    return {
        _confirmed_tick = -1,
        _confirmed_boundary = 0,
        _confirmed_snapshot = canonical,
        _steps = {},
    }
end

---@param timeline RollbackEventTimeline
---@param replaced_from_tick integer
---@param replaced_through_tick integer
---@param steps RollbackEventStepInput[]
---@return RollbackEventDiff
function rollback_events.apply(timeline, replaced_from_tick, replaced_through_tick, steps)
    assert_timeline(timeline)
    assert(
        type(replaced_from_tick) == "number"
            and replaced_from_tick == math.floor(replaced_from_tick)
            and replaced_from_tick >= 0,
        "rollback event replacement start must be a non-negative integer"
    )
    assert(
        type(replaced_through_tick) == "number"
            and replaced_through_tick == math.floor(replaced_through_tick)
            and replaced_through_tick >= replaced_from_tick,
        "rollback event replacement end must not precede its start"
    )
    assert(
        replaced_from_tick > timeline._confirmed_tick,
        "rollback events cannot correct an already-confirmed tick"
    )
    assert(type(steps) == "table", "rollback event corrected steps are required")

    local latest = latest_speculative_tick(timeline)
    local replacing = timeline._steps[replaced_from_tick] ~= nil
    if replacing then
        assert(
            replaced_through_tick == latest,
            "rollback event correction must replace the complete speculative tail"
        )
        for tick = replaced_from_tick, replaced_through_tick do
            assert(
                timeline._steps[tick] ~= nil,
                ("rollback event correction is missing stale tick %d"):format(tick)
            )
        end
    else
        assert(
            replaced_from_tick == latest + 1
                and replaced_through_tick == replaced_from_tick
                and #steps == 1,
            "rollback event normal apply must append exactly one contiguous step"
        )
    end

    local previous_snapshot = snapshot_before(timeline, replaced_from_tick)
    local old_steps = {}
    for tick = replaced_from_tick, replaced_through_tick do
        old_steps[tick] = timeline._steps[tick]
        timeline._steps[tick] = nil
    end

    local new_steps = {}
    for index, supplied in ipairs(steps) do
        assert(type(supplied) == "table", "rollback event step input is required")
        local output = supplied.output
        local expected_tick = replaced_from_tick + index - 1
        assert(
            output.tick == expected_tick,
            ("rollback event corrected step %d is noncontiguous"):format(output.tick)
        )
        assert(
            output.tick <= replaced_through_tick,
            "rollback event corrected steps extend beyond the replaced interval"
        )
        local step = make_step(output, supplied.snapshot, previous_snapshot)
        new_steps[step.tick] = step
        timeline._steps[step.tick] = step
        previous_snapshot = step.snapshot
    end

    local old_events = ordered_events(old_steps, replaced_from_tick, replaced_through_tick)
    local corrected_through = replaced_from_tick + #steps - 1
    local new_events = ordered_events(new_steps, replaced_from_tick, corrected_through)
    return diff_events(old_events, new_events)
end

---@param timeline RollbackEventTimeline
---@param confirmed_output_tick integer
---@return RollbackEventStep[]
function rollback_events.confirm(timeline, confirmed_output_tick)
    assert_timeline(timeline)
    assert(
        type(confirmed_output_tick) == "number"
            and confirmed_output_tick == math.floor(confirmed_output_tick)
            and confirmed_output_tick >= -1,
        "rollback event confirmation must be an integer at or after -1"
    )
    assert(
        confirmed_output_tick >= timeline._confirmed_tick,
        "rollback event confirmation cannot move backward"
    )
    if confirmed_output_tick == timeline._confirmed_tick then
        return {}
    end

    local confirmed = {}
    for tick = timeline._confirmed_tick + 1, confirmed_output_tick do
        local step = assert(
            timeline._steps[tick],
            ("rollback event confirmation is missing tick %d"):format(tick)
        )
        assert(
            step.start_boundary == timeline._confirmed_boundary,
            ("rollback event confirmation is noncontiguous at tick %d"):format(tick)
        )
        confirmed[#confirmed + 1] = copy_step(step)
        timeline._confirmed_tick = tick
        timeline._confirmed_boundary = step.end_boundary
        timeline._confirmed_snapshot = copy_snapshot(step.snapshot)
        timeline._steps[tick] = nil
    end
    return confirmed
end

return rollback_events
