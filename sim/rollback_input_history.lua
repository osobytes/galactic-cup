-- Pure per-tick input history for rollback clients. It records transport-facing
-- authoritative arrivals and materializes the complete InputFrame consumed by
-- sim.match without knowing about sockets, wall clocks, or presentation.

local fixed_clock = require("sim.fixed_clock")
local input_frame = require("sim.input_frame")

---@alias RollbackInputSource "local"|"remote"
---@alias RollbackInputStatus "authoritative"|"predicted"
---@alias RollbackInputHistoryErrorCode "malformed"|"conflicting_authoritative"

---@class RollbackInputSlotRecord
---@field source RollbackInputSource
---@field status RollbackInputStatus
---@field sample InputSample

---@class RollbackInputTickRecord
---@field tick integer
---@field slots RollbackInputSlotRecord[]

---@class RollbackAuthoritativeArrival
---@field duplicate boolean -- True only when this exact authoritative sample already existed.
---@field confirmed_tick integer -- Highest contiguous all-authoritative tick, or -1 before tick zero.
---@field earliest_divergence integer? -- Earliest unconsumed corrected tick used by the simulation.

---@class RollbackInputHistory
---@field _sources RollbackInputSource[]
---@field _authoritative table<integer, table<integer, InputSample>>
---@field _authoritative_counts table<integer, integer>
---@field _effective table<integer, InputFrame>
---@field _records table<integer, RollbackInputTickRecord>
---@field _confirmed_tick integer
---@field _earliest_divergence integer?

---@class RollbackInputHistoryModule
local rollback_input_history = {}

rollback_input_history.ROLLBACK_WINDOW_TICKS = 30
rollback_input_history.ROLLBACK_WINDOW_MILLISECONDS = rollback_input_history.ROLLBACK_WINDOW_TICKS
    * 1000
    / fixed_clock.TICK_RATE

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
end

---@param history RollbackInputHistory
local function assert_history(history)
    assert(type(history) == "table", "rollback input history is required")
    assert(type(history._sources) == "table", "rollback input history sources are missing")
    assert(
        type(history._authoritative) == "table",
        "rollback authoritative input history is missing"
    )
    assert(type(history._effective) == "table", "rollback effective input history is missing")
end

---@param sample InputSample
---@return InputSample
local function copy_sample(sample)
    return assert(input_frame.new_sample(sample))
end

---@param left InputSample
---@param right InputSample
---@return boolean
local function samples_equal(left, right)
    return left.move_x == right.move_x
        and left.move_y == right.move_y
        and left.held == right.held
        and left.edges == right.edges
end

---@param frame InputFrame
---@return InputFrame
local function copy_frame(frame)
    return assert(input_frame.copy(frame))
end

---@param record RollbackInputTickRecord
---@return RollbackInputTickRecord
local function copy_record(record)
    local slots = {}
    for index = 1, input_frame.SLOT_COUNT do
        local slot = record.slots[index]
        slots[index] = {
            source = slot.source,
            status = slot.status,
            sample = copy_sample(slot.sample),
        }
    end
    return { tick = record.tick, slots = slots }
end

---@param sources RollbackInputSource[]
local function assert_sources(sources)
    assert(type(sources) == "table", "rollback input sources are required")
    for index in pairs(sources) do
        assert(
            is_integer(index) and index >= 1 and index <= input_frame.SLOT_COUNT,
            "rollback input sources must use canonical numeric indexes"
        )
    end
    for index = 1, input_frame.SLOT_COUNT do
        local source = sources[index]
        assert(
            source == "local" or source == "remote",
            "rollback input source " .. index .. " must be local or remote"
        )
    end
end

---@param tick any
---@param slot_index any
---@param sample any
---@return boolean?, string?, RollbackInputHistoryErrorCode?
local function validate_arrival(tick, slot_index, sample)
    if not is_integer(tick) or tick < 0 or tick > input_frame.MAX_TICK then
        return nil, "authoritative input tick must be a bounded non-negative integer", "malformed"
    end
    if not is_integer(slot_index) or slot_index < 1 or slot_index > input_frame.SLOT_COUNT then
        return nil, "authoritative input slot must be between one and eight", "malformed"
    end
    local ok, err = input_frame.validate_sample(sample)
    if not ok then
        return nil, err or "authoritative input sample is malformed", "malformed"
    end
    return true
end

---@param history RollbackInputHistory
local function advance_confirmation(history)
    local next_tick = history._confirmed_tick + 1
    while history._authoritative_counts[next_tick] == input_frame.SLOT_COUNT do
        history._confirmed_tick = next_tick
        next_tick = next_tick + 1
    end
end

---@param history RollbackInputHistory
---@param tick integer
---@param slot_index integer
---@return InputSample?
local function latest_authoritative(history, tick, slot_index)
    local latest_tick = -1
    local latest_sample = nil
    for authoritative_tick, slots in pairs(history._authoritative) do
        if authoritative_tick <= tick and authoritative_tick > latest_tick then
            local sample = slots[slot_index]
            if sample ~= nil then
                latest_tick = authoritative_tick
                latest_sample = sample
            end
        end
    end
    return latest_sample
end

---@param sources RollbackInputSource[] Canonical eight-slot local/remote ownership metadata.
---@return RollbackInputHistory
function rollback_input_history.new(sources)
    assert_sources(sources)
    local copied_sources = {}
    for index = 1, input_frame.SLOT_COUNT do
        copied_sources[index] = sources[index]
    end
    return {
        _sources = copied_sources,
        _authoritative = {},
        _authoritative_counts = {},
        _effective = {},
        _records = {},
        _confirmed_tick = -1,
        _earliest_divergence = nil,
    }
