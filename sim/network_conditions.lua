-- Deterministic, in-process packet impairment for rollback laboratory runs.
-- Transport time is an integer tick owned by the caller and is deliberately
-- separate from the input tick carried by each authoritative sample.

local rng = require("core.rng")
local input_frame = require("sim.input_frame")

---@alias NetworkConditionErrorCode
---| "malformed"
---| "conflicting_authoritative"
---| "stale_authoritative"
---| "not_retained"

---@alias NetworkDropReason "independent_loss"|"burst_loss"

---@class NetworkInputRecord
---@field tick integer
---@field sample InputSample

---@class NetworkDelivery
---@field source_slot integer
---@field send_tick integer
---@field sequence integer
---@field duplicate_ordinal integer -- Zero for the original and one for its duplicate.
---@field arrival_tick integer
---@field current NetworkInputRecord
---@field history NetworkInputRecord[] -- At most six records, oldest first.

---@class NetworkSendReceipt
---@field sequence integer
---@field dropped boolean
---@field drop_reason NetworkDropReason?
---@field arrival_tick integer?
---@field duplicated boolean
---@field authoritative_duplicate boolean

---@class NetworkConditionCounters
---@field sent integer -- Source packets, excluding impairment-created duplicates.
---@field delivered integer -- Delivered envelopes, including duplicates.
---@field independent_lost integer
---@field burst_lost integer
---@field duplicated integer -- Duplicate envelopes scheduled for delivery.
---@field reordered integer -- Unique sequence identities delivered after a later sequence.
---@field history_recovered integer -- First-seen samples recovered from redundant history.

---@class NetworkResendRequest
---@field source_slot integer
---@field input_tick integer

---@class NetworkDrainResult
---@field deliveries NetworkDelivery[]
---@field final_tick integer
---@field complete boolean
---@field pending integer
---@field recovered integer
---@field requested integer

---@class NetworkConditions
---@field _profile NetworkProfile
---@field _rng integer
---@field _sequence integer
---@field _clock_tick integer
---@field _records table<integer, NetworkInputRecord[]>
---@field _pending NetworkDelivery[]
---@field _burst_until table<integer, integer>
---@field _delivered_samples table<integer, table<integer, InputSample>>
---@field _max_delivered_sequence integer
---@field _reordered_sequences table<integer, boolean>
---@field _counters NetworkConditionCounters

---@class NetworkConditionsModule
local network_conditions = {}

network_conditions.HISTORY_RECORDS = 6
network_conditions.RETAINED_RECORDS = network_conditions.HISTORY_RECORDS + 1

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
end

