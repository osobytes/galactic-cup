local determinism_evidence = require("sim.determinism_evidence")
local fixture = require("data.omp1_determinism")
local input_tape = require("sim.input_tape")
local match_snapshot = require("sim.match_snapshot")
local placement = require("sim.placement")
local t = require("spec.support.runner")

t.describe("OMP-1 determinism evidence", function()
    t.it("pins the authoritative fixture to the current snapshot schema", function()
        t.eq(fixture.identity.snapshot_version, match_snapshot.VERSION)
        t.eq(match_snapshot.VERSION, 5)
    end)

    t.it("uses a total order for equal-distance match candidates", function()
        local before = placement.distance_candidate_before
        t.is_true(before({ idx = 9, d = 10 }, { idx = 2, d = 10 }))
        t.is_true(not before({ idx = 2, d = 10 }, { idx = 9, d = 10 }))
        t.is_true(before({ idx = 9, d = 9 }, { idx = 2, d = 10 }))
        t.is_true(not before({ idx = 2, d = 10 }, { idx = 9, d = 9 }))
    end)

    t.it("validates a migration identity while changing only the snapshot version", function()
        local prior = input_tape.copy_identity(fixture.identity)
        prior.snapshot_version = match_snapshot.VERSION - 1
        local migrated = determinism_evidence.migration_identity(prior)

        for _, field in ipairs(input_tape.IDENTITY_FIELDS) do
            if field ~= "snapshot_version" and field ~= "ownership" then
                t.eq(migrated[field], prior[field], "migration identity field " .. field)
            end
        end
        t.eq(migrated.snapshot_version, match_snapshot.VERSION)
        t.is_true(migrated.ownership ~= prior.ownership)
        local frozen_keeper = migrated.ownership.rosters.home[1]
        prior.ownership.rosters.home[1] = "mutated-after-copy"
        t.eq(migrated.ownership.rosters.home[1], frozen_keeper)

        local malformed = input_tape.copy_identity(fixture.identity)
        malformed.snapshot_version = match_snapshot.VERSION - 1
        rawset(malformed, "unexpected", true)
        t.is_true(not pcall(determinism_evidence.migration_identity, malformed))
        rawset(malformed, "unexpected", nil)
        rawset(malformed.ownership.rosters.home, 1, false)
        t.is_true(not pcall(determinism_evidence.migration_identity, malformed))
    end)

    t.it("pins the full fixed-input match on the explicit evidence command", function()
        local result = determinism_evidence.verify()
        t.eq(result.ticks, 7201)
        t.eq(result.boundaries, 7202)
        t.eq(result.score_home, 0)
        t.eq(result.score_away, 0)
        t.eq(result.outcome, "draw")
        t.is_true(not result.coverage.goal_kickoff)
        t.is_true(result.coverage.tackle)
        t.is_true(result.coverage.aerial)
        t.is_true(result.coverage.keeper)
        t.is_true(result.coverage.full_time)
        local report = determinism_evidence.report(result)
        t.is_true(report:match("coverage=tackle,aerial,keeper,full_time") ~= nil)
        t.is_true(report:match("coverage=goal_kickoff") == nil)
    end)
end)