end

---@param history RollbackInputHistory
---@param slot_index integer
---@return RollbackInputSource
function rollback_input_history.source(history, slot_index)
    assert_history(history)
    assert(
        is_integer(slot_index) and slot_index >= 1 and slot_index <= input_frame.SLOT_COUNT,
        "rollback input slot must be between one and eight"
    )
    return history._sources[slot_index]
end

-- Store one local or remote authoritative sample. Transport-shaped validation
-- failures, including conflicting duplicates, are recoverable and leave the
-- history unchanged.
---@param history RollbackInputHistory
---@param tick integer
---@param slot_index integer
---@param sample InputSample
---@return RollbackAuthoritativeArrival?, string?, RollbackInputHistoryErrorCode?
function rollback_input_history.add_authoritative(history, tick, slot_index, sample)
    assert_history(history)
    local ok, err, code = validate_arrival(tick, slot_index, sample)
    if not ok then
        return nil, err, code
    end

    local slots = history._authoritative[tick]
    local existing = slots and slots[slot_index] or nil
    if existing ~= nil then
        if not samples_equal(existing, sample) then
            return nil,
                ("authoritative input conflicts at tick %d slot %d"):format(tick, slot_index),
                "conflicting_authoritative"
        end
        return {
            duplicate = true,
            confirmed_tick = history._confirmed_tick,
            earliest_divergence = history._earliest_divergence,
        }
    end

    local used_frame = history._effective[tick]
    if used_frame ~= nil and not samples_equal(used_frame.slots[slot_index], sample) then
        if history._earliest_divergence == nil or tick < history._earliest_divergence then
            history._earliest_divergence = tick
        end
    end

    if slots == nil then
        slots = {}
        history._authoritative[tick] = slots
        history._authoritative_counts[tick] = 0
    end
    slots[slot_index] = copy_sample(sample)
    history._authoritative_counts[tick] = history._authoritative_counts[tick] + 1
    advance_confirmation(history)

    return {
        duplicate = false,
        confirmed_tick = history._confirmed_tick,
        earliest_divergence = history._earliest_divergence,
    }
end

-- Materialize the exact frame that the simulation is about to use. Calling
-- this tick again during resimulation replaces its former used-input record
-- with a frame derived from the now-current authoritative history.
---@param history RollbackInputHistory
---@param tick integer
---@return InputFrame frame
---@return RollbackInputTickRecord record
function rollback_input_history.materialize(history, tick)
    assert_history(history)
    assert(
        is_integer(tick) and tick >= 0 and tick <= input_frame.MAX_TICK,
        "rollback input tick must be a bounded non-negative integer"
    )
    assert(
        history._earliest_divergence == nil or tick < history._earliest_divergence,
        "consume the earliest divergence before materializing the corrected timeline"
    )

    local authoritative = history._authoritative[tick]
    local samples = {}
    local records = {}
    for index = 1, input_frame.SLOT_COUNT do
        local sample = authoritative and authoritative[index] or nil
        assert(
            sample ~= nil or history._sources[index] == "remote",
            "local rollback input must be authoritative before materialization"
        )
        ---@type RollbackInputStatus
        local status = "authoritative"
        if sample == nil then
            status = "predicted"
            local prior = latest_authoritative(history, tick, index)
            if prior == nil then
                sample = input_frame.neutral_sample()
            else
                sample = {
                    move_x = prior.move_x,
                    move_y = prior.move_y,
                    held = prior.held,
                    edges = 0,
                }
            end
        end
        samples[index] = copy_sample(sample)
        records[index] = {
            source = history._sources[index],
            status = status,
            sample = copy_sample(sample),
        }
    end

    local frame = assert(input_frame.new(tick, samples))
    local record = { tick = tick, slots = records }
    history._effective[tick] = copy_frame(frame)
    history._records[tick] = copy_record(record)
    return copy_frame(frame), copy_record(record)
end

---@param history RollbackInputHistory
---@param tick integer
---@return RollbackInputTickRecord?
function rollback_input_history.record(history, tick)
    assert_history(history)
    local record = history._records[tick]
    return record and copy_record(record) or nil
end

---@param history RollbackInputHistory
---@param tick integer
---@param slot_index integer
---@return RollbackInputSlotRecord?
function rollback_input_history.authoritative_record(history, tick, slot_index)
    assert_history(history)
    local slots = history._authoritative[tick]
    local sample = slots and slots[slot_index] or nil
    if sample == nil then
        return nil
    end
    return {
        source = rollback_input_history.source(history, slot_index),
        status = "authoritative",
        sample = copy_sample(sample),
    }
end

---@param history RollbackInputHistory
---@return integer
function rollback_input_history.confirmed_tick(history)
    assert_history(history)
    return history._confirmed_tick
end

---@param history RollbackInputHistory
---@return integer?
function rollback_input_history.earliest_divergence(history)
    assert_history(history)
    return history._earliest_divergence
end

-- Consume the current correction batch boundary. Later differing arrivals can
-- then establish a new earliest divergence after the caller has resimulated.
---@param history RollbackInputHistory
---@return integer?
function rollback_input_history.consume_earliest_divergence(history)
    assert_history(history)
    local tick = history._earliest_divergence
    history._earliest_divergence = nil
    return tick
end

return rollback_input_history