---@param value any
---@return boolean
local function is_rate(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value >= 0
        and value <= 1
end

---@param code NetworkConditionErrorCode
---@param message string
---@return nil, string, NetworkConditionErrorCode
local function failure(code, message)
    return nil, message, code
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

---@param record NetworkInputRecord
---@return NetworkInputRecord
local function copy_record(record)
    return { tick = record.tick, sample = copy_sample(record.sample) }
end

---@param records NetworkInputRecord[]
---@return NetworkInputRecord[]
local function copy_records(records)
    local copied = {}
    for index, record in ipairs(records) do
        copied[index] = copy_record(record)
    end
    return copied
end

---@param delivery NetworkDelivery
---@return NetworkDelivery
local function copy_delivery(delivery)
    return {
        source_slot = delivery.source_slot,
        send_tick = delivery.send_tick,
        sequence = delivery.sequence,
        duplicate_ordinal = delivery.duplicate_ordinal,
        arrival_tick = delivery.arrival_tick,
        current = copy_record(delivery.current),
        history = copy_records(delivery.history),
    }
end

---@param profile NetworkProfile
---@return NetworkProfile
local function copy_profile(profile)
    return {
        base_delay_ticks = profile.base_delay_ticks,
        jitter_min_ticks = profile.jitter_min_ticks,
        jitter_max_ticks = profile.jitter_max_ticks,
        independent_loss_rate = profile.independent_loss_rate,
        duplication_rate = profile.duplication_rate,
        burst_start_rate = profile.burst_start_rate,
        burst_length_ticks = profile.burst_length_ticks,
    }
end

---@param profile NetworkProfile
local function assert_profile(profile)
    assert(type(profile) == "table", "network profile is required")
    assert(
        is_integer(profile.base_delay_ticks) and profile.base_delay_ticks >= 0,
        "network base delay must be a non-negative integer"
    )
    assert(
        is_integer(profile.jitter_min_ticks) and is_integer(profile.jitter_max_ticks),
        "network jitter bounds must be integers"
    )
    assert(
        profile.jitter_min_ticks <= profile.jitter_max_ticks,
        "network jitter bounds are reversed"
    )
    assert(is_rate(profile.independent_loss_rate), "network loss rate must be in [0, 1]")
    assert(is_rate(profile.duplication_rate), "network duplication rate must be in [0, 1]")
    assert(is_rate(profile.burst_start_rate), "network burst rate must be in [0, 1]")
    assert(
        is_integer(profile.burst_length_ticks) and profile.burst_length_ticks >= 0,
        "network burst length must be a non-negative integer"
    )
    assert(
        (profile.burst_start_rate == 0 and profile.burst_length_ticks == 0)
            or (profile.burst_start_rate > 0 and profile.burst_length_ticks > 0),
        "network burst rate and length must both be disabled or enabled"
    )
end

---@param conditions NetworkConditions
local function assert_conditions(conditions)
    assert(type(conditions) == "table", "network conditions state is required")
    assert(type(conditions._pending) == "table", "network pending queue is missing")
    assert(type(conditions._records) == "table", "network authoritative history is missing")
    assert(type(conditions._counters) == "table", "network counters are missing")
end

---@param tick any
---@return boolean
local function is_bounded_tick(tick)
    return is_integer(tick) and tick >= 0 and tick <= input_frame.MAX_TICK
end

---@param source_slot any
---@return boolean
local function is_source_slot(source_slot)
    return is_integer(source_slot) and source_slot >= 1 and source_slot <= input_frame.SLOT_COUNT
end

---@param state integer
---@return integer new_state
---@return number jitter_roll
---@return number loss_roll
---@return number duplicate_roll
---@return number burst_roll
local function impairment_rolls(state)
    local jitter_roll, loss_roll, duplicate_roll, burst_roll
    state, jitter_roll = rng.roll(state)
    state, loss_roll = rng.roll(state)
    state, duplicate_roll = rng.roll(state)
    state, burst_roll = rng.roll(state)
    return state, jitter_roll, loss_roll, duplicate_roll, burst_roll
end

---@param profile NetworkProfile
---@param roll number
---@return integer
local function jitter_from_roll(profile, roll)
    local width = profile.jitter_max_ticks - profile.jitter_min_ticks + 1
    return profile.jitter_min_ticks + math.floor(roll * width)
end

---@param records NetworkInputRecord[]
---@param input_tick integer
---@return integer?
local function find_record_index(records, input_tick)
    for index, record in ipairs(records) do
        if record.tick == input_tick then
            return index
        end
    end
    return nil
end

---@param conditions NetworkConditions
---@param source_slot integer
---@param input_tick integer
---@return NetworkInputRecord?
local function find_record(conditions, source_slot, input_tick)
    local records = conditions._records[source_slot]
    if records == nil then
        return nil
    end
    local index = find_record_index(records, input_tick)
    return index and records[index] or nil
end

---@param conditions NetworkConditions
---@param source_slot integer
---@param input_tick integer
---@param sample InputSample
---@return boolean? duplicate
---@return string? error_message
---@return NetworkConditionErrorCode? error_code
local function retain_authoritative(conditions, source_slot, input_tick, sample)
    local records = conditions._records[source_slot]
    if records == nil then
        records = {}
        conditions._records[source_slot] = records
    end

    local existing_index = find_record_index(records, input_tick)
    if existing_index ~= nil then
        if not samples_equal(records[existing_index].sample, sample) then
            return failure(
                "conflicting_authoritative",
                ("network input conflicts at tick %d slot %d"):format(input_tick, source_slot)
            )
        end
        return true
    end

    local latest = records[#records]
    if latest ~= nil and input_tick < latest.tick then
        return failure(
            "stale_authoritative",
            ("network input tick %d precedes retained slot %d authority"):format(
                input_tick,
                source_slot
            )
        )
    end

    records[#records + 1] = { tick = input_tick, sample = copy_sample(sample) }
    if #records > network_conditions.RETAINED_RECORDS then
        table.remove(records, 1)
    end
    return false
end

---@param conditions NetworkConditions
---@param source_slot integer
---@param input_tick integer
---@return NetworkInputRecord[]
local function packet_history(conditions, source_slot, input_tick)
    local records = assert(conditions._records[source_slot])
    local current_index = assert(find_record_index(records, input_tick))
    local history = {}
    local first = math.max(1, current_index - network_conditions.HISTORY_RECORDS)
    for index = first, current_index - 1 do
        history[#history + 1] = copy_record(records[index])
    end
    return history
end

---@param conditions NetworkConditions
---@param source_slot integer
---@param send_tick integer
---@param input_tick integer
---@param authoritative_duplicate boolean
---@return NetworkSendReceipt
local function schedule_packet(
    conditions,
    source_slot,
    send_tick,
    input_tick,
    authoritative_duplicate
)
    conditions._sequence = conditions._sequence + 1
    conditions._counters.sent = conditions._counters.sent + 1

    local jitter_roll, loss_roll, duplicate_roll, burst_roll
    conditions._rng, jitter_roll, loss_roll, duplicate_roll, burst_roll =
        impairment_rolls(conditions._rng)

    local profile = conditions._profile
    local active_burst = send_tick <= (conditions._burst_until[source_slot] or -1)
    local started_burst = false
    if not active_burst and burst_roll < profile.burst_start_rate then
        started_burst = true
        conditions._burst_until[source_slot] = send_tick + profile.burst_length_ticks - 1
    end

    local sequence = conditions._sequence
    if active_burst or started_burst then
        conditions._counters.burst_lost = conditions._counters.burst_lost + 1
        return {
            sequence = sequence,
            dropped = true,
            drop_reason = "burst_loss",
            arrival_tick = nil,
            duplicated = false,
            authoritative_duplicate = authoritative_duplicate,
        }
    end
    if loss_roll < profile.independent_loss_rate then
        conditions._counters.independent_lost = conditions._counters.independent_lost + 1
        return {
            sequence = sequence,
            dropped = true,
            drop_reason = "independent_loss",
            arrival_tick = nil,
            duplicated = false,
            authoritative_duplicate = authoritative_duplicate,
        }
    end

    local jitter = jitter_from_roll(profile, jitter_roll)
    local arrival_tick = math.max(send_tick, send_tick + profile.base_delay_ticks + jitter)
    local current = assert(find_record(conditions, source_slot, input_tick))
    ---@type NetworkDelivery
    local delivery = {
        source_slot = source_slot,
        send_tick = send_tick,
        sequence = sequence,
        duplicate_ordinal = 0,
        arrival_tick = arrival_tick,
        current = copy_record(current),
        history = packet_history(conditions, source_slot, input_tick),
    }
    conditions._pending[#conditions._pending + 1] = delivery

    local duplicated = duplicate_roll < profile.duplication_rate
    if duplicated then
        local duplicate = copy_delivery(delivery)
        duplicate.duplicate_ordinal = 1
        conditions._pending[#conditions._pending + 1] = duplicate
        conditions._counters.duplicated = conditions._counters.duplicated + 1
    end

    return {
        sequence = sequence,
        dropped = false,
        drop_reason = nil,
        arrival_tick = arrival_tick,
        duplicated = duplicated,
        authoritative_duplicate = authoritative_duplicate,
    }
end

---@param conditions NetworkConditions
---@param send_tick any
---@param source_slot any
---@param input_tick any
---@param sample any
---@return boolean?, string?, NetworkConditionErrorCode?
local function validate_send(conditions, send_tick, source_slot, input_tick, sample)
    if not is_bounded_tick(send_tick) or send_tick < conditions._clock_tick then
        return failure("malformed", "network send tick must be bounded and monotonic")
    end
    if not is_source_slot(source_slot) then
        return failure("malformed", "network source slot must be between one and eight")
    end
    if not is_bounded_tick(input_tick) then
        return failure("malformed", "network input tick must be a bounded non-negative integer")
    end
    local ok, err = input_frame.validate_sample(sample)
    if not ok then
        return failure("malformed", err or "network input sample is malformed")
    end
    return true
end

---@param profile NetworkProfile
---@param seed number
---@return NetworkConditions
function network_conditions.new(profile, seed)
    assert_profile(profile)
    assert(
        type(seed) == "number" and seed == seed and seed ~= math.huge and seed ~= -math.huge,
        "network seed must be finite"
    )
    return {
        _profile = copy_profile(profile),
        _rng = rng.seed(seed),
        _sequence = 0,
        _clock_tick = -1,
        _records = {},
        _pending = {},
        _burst_until = {},
        _delivered_samples = {},
        _max_delivered_sequence = 0,
        _reordered_sequences = {},
        _counters = {
            sent = 0,
            delivered = 0,
            independent_lost = 0,
            burst_lost = 0,
            duplicated = 0,
            reordered = 0,
            history_recovered = 0,
        },
    }
end

-- Retain a new authoritative sample (or accept its identical duplicate), then
-- schedule one source packet. Every call consumes jitter, independent-loss,
-- duplication, and burst-start rolls in that order, including dropped packets.
---@param conditions NetworkConditions
---@param send_tick integer
---@param source_slot integer
---@param input_tick integer
---@param sample InputSample
---@return NetworkSendReceipt?, string?, NetworkConditionErrorCode?
function network_conditions.send(conditions, send_tick, source_slot, input_tick, sample)
    assert_conditions(conditions)
    local ok, err, code = validate_send(conditions, send_tick, source_slot, input_tick, sample)
    if not ok then
        return nil, err, code
    end
    local duplicate, retain_err, retain_code =
        retain_authoritative(conditions, source_slot, input_tick, sample)
    if duplicate == nil then
        return nil, retain_err, retain_code
    end
    conditions._clock_tick = send_tick
    return schedule_packet(conditions, source_slot, send_tick, input_tick, duplicate)
end

-- Schedule an already-retained sample without adding another input-history row.
---@param conditions NetworkConditions
---@param send_tick integer
---@param source_slot integer
---@param input_tick integer
---@return NetworkSendReceipt?, string?, NetworkConditionErrorCode?
function network_conditions.resend(conditions, send_tick, source_slot, input_tick)
    assert_conditions(conditions)
    if not is_bounded_tick(send_tick) or send_tick < conditions._clock_tick then
        return failure("malformed", "network resend tick must be bounded and monotonic")
    end
    if not is_source_slot(source_slot) or not is_bounded_tick(input_tick) then
        return failure("malformed", "network resend slot and input tick are invalid")
    end
    if find_record(conditions, source_slot, input_tick) == nil then
        return failure("not_retained", "network resend input is outside retained history")
    end
    conditions._clock_tick = send_tick
    return schedule_packet(conditions, source_slot, send_tick, input_tick, true)
end

---@param conditions NetworkConditions
---@param delivery NetworkDelivery
local function record_delivery(conditions, delivery)
    conditions._counters.delivered = conditions._counters.delivered + 1
    if
        delivery.sequence < conditions._max_delivered_sequence
        and not conditions._reordered_sequences[delivery.sequence]
    then
        conditions._reordered_sequences[delivery.sequence] = true
        conditions._counters.reordered = conditions._counters.reordered + 1
    end
    conditions._max_delivered_sequence =
        math.max(conditions._max_delivered_sequence, delivery.sequence)

    local delivered = conditions._delivered_samples[delivery.source_slot]
    if delivered == nil then
        delivered = {}
        conditions._delivered_samples[delivery.source_slot] = delivered
    end
    for _, record in ipairs(delivery.history) do
        local existing = delivered[record.tick]
        assert(
            existing == nil or samples_equal(existing, record.sample),
            "network history delivered conflicting authority"
        )
        if existing == nil then
            delivered[record.tick] = copy_sample(record.sample)
            conditions._counters.history_recovered = conditions._counters.history_recovered + 1
        end
    end
    local existing = delivered[delivery.current.tick]
    assert(
        existing == nil or samples_equal(existing, delivery.current.sample),
        "network current delivery conflicts with prior authority"
    )
    if existing == nil then
        delivered[delivery.current.tick] = copy_sample(delivery.current.sample)
    end
end

---@param left NetworkDelivery
---@param right NetworkDelivery
---@return boolean
local function delivery_less(left, right)
    if left.arrival_tick ~= right.arrival_tick then
        return left.arrival_tick < right.arrival_tick
    end
    if left.sequence ~= right.sequence then
        return left.sequence < right.sequence
    end
    return left.duplicate_ordinal < right.duplicate_ordinal
end

-- Return every envelope due at or before the monotonic transport tick. Equal
-- arrivals use (arrival_tick, sequence, duplicate_ordinal) ordering.
---@param conditions NetworkConditions
---@param delivery_tick integer
---@return NetworkDelivery[]
function network_conditions.poll(conditions, delivery_tick)
    assert_conditions(conditions)
    assert(
        is_bounded_tick(delivery_tick) and delivery_tick >= conditions._clock_tick,
        "network poll tick must be bounded and monotonic"
    )
    conditions._clock_tick = delivery_tick

    local due = {}
    local pending = {}
    for _, delivery in ipairs(conditions._pending) do
        if delivery.arrival_tick <= delivery_tick then
            due[#due + 1] = delivery
        else
            pending[#pending + 1] = delivery
        end
    end
    conditions._pending = pending
    table.sort(due, delivery_less)

    local result = {}
    for index, delivery in ipairs(due) do
        record_delivery(conditions, delivery)
        result[index] = copy_delivery(delivery)
    end
    return result
end

---@param conditions NetworkConditions
---@return integer
function network_conditions.pending(conditions)
    assert_conditions(conditions)
    return #conditions._pending
end

---@param conditions NetworkConditions
---@return NetworkConditionCounters
function network_conditions.counters(conditions)
    assert_conditions(conditions)
    local counters = conditions._counters
    return {
        sent = counters.sent,
        delivered = counters.delivered,
        independent_lost = counters.independent_lost,
        burst_lost = counters.burst_lost,
        duplicated = counters.duplicated,
        reordered = counters.reordered,
        history_recovered = counters.history_recovered,
    }
end

-- Return a delivery's redundant rows followed by its current row. The result
-- is copied and can be passed in order to rollback_input_history.add_authoritative.
---@param delivery NetworkDelivery
---@return NetworkInputRecord[]
function network_conditions.records(delivery)
    local records = copy_records(delivery.history)
    records[#records + 1] = copy_record(delivery.current)
    return records
end

---@param conditions NetworkConditions
---@param request NetworkResendRequest
---@return boolean
local function request_delivered(conditions, request)
    local delivered = conditions._delivered_samples[request.source_slot]
    return delivered ~= nil and delivered[request.input_tick] ~= nil
end

---@param conditions NetworkConditions
---@param requests NetworkResendRequest[]
---@return boolean
local function requests_complete(conditions, requests)
    for _, request in ipairs(requests) do
        if not request_delivered(conditions, request) then
            return false
        end
    end
    return true
end

---@param requests NetworkResendRequest[]
---@return NetworkResendRequest[]?, string?, NetworkConditionErrorCode?
local function validated_requests(requests)
    if type(requests) ~= "table" then
        return failure("malformed", "network drain requests must be a table")
    end
    local copied = {}
    local seen = {}
    for _, request in ipairs(requests) do
        if
            type(request) ~= "table"
            or not is_source_slot(request.source_slot)
            or not is_bounded_tick(request.input_tick)
        then
            return failure("malformed", "network drain request is invalid")
        end
        local identity = request.source_slot .. ":" .. request.input_tick
        if seen[identity] then
            return failure("malformed", "network drain requests must be unique")
        end
        seen[identity] = true
        copied[#copied + 1] = {
            source_slot = request.source_slot,
            input_tick = request.input_tick,
        }
    end
    table.sort(copied, function(left, right)
        if left.source_slot ~= right.source_slot then
            return left.source_slot < right.source_slot
        end
        return left.input_tick < right.input_tick
    end)
    return copied
end

-- Advance only transport ticks. Missing requested samples are resent once per
-- transport tick until observed; after recovery, pending redundant packets are
-- polled without further sends. Match simulation never advances here.
---@param conditions NetworkConditions
---@param start_tick integer
---@param max_ticks integer
---@param requests NetworkResendRequest[]
---@return NetworkDrainResult?, string?, NetworkConditionErrorCode?
function network_conditions.drain(conditions, start_tick, max_ticks, requests)
    assert_conditions(conditions)
    if
        not is_bounded_tick(start_tick)
        or start_tick < conditions._clock_tick
        or not is_integer(max_ticks)
        or max_ticks < 1
        or start_tick + max_ticks - 1 > input_frame.MAX_TICK
    then
        return failure("malformed", "network drain tick range must be bounded and monotonic")
    end
    local sorted, err, code = validated_requests(requests)
    if sorted == nil then
        return nil, err, code
    end
    for _, request in ipairs(sorted) do
        if find_record(conditions, request.source_slot, request.input_tick) == nil then
            return failure("not_retained", "network drain request is outside retained history")
        end
    end

    local deliveries = {}
    local final_tick = start_tick
    for offset = 0, max_ticks - 1 do
        final_tick = start_tick + offset
        local before = network_conditions.poll(conditions, final_tick)
        for _, delivery in ipairs(before) do
            deliveries[#deliveries + 1] = delivery
        end

        if not requests_complete(conditions, sorted) then
            for _, request in ipairs(sorted) do
                if not request_delivered(conditions, request) then
                    assert(
                        network_conditions.resend(
                            conditions,
                            final_tick,
                            request.source_slot,
                            request.input_tick
                        )
                    )
                end
            end
            local immediate = network_conditions.poll(conditions, final_tick)
            for _, delivery in ipairs(immediate) do
                deliveries[#deliveries + 1] = delivery
            end
        end

        if
            requests_complete(conditions, sorted)
            and network_conditions.pending(conditions) == 0
        then
            break
        end
    end

    local recovered = 0
    for _, request in ipairs(sorted) do
        if request_delivered(conditions, request) then
            recovered = recovered + 1
        end
    end
    return {
        deliveries = deliveries,
        final_tick = final_tick,
        complete = recovered == #sorted and network_conditions.pending(conditions) == 0,
        pending = network_conditions.pending(conditions),
        recovered = recovered,
        requested = #sorted,
    }
end

return network_conditions
