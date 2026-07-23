-- Bounded start-of-tick snapshot storage for rollback sessions. Boundaries are
-- indexed by the InputFrame tick they will consume; the ring owns independent
-- canonical snapshots and has no simulation, transport, or presentation role.

local input_frame = require("sim.input_frame")
local match_snapshot = require("sim.match_snapshot")
local rollback_input_history = require("sim.rollback_input_history")

---@alias RollbackSnapshotLookupStatus "present"|"retained"|"missing"|"outside_window"
---@alias RollbackSnapshotHistoryErrorCode "malformed"|"outside_window"|"missing"

---@class RollbackSnapshotEntry
---@field tick integer
---@field snapshot MatchSnapshot
---@field canonical_bytes integer
---@field hash string?

---@class RollbackSnapshotHistory
---@field _max_rollback_ticks integer
---@field _capacity integer
---@field _entries table<integer, RollbackSnapshotEntry>
---@field _latest_tick integer?
---@field _oldest_supported_tick integer?
---@field _count integer
---@field _canonical_bytes integer

---@class RollbackSnapshotLookup
---@field status RollbackSnapshotLookupStatus
---@field tick integer
---@field snapshot MatchSnapshot?
---@field canonical_bytes integer?

---@class RollbackSnapshotStoreResult
---@field tick integer
---@field replaced boolean
---@field evicted integer

---@class RollbackSnapshotTruncateResult
---@field boundary_tick integer
---@field removed integer
---@field diagnostics RollbackSnapshotHistoryDiagnostics

---@class RollbackSnapshotHistoryDiagnostics
---@field max_rollback_ticks integer
---@field capacity integer
---@field retained_boundary_count integer
---@field canonical_bytes integer
---@field oldest_supported_tick integer?
---@field oldest_boundary_tick integer?
---@field latest_tick integer?

---@class RollbackSnapshotHistoryModule
local rollback_snapshot_history = {}

rollback_snapshot_history.DEFAULT_MAX_ROLLBACK_TICKS = rollback_input_history.ROLLBACK_WINDOW_TICKS

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
end

---@param history RollbackSnapshotHistory
local function assert_history(history)
    assert(type(history) == "table", "rollback snapshot history is required")
    assert(type(history._entries) == "table", "rollback snapshot ring is missing")
    assert(
        is_integer(history._capacity) and history._capacity >= 1,
        "rollback snapshot capacity is invalid"
    )
end

---@param snapshot MatchSnapshot
---@return MatchSnapshot
local function copy_snapshot(snapshot)
    return match_snapshot.capture(match_snapshot.restore(snapshot))
end

---@param history RollbackSnapshotHistory
---@param tick integer
---@return integer
local function ring_index(history, tick)
    return (tick % history._capacity) + 1
end

---@param history RollbackSnapshotHistory
---@return integer?
local function oldest_supported_tick(history)
    return history._oldest_supported_tick
end

---@param history RollbackSnapshotHistory
---@param entry RollbackSnapshotEntry
local function remove_entry(history, entry)
    history._entries[ring_index(history, entry.tick)] = nil
    history._count = history._count - 1
    history._canonical_bytes = history._canonical_bytes - entry.canonical_bytes
end

---@param max_rollback_ticks integer? Maximum prior input ticks that remain restorable.
---@return RollbackSnapshotHistory
function rollback_snapshot_history.new(max_rollback_ticks)
    max_rollback_ticks = max_rollback_ticks or rollback_snapshot_history.DEFAULT_MAX_ROLLBACK_TICKS
    assert(
        is_integer(max_rollback_ticks)
            and max_rollback_ticks >= 0
            and max_rollback_ticks <= input_frame.MAX_TICK,
        "maximum rollback ticks must be a bounded non-negative integer"
    )
    return {
        _max_rollback_ticks = max_rollback_ticks,
        _capacity = max_rollback_ticks + 1,
        _entries = {},
        _latest_tick = nil,
        _oldest_supported_tick = nil,
        _count = 0,
        _canonical_bytes = 0,
    }
end

-- Store or replace one canonical start-of-tick boundary. Advancing the latest
-- boundary evicts every entry older than the supported correction window.
---@param history RollbackSnapshotHistory
---@param snapshot MatchSnapshot
---@return RollbackSnapshotStoreResult?, string?, RollbackSnapshotHistoryErrorCode?
function rollback_snapshot_history.store(history, snapshot)
    assert_history(history)
    local retained = copy_snapshot(snapshot)
    local tick = retained.state.input_tick
    assert(
        is_integer(tick) and tick >= 0 and tick <= input_frame.MAX_TICK,
        "snapshot input tick must be a bounded non-negative integer"
    )

    local supported = oldest_supported_tick(history)
    if supported ~= nil and tick < supported then
        return nil,
            ("snapshot boundary %d is older than retained boundary %d"):format(tick, supported),
            "outside_window"
    end

    if history._latest_tick == nil or tick > history._latest_tick then
        history._latest_tick = tick
        local next_supported = math.max(0, tick - history._max_rollback_ticks)
        if
            history._oldest_supported_tick == nil
            or next_supported > history._oldest_supported_tick
        then
            history._oldest_supported_tick = next_supported
        end
    end
    supported = assert(oldest_supported_tick(history))
    local evicted = 0
    for _, entry in pairs(history._entries) do
        if entry and entry.tick < supported then
            remove_entry(history, entry)
            evicted = evicted + 1
        end
    end

    local index = ring_index(history, tick)
    local existing = history._entries[index]
    local replaced = existing ~= nil and existing.tick == tick
    if existing then
        remove_entry(history, existing)
    end
    local canonical_bytes = #match_snapshot.encode(retained)
    history._entries[index] = {
        tick = tick,
        snapshot = retained,
        canonical_bytes = canonical_bytes,
        hash = nil,
    }
    history._count = history._count + 1
    history._canonical_bytes = history._canonical_bytes + canonical_bytes
    return { tick = tick, replaced = replaced, evicted = evicted }
