local t = require("spec.support.runner")
local match = require("sim.match")
local match_snapshot = require("sim.match_snapshot")
local rollback_snapshot_history = require("sim.rollback_snapshot_history")
local teams = require("data.teams")

---@return MatchState
local function new_state()
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        duration = 2,
        max_goals = 3,
        seed = 69,
        input_ownership = match.ownership_for_teams(teams.nebula, teams.orion),
    })
end

---@param state MatchState
---@param tick integer
---@return MatchSnapshot
local function boundary(state, tick)
    state.input_tick = tick
    return match_snapshot.capture(state)
end

t.describe("bounded rollback snapshot history", function()
    t.it("retains the present boundary plus exactly thirty prior boundaries", function()
        local history = rollback_snapshot_history.new()
        local state = new_state()
        for tick = 0, 31 do
            assert(rollback_snapshot_history.store(history, boundary(state, tick)))
        end

        local diagnostics = rollback_snapshot_history.diagnostics(history)
        t.eq(diagnostics.max_rollback_ticks, 30)
        t.eq(diagnostics.capacity, 31)
        t.eq(diagnostics.retained_boundary_count, 31)
        t.eq(diagnostics.oldest_supported_tick, 1)
        t.eq(diagnostics.oldest_boundary_tick, 1)
        t.eq(diagnostics.latest_tick, 31)
        t.eq(rollback_snapshot_history.lookup(history, 31).status, "present")
        t.eq(rollback_snapshot_history.lookup(history, 1).status, "retained")
        t.eq(rollback_snapshot_history.lookup(history, 0).status, "outside_window")
    end)

    t.it("distinguishes missing boundaries inside the ring's supported range", function()
        local history = rollback_snapshot_history.new(3)
        local state = new_state()
        assert(rollback_snapshot_history.store(history, boundary(state, 10)))
        assert(rollback_snapshot_history.store(history, boundary(state, 12)))

        t.eq(rollback_snapshot_history.lookup(history, 12).status, "present")
        t.eq(rollback_snapshot_history.lookup(history, 10).status, "retained")
        t.eq(rollback_snapshot_history.lookup(history, 11).status, "missing")
        t.eq(rollback_snapshot_history.lookup(history, 8).status, "outside_window")
        local rejected, _, code = rollback_snapshot_history.store(history, boundary(state, 8))
        t.eq(rejected, nil)
        t.eq(code, "outside_window")
    end)

    t.it("owns independent stored and returned snapshots", function()
        local history = rollback_snapshot_history.new()
        local state = new_state()
        local supplied = boundary(state, 0)
        local original_x = supplied.state.players[1].pos.x
        assert(rollback_snapshot_history.store(history, supplied))
        supplied.state.players[1].pos.x = original_x + 100

        local first = assert(rollback_snapshot_history.lookup(history, 0).snapshot)
        t.eq(first.state.players[1].pos.x, original_x)
        first.state.players[1].pos.x = original_x - 100
        local second = assert(rollback_snapshot_history.lookup(history, 0).snapshot)
        t.eq(second.state.players[1].pos.x, original_x)
    end)

    t.it("updates byte accounting and invalidates a replaced boundary's lazy hash", function()
        local history = rollback_snapshot_history.new(1)
        local state = new_state()
        local initial = boundary(state, 0)
        local initial_bytes = #match_snapshot.encode(initial)
        local first = assert(rollback_snapshot_history.store(history, initial))
        t.eq(first.replaced, false)
        t.eq(rollback_snapshot_history.diagnostics(history).canonical_bytes, initial_bytes)
        local first_hash = assert(rollback_snapshot_history.boundary_hash(history, 0))

        state.score.home = 1
        local replacement = boundary(state, 0)
        local replacement_bytes = #match_snapshot.encode(replacement)
        local replaced = assert(rollback_snapshot_history.store(history, replacement))
        t.eq(replaced.replaced, true)
        local diagnostics = rollback_snapshot_history.diagnostics(history)
        t.eq(diagnostics.retained_boundary_count, 1)
        t.eq(diagnostics.canonical_bytes, replacement_bytes)
        local replacement_hash = assert(rollback_snapshot_history.boundary_hash(history, 0))
        t.is_true(replacement_hash ~= first_hash)

        local next_boundary = boundary(state, 1)
        local next_bytes = #match_snapshot.encode(next_boundary)
        assert(rollback_snapshot_history.store(history, next_boundary))
        t.eq(
            rollback_snapshot_history.diagnostics(history).canonical_bytes,
            replacement_bytes + next_bytes
        )
        local third_boundary = boundary(state, 2)
        local third_bytes = #match_snapshot.encode(third_boundary)
        local advanced = assert(rollback_snapshot_history.store(history, third_boundary))
        t.eq(advanced.evicted, 1)
        t.eq(
            rollback_snapshot_history.diagnostics(history).canonical_bytes,
            next_bytes + third_bytes
        )
        t.eq(rollback_snapshot_history.lookup(history, 0).status, "outside_window")
    end)

    t.it("evicts deterministically across wraparound and sparse advances", function()
        local left = rollback_snapshot_history.new(3)
        local right = rollback_snapshot_history.new(3)
        local state = new_state()
        for _, tick in ipairs({ 0, 1, 4, 6, 7 }) do
            assert(rollback_snapshot_history.store(left, boundary(state, tick)))
            assert(rollback_snapshot_history.store(right, boundary(state, tick)))
        end
        local left_diagnostics = rollback_snapshot_history.diagnostics(left)
        local right_diagnostics = rollback_snapshot_history.diagnostics(right)
        t.eq(left_diagnostics.retained_boundary_count, right_diagnostics.retained_boundary_count)
        t.eq(left_diagnostics.canonical_bytes, right_diagnostics.canonical_bytes)
        for tick = 0, 7 do
            local left_lookup = rollback_snapshot_history.lookup(left, tick)
            local right_lookup = rollback_snapshot_history.lookup(right, tick)
            t.eq(left_lookup.status, right_lookup.status)
            if left_lookup.snapshot then
                t.eq(
                    assert(rollback_snapshot_history.boundary_hash(left, tick)),
                    assert(rollback_snapshot_history.boundary_hash(right, tick))
                )
            end
        end
    end)

    t.it("retains the final full-time boundary without inventing another input", function()
        local history = rollback_snapshot_history.new()
        local state = new_state()
        assert(rollback_snapshot_history.store(history, boundary(state, 6)))
        state.finished = true
        assert(rollback_snapshot_history.store(history, boundary(state, 7)))

        local final = rollback_snapshot_history.lookup(history, 7)
        t.eq(final.status, "present")
        t.is_true(assert(final.snapshot).state.finished)
        t.eq(rollback_snapshot_history.lookup(history, 8).status, "missing")
        t.eq(rollback_snapshot_history.diagnostics(history).latest_tick, 7)
    end)
end)
