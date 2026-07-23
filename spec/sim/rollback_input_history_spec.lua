local t = require("spec.support.runner")
local input_frame = require("sim.input_frame")
local rollback_input_history = require("sim.rollback_input_history")

---@param local_slot integer?
---@return RollbackInputSource[]
local function sources(local_slot)
    local result = {}
    for index = 1, input_frame.SLOT_COUNT do
        result[index] = index == local_slot and "local" or "remote"
    end
    return result
end

---@param move_x integer?
---@param move_y integer?
---@param held integer?
---@param edges integer?
---@return InputSample
local function sample(move_x, move_y, held, edges)
    return assert(input_frame.new_sample({
        move_x = move_x,
        move_y = move_y,
        held = held,
        edges = edges,
    }))
end

---@param history RollbackInputHistory
---@param tick integer
---@param value InputSample?
local function add_full_tick(history, tick, value)
    for index = 1, input_frame.SLOT_COUNT do
        assert(
            rollback_input_history.add_authoritative(
                history,
                tick,
                index,
                value or input_frame.neutral_sample()
            )
        )
    end
end

t.describe("OMP-2 rollback input history", function()
    t.it("uses neutral first-sample prediction and preserves local/remote status", function()
        local declared_sources = sources(1)
        local history = rollback_input_history.new(declared_sources)
        declared_sources[1] = "remote"

        t.eq(rollback_input_history.source(history, 1), "local")
        t.eq(rollback_input_history.confirmed_tick(history), -1)
        t.is_true(
            not pcall(rollback_input_history.materialize, history, 0),
            "a missing local sample is a producer invariant failure"
        )

        assert(
            rollback_input_history.add_authoritative(
                history,
                0,
                1,
                sample(20, -30, input_frame.HELD_BITS.sprint, input_frame.EDGE_BITS.dash)
            )
        )
        assert(
            rollback_input_history.add_authoritative(
                history,
                0,
                2,
                sample(-10, 40, input_frame.HELD_BITS.jockey, input_frame.EDGE_BITS.dodge)
            )
        )
        local frame, record = rollback_input_history.materialize(history, 0)
        t.eq(frame.slots[1].move_x, 20)
        t.eq(record.slots[1].source, "local")
        t.eq(record.slots[1].status, "authoritative")
        t.eq(record.slots[2].source, "remote")
        t.eq(record.slots[2].status, "authoritative")
        t.eq(record.slots[3].status, "predicted")
        t.eq(frame.slots[3].move_x, 0)
        t.eq(frame.slots[3].move_y, 0)
        t.eq(frame.slots[3].held, 0)
        t.eq(frame.slots[3].edges, 0)
    end)

    t.it("repeats only axes and held bits from the latest prior authority", function()
        local history = rollback_input_history.new(sources())
        local authoritative = sample(
            -64,
            90,
            input_frame.HELD_BITS.shoot + input_frame.HELD_BITS.lob,
            input_frame.EDGE_BITS.shoot + input_frame.EDGE_BITS.dash
        )
        assert(rollback_input_history.add_authoritative(history, 5, 1, authoritative))

        local before, before_record = rollback_input_history.materialize(history, 4)
        t.eq(before.slots[1].move_x, 0, "future authority cannot predict backward")
        t.eq(before_record.slots[1].status, "predicted")

        local at_tick, at_record = rollback_input_history.materialize(history, 5)
        t.eq(at_tick.slots[1].edges, authoritative.edges)
        t.eq(at_record.slots[1].status, "authoritative")

        local predicted, predicted_record = rollback_input_history.materialize(history, 6)
        t.eq(predicted.slots[1].move_x, authoritative.move_x)
        t.eq(predicted.slots[1].move_y, authoritative.move_y)
        t.eq(predicted.slots[1].held, authoritative.held)
        t.eq(predicted.slots[1].edges, 0, "edge bits never repeat")
        t.eq(predicted_record.slots[1].status, "predicted")
    end)

    t.it("reports divergence only against an effective sample already used", function()
        local history = rollback_input_history.new(sources())
        rollback_input_history.materialize(history, 2)
        rollback_input_history.materialize(history, 5)

        local same = assert(
            rollback_input_history.add_authoritative(history, 2, 1, input_frame.neutral_sample())
        )
        t.eq(same.earliest_divergence, nil, "an identical prediction needs no correction")

        local later =
            assert(rollback_input_history.add_authoritative(history, 5, 1, sample(10, 0, 0, 0)))
        t.eq(later.earliest_divergence, 5)
        local earlier =
            assert(rollback_input_history.add_authoritative(history, 2, 2, sample(-10, 0, 0, 0)))
        t.eq(earlier.earliest_divergence, 2)
        t.eq(rollback_input_history.earliest_divergence(history), 2)
        t.is_true(
            not pcall(rollback_input_history.materialize, history, 2),
            "a corrected timeline cannot overwrite used records before divergence is consumed"
        )
        t.eq(rollback_input_history.consume_earliest_divergence(history), 2)
        t.eq(rollback_input_history.consume_earliest_divergence(history), nil)

        local corrected = rollback_input_history.materialize(history, 2)
        t.eq(corrected.slots[2].move_x, -10)
        assert(rollback_input_history.add_authoritative(history, 3, 1, sample(40, 0, 0, 0)))
        t.eq(
            rollback_input_history.earliest_divergence(history),
            nil,
            "unmaterialized input is authority, not a correction"
        )
    end)

    t.it("advances confirmation monotonically across contiguous complete ticks", function()
        local history = rollback_input_history.new(sources())
        t.eq(rollback_input_history.confirmed_tick(history), -1)

        add_full_tick(history, 1)
        t.eq(rollback_input_history.confirmed_tick(history), -1, "tick zero remains a gap")
        add_full_tick(history, 0)
        t.eq(rollback_input_history.confirmed_tick(history), 1)
        add_full_tick(history, 3)
        t.eq(rollback_input_history.confirmed_tick(history), 1, "tick two remains a gap")
        add_full_tick(history, 2)
        t.eq(rollback_input_history.confirmed_tick(history), 3)
    end)

    t.it("accepts identical duplicates and rejects conflicts without mutation", function()
        local history = rollback_input_history.new(sources())
        local original = sample(12, -4, input_frame.HELD_BITS.pass, input_frame.EDGE_BITS.pass)
        local first = assert(rollback_input_history.add_authoritative(history, 0, 1, original))
        t.eq(first.duplicate, false)
        local duplicate =
            assert(rollback_input_history.add_authoritative(history, 0, 1, sample(12, -4, 2, 2)))
        t.eq(duplicate.duplicate, true)

        local rejected, message, code =
            rollback_input_history.add_authoritative(history, 0, 1, sample(13, -4, 2, 2))
        t.eq(rejected, nil)
        t.eq(code, "conflicting_authoritative")
        t.is_true(assert(message):match("tick 0 slot 1") ~= nil)
        local retained = assert(rollback_input_history.authoritative_record(history, 0, 1))
        t.eq(retained.sample.move_x, 12)
        t.eq(rollback_input_history.earliest_divergence(history), nil)

        for index = 2, input_frame.SLOT_COUNT do
            assert(
                rollback_input_history.add_authoritative(
                    history,
                    0,
                    index,
                    input_frame.neutral_sample()
                )
            )
        end
        t.eq(rollback_input_history.confirmed_tick(history), 0)
    end)

    t.it("deep-copies authoritative, effective, and caller-returned records", function()
        local history = rollback_input_history.new(sources())
        local supplied = sample(70, -20, input_frame.HELD_BITS.sprint, input_frame.EDGE_BITS.dodge)
        assert(rollback_input_history.add_authoritative(history, 0, 1, supplied))
        supplied.move_x = -99

        local frame, record = rollback_input_history.materialize(history, 0)
        t.eq(frame.slots[1].move_x, 70)
        frame.slots[1].move_x = 1
        record.slots[1].sample.move_x = 2
        local retained_record = assert(rollback_input_history.record(history, 0))
        t.eq(retained_record.slots[1].sample.move_x, 70)

        local authoritative = assert(rollback_input_history.authoritative_record(history, 0, 1))
        authoritative.sample.move_x = 3
        local retained_authoritative =
            assert(rollback_input_history.authoritative_record(history, 0, 1))
        t.eq(retained_authoritative.sample.move_x, 70)
    end)

    t.it("pins the initial rollback window to thirty 60 Hz ticks", function()
        t.eq(rollback_input_history.ROLLBACK_WINDOW_TICKS, 30)
        t.eq(rollback_input_history.ROLLBACK_WINDOW_MILLISECONDS, 500)
    end)
end)