end

---@param history RollbackSnapshotHistory
---@param tick integer
---@return RollbackSnapshotLookupStatus
local function lookup_status(history, tick)
    local supported = oldest_supported_tick(history)
    if supported ~= nil and tick < supported then
        return "outside_window"
    end
    local entry = history._entries[ring_index(history, tick)]
    if entry == nil or entry.tick ~= tick then
        return "missing"
    end
    return tick == history._latest_tick and "present" or "retained"
end

-- Keep the named start-of-tick boundary and discard only later snapshots from
-- an obsolete predicted timeline. The historical floor never moves backward:
-- already-evicted boundaries cannot become supported merely because the
-- corrected timeline finished earlier.
---@param history RollbackSnapshotHistory
---@param boundary_tick integer
---@return RollbackSnapshotTruncateResult?, string?, RollbackSnapshotHistoryErrorCode?
function rollback_snapshot_history.truncate_after(history, boundary_tick)
    assert_history(history)
    if
        not is_integer(boundary_tick)
        or boundary_tick < 0
        or boundary_tick > input_frame.MAX_TICK
    then
        return nil,
            "rollback snapshot truncate tick must be a bounded non-negative integer",
            "malformed"
    end
    local status = lookup_status(history, boundary_tick)
    if status == "outside_window" then
        return nil,
            ("snapshot boundary %d is older than retained boundary %d"):format(
                boundary_tick,
                assert(oldest_supported_tick(history))
            ),
            "outside_window"
    end
    if status == "missing" then
        return nil,
            ("snapshot boundary %d is missing from retained history"):format(boundary_tick),
            "missing"
    end

    local removed = 0
    for _, entry in pairs(history._entries) do
        if entry.tick > boundary_tick then
            remove_entry(history, entry)
            removed = removed + 1
        end
    end
    history._latest_tick = boundary_tick
    return {
        boundary_tick = boundary_tick,
        removed = removed,
        diagnostics = rollback_snapshot_history.diagnostics(history),
    }
end

---@param history RollbackSnapshotHistory
---@param tick integer
---@return RollbackSnapshotLookup
function rollback_snapshot_history.lookup(history, tick)
    assert_history(history)
    assert(
        is_integer(tick) and tick >= 0 and tick <= input_frame.MAX_TICK,
        "rollback snapshot lookup tick must be a bounded non-negative integer"
    )
    local status = lookup_status(history, tick)
    if status == "missing" or status == "outside_window" then
        return { status = status, tick = tick }
    end
    local entry = assert(history._entries[ring_index(history, tick)])
    assert(entry.tick == tick, "rollback snapshot ring lookup is inconsistent")
    return {
        status = status,
        tick = tick,
        snapshot = copy_snapshot(entry.snapshot),
        canonical_bytes = entry.canonical_bytes,
    }
end

-- Hashing is diagnostic and deliberately lazy: ordinary retention does not
-- pay a second canonical encoding. Replacement creates a fresh unhashed entry.
---@param history RollbackSnapshotHistory
---@param tick integer
---@return string?, RollbackSnapshotLookupStatus
function rollback_snapshot_history.boundary_hash(history, tick)
    assert_history(history)
    assert(
        is_integer(tick) and tick >= 0 and tick <= input_frame.MAX_TICK,
        "rollback snapshot hash tick must be a bounded non-negative integer"
    )
    local status = lookup_status(history, tick)
    if status == "missing" or status == "outside_window" then
        return nil, status
    end
    local entry = assert(history._entries[ring_index(history, tick)])
    if entry.hash == nil then
        entry.hash = match_snapshot.hash(entry.snapshot)
    end
    return entry.hash, status
end

---@param history RollbackSnapshotHistory
---@return RollbackSnapshotHistoryDiagnostics
function rollback_snapshot_history.diagnostics(history)
    assert_history(history)
    local oldest = nil
    for _, entry in pairs(history._entries) do
        if entry and (oldest == nil or entry.tick < oldest) then
            oldest = entry.tick
        end
    end
    return {
        max_rollback_ticks = history._max_rollback_ticks,
        capacity = history._capacity,
        retained_boundary_count = history._count,
        canonical_bytes = history._canonical_bytes,
        oldest_supported_tick = oldest_supported_tick(history),
        oldest_boundary_tick = oldest,
        latest_tick = history._latest_tick,
    }
end

return rollback_snapshot_history
