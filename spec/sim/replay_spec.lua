local t = require("spec.support.runner")
local short_match_tape = require("spec.fixtures.short_match_tape")
local input_frame = require("sim.input_frame")
local input_tape = require("sim.input_tape")
local match_snapshot = require("sim.match_snapshot")
local replay = require("sim.replay")
local tuning = require("sim.tuning")

---@param tape InputTape
---@return InputFrame[]
local function copy_frames(tape)
    local frames = {}
    for index, frame in ipairs(tape.frames) do
        frames[index] = assert(input_frame.copy(frame))
    end
    return frames
end

t.describe("input tape replay", function()
    t.it("replays a short complete match with every boundary hash", function()
        local tape, identity = short_match_tape.make()
        local result, failure = replay.run(tape, identity)
        local replayed = assert(result, failure and failure.message)
        t.eq(#replayed.boundaries, #tape.frames + 1)
        for index = 1, #replayed.boundaries do
            local expected = short_match_tape.EXPECTED_BOUNDARY_HASHES[index]
            t.eq(tape.boundary_hashes[index], expected, "constructed tape boundary " .. (index - 1))
            t.eq(replayed.boundaries[index].hash, expected, "replay boundary " .. (index - 1))
        end
        t.is_true(replayed.state.finished, "the fixture reaches its match end")
        t.eq(replayed.state.input_tick, 3)
        t.is_true(replayed.divergence == nil)

        replayed.state.ball.x = -500
        local second = assert(replay.run(tape, identity))
        t.is_true(second.state.ball.x ~= -500, "each replay returns independent final state")
    end)

    t.it("deep-copies snapshot frames identity and ownership at construction", function()
        local tape, identity = short_match_tape.make()
        local frames = copy_frames(tape)
        local initial = match_snapshot.capture(match_snapshot.restore(tape.initial))
        local copied = input_tape.new(identity, initial, frames)
        frames[1].slots[1].move_x = -127
        initial.state.ball.x = -1
        identity.ownership.slots[1].player_id = "changed"
        identity.config = "changed"
        t.eq(copied.frames[1].slots[1].move_x, tape.frames[1].slots[1].move_x)
        t.is_true(copied.initial.state.ball.x ~= -1)
        t.is_true(copied.identity.ownership.slots[1].player_id ~= "changed")
        t.is_true(copied.identity.config ~= "changed")
    end)

    t.it("rejects identity and active tuning mismatches separately", function()
        local tape, identity = short_match_tape.make()
        local wrong = input_tape.copy_identity(identity)
        wrong.content = "different-content"
        local result, failure = replay.run(tape, wrong)
        t.eq(result, nil)
        local mismatch = assert(failure)
        t.eq(mismatch.code, "identity_mismatch")
        t.eq(mismatch.path, "identity.content")

        tuning.set("AI_SHOOT_RANGE", tuning.values.AI_SHOOT_RANGE + 1)
        local tuned, tune_failure = replay.run(tape, identity)
        tuning.reset()
        t.eq(tuned, nil)
        local tune_mismatch = assert(tune_failure)
        t.eq(tune_mismatch.code, "identity_mismatch")
        t.eq(tune_mismatch.path, "identity.tuning")
    end)

    t.it("rejects identity before simulation-aware tape validation", function()
        local tape, identity = short_match_tape.make()
        tape.frames[4] = assert(input_frame.neutral(3))
        tape.boundary_hashes[5] = tape.boundary_hashes[4]

        local wrong = input_tape.copy_identity(identity)
        wrong.content = "different-content"
        local mismatched, mismatch_failure = replay.run(tape, wrong)
        t.eq(mismatched, nil)
        local mismatch = assert(mismatch_failure)
        t.eq(mismatch.code, "identity_mismatch")
        t.eq(mismatch.path, "identity.content")

        tuning.set("AI_SHOOT_RANGE", tuning.values.AI_SHOOT_RANGE + 1)
        local tuned, tune_failure = replay.run(tape, identity)
        tuning.reset()
        t.eq(tuned, nil)
        local tune_mismatch = assert(tune_failure)
        t.eq(tune_mismatch.code, "identity_mismatch")
        t.eq(tune_mismatch.path, "identity.tuning")

        local missing_identity, valid_identity = short_match_tape.make()
        rawset(missing_identity, "identity", nil)
        local malformed_result, malformed_failure = replay.run(missing_identity, valid_identity)
        t.eq(malformed_result, nil)
        t.eq(assert(malformed_failure).code, "malformed")
    end)

    t.it("names the first causal input and differing state path", function()
        local reference, identity = short_match_tape.make()
        local changed_frames = copy_frames(reference)
        changed_frames[1].slots[1] = assert(input_frame.new_sample({ move_x = -127 }))
        local candidate = input_tape.new(identity, reference.initial, changed_frames)
        local comparison, failure = replay.compare(reference, candidate, identity)
        local compared = assert(comparison, failure and failure.message)
        t.is_true(not compared.equal)
        local divergence = assert(compared.divergence)
        t.eq(divergence.causal_input_tick, 0)
        t.eq(divergence.boundary_tick, 1)
        t.is_true(divergence.expected_hash ~= divergence.actual_hash)
        t.is_true(divergence.state_path:match("^state%.players%."))
        t.is_true(divergence.expected_input ~= divergence.actual_input)
    end)

    t.it("diagnoses a modified initial state before any causal input", function()
        local reference, identity = short_match_tape.make()
        local changed = match_snapshot.capture(match_snapshot.restore(reference.initial))
        changed.state.ball_z = 1
        local candidate = input_tape.new(identity, changed, copy_frames(reference))
        local comparison = assert(replay.compare(reference, candidate, identity))
        local divergence = assert(comparison.divergence)
        t.eq(divergence.causal_input_tick, nil)
        t.eq(divergence.boundary_tick, 0)
        t.eq(divergence.state_path, "state.ball_z")
        t.eq(divergence.expected_state, 0)
        t.eq(divergence.actual_state, 1)
    end)

    t.it("detects tampering against a tape's frozen boundary hashes", function()
        local tape, identity = short_match_tape.make()
        tape.frames[1].slots[1].move_x = -127
        local result = assert(replay.run(tape, identity))
        local divergence = assert(result.divergence)
        t.eq(divergence.causal_input_tick, 0)
        t.eq(divergence.boundary_tick, 1)
        t.eq(divergence.state_path, "unavailable_without_reference_tape")
    end)

    t.it("reports malformed and unsupported tape versions", function()
        local tape, identity = short_match_tape.make()
        tape.version = 999
        local result, failure = replay.run(tape, identity)
        t.eq(result, nil)
        local malformed = assert(failure)
        t.eq(malformed.code, "malformed")
        t.is_true(malformed.message:match("unsupported input tape version") ~= nil)

        local snapshot_tape, snapshot_identity = short_match_tape.make()
        snapshot_tape.initial.version = 1
        local snapshot_result, snapshot_failure = replay.run(snapshot_tape, snapshot_identity)
        t.eq(snapshot_result, nil)
        local prior_schema = assert(snapshot_failure)
        t.eq(prior_schema.code, "malformed")
        t.is_true(prior_schema.message:match("unsupported match snapshot version") ~= nil)
    end)

    t.it("rejects ownership detached from the initial snapshot and post-match frames", function()
        local tape, identity = short_match_tape.make()
        tape.identity.ownership.slots[1].player_id = "detached-owner"
        local expected = input_tape.copy_identity(tape.identity)
        local detached, detached_failure = replay.run(tape, expected)
        t.eq(detached, nil)
        t.eq(assert(detached_failure).code, "malformed")

        local complete, complete_identity = short_match_tape.make()
        local frames = copy_frames(complete)
        frames[4] = assert(input_frame.neutral(3))
        t.is_true(
            not pcall(input_tape.new, complete_identity, complete.initial, frames),
            "a materialized frame cannot follow the finished boundary"
        )

        complete.frames[4] = assert(input_frame.neutral(3))
        complete.boundary_hashes[5] = complete.boundary_hashes[4]
        local appended, appended_failure = replay.run(complete, complete_identity)
        t.eq(appended, nil)
        local malformed = assert(appended_failure)
        t.eq(malformed.code, "malformed")
        t.is_true(malformed.message:match("frame after the match finished") ~= nil)
    end)

    t.it("rejects jointly malformed ownership and snapshot routing", function()
        local tape, identity = short_match_tape.make()
        local malformed_identity = input_tape.copy_identity(identity)
        local malformed_snapshot = match_snapshot.capture(match_snapshot.restore(tape.initial))
        malformed_identity.ownership.slots[1].team = "away"
        malformed_snapshot.state.input_ownership.slots[1].team = "away"
        t.is_true(
            not pcall(input_tape.new, malformed_identity, malformed_snapshot, copy_frames(tape)),
            "matching malformed slot semantics must still be rejected"
        )

        local duplicate_identity = input_tape.copy_identity(identity)
        local duplicate_snapshot = match_snapshot.capture(match_snapshot.restore(tape.initial))
        duplicate_identity.ownership.rosters.home[2] = duplicate_identity.ownership.rosters.home[1]
        duplicate_snapshot.state.input_ownership.rosters.home[2] =
            duplicate_snapshot.state.input_ownership.rosters.home[1]
        t.is_true(
            not pcall(input_tape.new, duplicate_identity, duplicate_snapshot, copy_frames(tape)),
            "matching duplicate roster membership must still be rejected"
        )

        local route_snapshot = match_snapshot.capture(match_snapshot.restore(tape.initial))
        route_snapshot.state.slot_players[1] = route_snapshot.state.slot_players[2]
        t.is_true(
            not pcall(input_tape.new, identity, route_snapshot, copy_frames(tape)),
            "slot_players must agree with immutable ownership"
        )

        local inverse_snapshot = match_snapshot.capture(match_snapshot.restore(tape.initial))
        local first_player = inverse_snapshot.state.slot_players[1]
        inverse_snapshot.state.slot_for_player[first_player] = 2
        t.is_true(
            not pcall(input_tape.new, identity, inverse_snapshot, copy_frames(tape)),
            "slot_for_player must agree with immutable ownership"
        )
    end)
end)
