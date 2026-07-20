-- OMP-1 full-match determinism recording, verification, and evidence report.
--
-- Verification decodes only the checked-in effective InputFrames. Recording
-- is an explicit developer action which materializes all eight bot streams
-- once, outside the authoritative replay path.

local fnv1a64 = require("core.fnv1a64")
local fixture = require("data.omp1_determinism")
local teams = require("data.teams")
local fixed_clock = require("sim.fixed_clock")
local input_frame = require("sim.input_frame")
local input_tape = require("sim.input_tape")
local match = require("sim.match")
local match_snapshot = require("sim.match_snapshot")
local slot_input = require("sim.slot_input")
local tuning = require("sim.tuning")

---@class DeterminismCoverage
---@field tackle boolean
---@field keeper boolean
---@field aerial boolean
---@field goal_kickoff boolean
---@field full_time boolean

---@class DeterminismEvidenceResult
---@field fixture_id string
---@field ticks integer
---@field boundaries integer
---@field final_hash string
---@field sequence_digest string
---@field score_home integer
---@field score_away integer
---@field outcome "home"|"away"|"draw"
---@field snapshot_bytes integer
---@field coverage DeterminismCoverage

---@class Omp1Recording
---@field frame_wires string[]
---@field boundary_hashes string[]
---@field event_ticks table<string, integer>
---@field event_counts table<string, integer>
---@field score_home integer
---@field score_away integer

---@class DeterminismCampaign
---@field frames InputFrame[]
---@field expected_hashes string[]
---@field reference MatchState
---@field candidate MatchState?
---@field sequence Fnv1a64State
---@field snapshots table<integer, MatchSnapshot>
---@field window_starts table<integer, boolean>
---@field coverage DeterminismCoverage
---@field event_counts table<string, integer>
---@field next_index integer
---@field result DeterminismEvidenceResult?

---@class DeterminismEvidenceModule
local determinism_evidence = {}

local REQUIRED_EVENT_KINDS = {
    tackle = "tackle",
    keeper = "catch",
    aerial = "header",
}

---@param allow_prior_snapshot boolean?
---@return MatchState
local function new_state(allow_prior_snapshot)
    -- The explicit refresh command is also the schema-migration path: it must
    -- be able to replay the previous fixture's ownership while producing the
    -- current snapshot version. Ordinary verification still validates the
    -- complete identity through input_tape.copy_identity below.
    local identity = allow_prior_snapshot and fixture.identity
        or input_tape.copy_identity(fixture.identity)
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        duration = fixture.duration_seconds,
        max_goals = 3,
        seed = identity.seed,
        input_ownership = identity.ownership,
    })
end

---@param lines string
---@return string[]
local function split_lines(lines)
    local result = {}
    for line in lines:gmatch("([^\n]+)") do
        result[#result + 1] = line
    end
    return result
end

---@param state MatchState
---@return string
local function state_hash(state)
    return match_snapshot.hash(match_snapshot.capture(state))
end

---@param state MatchState
---@return boolean
local function has_event(state, kind)
    for _, event in ipairs(state.events) do
        if event.kind == kind then
            return true
        end
    end
    return false
end

---@param home integer
---@param away integer
---@return "home"|"away"|"draw"
local function outcome(home, away)
    if home > away then
        return "home"
    elseif away > home then
        return "away"
    end
    return "draw"
end

---@param snapshots table<integer, MatchSnapshot>
---@param frames InputFrame[]
---@param expected_hashes string[]
---@param window Omp1Window
local function verify_window(snapshots, frames, expected_hashes, window)
    local initial = assert(
        snapshots[window.first_boundary],
        "missing snapshot for " .. window.name .. " window"
    )
    local state = match_snapshot.restore(initial)
    local saw_expected_event = window.event_kind == nil
    for boundary = window.first_boundary + 1, window.last_boundary do
        local causal_tick = boundary - 1
        match.step(state, fixed_clock.TICK_SECONDS, frames[causal_tick + 1])
        local actual = state_hash(state)
        assert(
            actual == expected_hashes[boundary + 1],
            ("%s restore/replay diverged at causal tick %d: expected %s, got %s"):format(
                window.name,
                causal_tick,
                expected_hashes[boundary + 1],
                actual
            )
        )
        if window.event_kind and has_event(state, window.event_kind) then
            assert(
                causal_tick == window.event_tick,
                ("%s event moved from tick %d to %d"):format(
                    window.name,
                    assert(window.event_tick),
                    causal_tick
                )
            )
            saw_expected_event = true
        end
    end
    assert(saw_expected_event, window.name .. " restore/replay missed its required event")
    if window.name == "goal_kickoff" then
        assert(state.score.away == 1, "goal window did not preserve the away goal")
        assert(state.kickoff_hold > 0, "goal window did not preserve the home kickoff")
    elseif window.name == "full_time" then
        assert(state.finished and state.time_left == 0, "full-time window did not finish")
    end
end

---@param compare_fresh boolean?
---@return DeterminismCampaign
function determinism_evidence.new_campaign(compare_fresh)
    assert(fixture.version == 1, "unsupported OMP-1 determinism fixture")
    local identity = input_tape.copy_identity(fixture.identity)
    assert(identity.tick_rate == fixed_clock.TICK_RATE, "fixture tick rate drifted")
    assert(identity.tuning == tuning.serialize(), "fixture tuning identity drifted")
    assert(identity.fixture == fixture.fixture_id, "fixture identity disagrees with fixture id")
    local wires = split_lines(fixture.frame_wires)
    local expected_hashes = split_lines(fixture.boundary_hashes)
    assert(#wires == fixture.frame_count, "fixture frame count does not match its recording")
    assert(
        #expected_hashes == fixture.boundary_count,
        "fixture boundary count does not match its baseline"
    )
    assert(#expected_hashes == #wires + 1, "fixture needs one hash per boundary")

    local frames = {}
    for index, wire in ipairs(wires) do
        local decoded, err = input_frame.decode(wire)
        assert(decoded, ("fixture frame %d is malformed: %s"):format(index - 1, tostring(err)))
        assert(decoded.tick == index - 1, "fixture frames are not contiguous from tick zero")
        frames[index] = decoded
    end

    local reference = new_state()
    local candidate = compare_fresh ~= false and new_state() or nil
    local initial_hash = state_hash(reference)
    if candidate then
        assert(initial_hash == state_hash(candidate), "fresh matches disagree at boundary zero")
    end
    assert(
        initial_hash == expected_hashes[1],
        ("pinned boundary 0 drifted: expected %s, got %s"):format(expected_hashes[1], initial_hash)
    )

    local sequence = fnv1a64.new()
    fnv1a64.update(sequence, initial_hash .. "\n")
    local snapshots = {}
    local window_starts = {}
    for _, window in ipairs(fixture.windows) do
        window_starts[window.first_boundary] = true
    end
    if window_starts[0] then
        snapshots[0] = match_snapshot.capture(reference)
    end

    return {
        frames = frames,
        expected_hashes = expected_hashes,
        reference = reference,
        candidate = candidate,
        sequence = sequence,
        snapshots = snapshots,
        window_starts = window_starts,
        coverage = {
            tackle = false,
            keeper = false,
            aerial = false,
            goal_kickoff = false,
            full_time = false,
        },
        event_counts = {},
        next_index = 1,
    }
end

---@param campaign DeterminismCampaign
---@return DeterminismEvidenceResult
local function finish_campaign(campaign)
    local reference = campaign.reference
    assert(reference.finished, "recording did not reach full time")
    assert(reference.input_tick == fixture.frame_count, "recording ended at the wrong tick")
    assert(reference.score.home == fixture.expected_score.home, "home score drifted")
    assert(reference.score.away == fixture.expected_score.away, "away score drifted")
    local final_hash = state_hash(reference)
    local sequence_digest = fnv1a64.hex(campaign.sequence)
    assert(final_hash == fixture.expected_final_hash, "fixture final hash drifted")
    assert(sequence_digest == fixture.expected_sequence_digest, "fixture sequence digest drifted")
    for name, covered in pairs(campaign.coverage) do
        assert(covered, "fixture did not cover " .. name)
    end
    for name, expected in pairs(fixture.event_counts) do
        assert(
            campaign.event_counts[name] == expected,
            ("fixture event count %s drifted: expected %d, got %s"):format(
                name,
                expected,
                tostring(campaign.event_counts[name])
            )
        )
    end
    for name, actual in pairs(campaign.event_counts) do
        assert(fixture.event_counts[name] == actual, "fixture gained unexpected event " .. name)
    end
    for _, window in ipairs(fixture.windows) do
        verify_window(campaign.snapshots, campaign.frames, campaign.expected_hashes, window)
    end
    return {
        fixture_id = fixture.fixture_id,
        ticks = fixture.frame_count,
        boundaries = fixture.boundary_count,
        final_hash = final_hash,
        sequence_digest = sequence_digest,
        score_home = reference.score.home,
        score_away = reference.score.away,
        outcome = outcome(reference.score.home, reference.score.away),
        snapshot_bytes = #match_snapshot.encode(match_snapshot.capture(reference)),
        coverage = campaign.coverage,
    }
end

---@param campaign DeterminismCampaign
---@param max_ticks integer
---@return DeterminismEvidenceResult?
function determinism_evidence.step_campaign(campaign, max_ticks)
    assert(max_ticks > 0 and max_ticks == math.floor(max_ticks), "max_ticks must be positive")
    if campaign.result then
        return campaign.result
    end
    local last_index = math.min(#campaign.frames, campaign.next_index + max_ticks - 1)
    for index = campaign.next_index, last_index do
        local frame = campaign.frames[index]
        local causal_tick = index - 1
        match.step(campaign.reference, fixed_clock.TICK_SECONDS, frame)
        if campaign.candidate then
            match.step(campaign.candidate, fixed_clock.TICK_SECONDS, frame)
        end
        local reference_hash = state_hash(campaign.reference)
        if campaign.candidate then
            local candidate_hash = state_hash(campaign.candidate)
            assert(
                reference_hash == candidate_hash,
                ("independent runs diverged after causal tick %d: reference %s, candidate %s"):format(
                    causal_tick,
                    reference_hash,
                    candidate_hash
                )
            )
        end
        assert(
            reference_hash == campaign.expected_hashes[index + 1],
            ("pinned boundary %d drifted after causal tick %d: expected %s, got %s"):format(
                index,
                causal_tick,
                campaign.expected_hashes[index + 1],
                reference_hash
            )
        )
        fnv1a64.update(campaign.sequence, reference_hash .. "\n")
        if campaign.window_starts[index] then
            campaign.snapshots[index] = match_snapshot.capture(campaign.reference)
        end
        for name, kind in pairs(REQUIRED_EVENT_KINDS) do
            if has_event(campaign.reference, kind) then
                campaign.coverage[name] = true
            end
        end
        for _, event in ipairs(campaign.reference.events) do
            campaign.event_counts[event.kind] = (campaign.event_counts[event.kind] or 0) + 1
        end
        if campaign.reference.score.away > 0 and campaign.reference.kickoff_hold > 0 then
            campaign.coverage.goal_kickoff = true
        end
        if campaign.reference.finished and campaign.reference.time_left == 0 then
            campaign.coverage.full_time = true
        end
    end
    campaign.next_index = last_index + 1
    if campaign.next_index > #campaign.frames then
        campaign.result = finish_campaign(campaign)
    end
    return campaign.result
end

---@return DeterminismEvidenceResult
function determinism_evidence.verify()
    local campaign = determinism_evidence.new_campaign(true)
    local result = nil
    while not result do
        result = determinism_evidence.step_campaign(campaign, fixture.frame_count)
    end
    return result
end

---@return Omp1Recording
function determinism_evidence.record()
    local state = new_state(true)
    local sources = {}
    for index, seed in ipairs(fixture.source_seeds) do
        sources[index] = { kind = "bot", seed = seed }
    end
    local producer = slot_input.new_producer(sources)
    local frame_wires = {}
    local boundary_hashes = { state_hash(state) }
    local event_ticks = {}
    local event_counts = {}
    while not state.finished do
        local tick = state.input_tick
        local neutral = assert(input_frame.neutral(tick))
        local frame = slot_input.materialize(producer, state, neutral)
        frame_wires[#frame_wires + 1] = assert(input_frame.encode(frame))
        match.step(state, fixed_clock.TICK_SECONDS, frame)
        boundary_hashes[#boundary_hashes + 1] = state_hash(state)
        for _, event in ipairs(state.events) do
            event_counts[event.kind] = (event_counts[event.kind] or 0) + 1
            if not event_ticks[event.kind] then
                event_ticks[event.kind] = tick
            end
        end
        if state.score.away > 0 and state.kickoff_hold > 0 and not event_ticks.goal_kickoff then
            event_ticks.goal_kickoff = tick
        end
        if state.finished and not event_ticks.full_time then
            event_ticks.full_time = tick
        end
    end
    return {
        frame_wires = frame_wires,
        boundary_hashes = boundary_hashes,
        event_ticks = event_ticks,
        event_counts = event_counts,
        score_home = state.score.home,
        score_away = state.score.away,
    }
end

---@param result DeterminismEvidenceResult
---@return string
function determinism_evidence.report(result)
    local identity = fixture.identity
    local event_names = {}
    for name in pairs(fixture.event_counts) do
        event_names[#event_names + 1] = name
    end
    table.sort(event_names)
    local event_parts = {}
    for index, name in ipairs(event_names) do
        event_parts[index] = name .. ":" .. fixture.event_counts[name]
    end
    return table.concat({
        "GC_DETERMINISM",
        "result",
        "schema=1",
        "fixture=" .. result.fixture_id,
        "build=" .. identity.build,
        "source=" .. identity.source,
        "content=" .. identity.content,
        "config=" .. identity.config,
        "tuning=" .. (identity.tuning == "" and "defaults" or identity.tuning),
        "seed=" .. identity.seed,
        "tick_rate=" .. fixed_clock.TICK_RATE,
        "ticks=" .. result.ticks,
        "boundaries=" .. result.boundaries,
        ("hash=fnv1a64-canonical-snapshot-v%d"):format(match_snapshot.VERSION),
        "final_hash=" .. result.final_hash,
        "sequence_digest=" .. result.sequence_digest,
        "score=" .. result.score_home .. "-" .. result.score_away,
        "outcome=" .. result.outcome,
        "snapshot_bytes=" .. result.snapshot_bytes,
        "coverage=goal_kickoff,tackle,aerial,keeper,full_time",
        "events=" .. table.concat(event_parts, ","),
    }, "|")
end

---@param recording Omp1Recording
---@return string
function determinism_evidence.serialize_recording(recording)
    local sequence = fnv1a64.new()
    for _, hash in ipairs(recording.boundary_hashes) do
        fnv1a64.update(sequence, hash .. "\n")
    end
    local windows = {
        {
            name = "tackle",
            first_boundary = assert(recording.event_ticks.tackle) - 1,
            last_boundary = assert(recording.event_ticks.tackle) + 2,
            event_kind = "tackle",
            event_tick = recording.event_ticks.tackle,
        },
        {
            name = "keeper",
            first_boundary = assert(recording.event_ticks.catch) - 2,
            last_boundary = assert(recording.event_ticks.catch) + 3,
            event_kind = "catch",
            event_tick = recording.event_ticks.catch,
        },
        {
            name = "aerial",
            first_boundary = assert(recording.event_ticks.header) - 2,
            last_boundary = assert(recording.event_ticks.header) + 3,
            event_kind = "header",
            event_tick = recording.event_ticks.header,
        },
        {
            name = "goal_kickoff",
            first_boundary = assert(recording.event_ticks.goal_kickoff) - 2,
            last_boundary = assert(recording.event_ticks.goal_kickoff) + 3,
            event_tick = recording.event_ticks.goal_kickoff,
        },
        {
            name = "full_time",
            first_boundary = assert(recording.event_ticks.full_time) - 2,
            last_boundary = assert(recording.event_ticks.full_time) + 1,
            event_tick = recording.event_ticks.full_time,
        },
    }
    local window_lines = {}
    for _, window in ipairs(windows) do
        local optional = ""
        if window.event_kind then
            optional = (", event_kind = %q"):format(window.event_kind)
        end
        window_lines[#window_lines + 1] = ("        { name = %q, first_boundary = %d, last_boundary = %d%s, event_tick = %d },"):format(
            window.name,
            window.first_boundary,
            window.last_boundary,
            optional,
            assert(window.event_tick)
        )
    end
    local seeds = {}
    for index, seed in ipairs(fixture.source_seeds) do
        seeds[index] = tostring(seed)
    end
    local frame_payload = table.concat(recording.frame_wires, "\n") .. "\n"
    local hash_payload = table.concat(recording.boundary_hashes, "\n") .. "\n"
    local event_names = {}
    for name in pairs(recording.event_counts) do
        event_names[#event_names + 1] = name
    end
    table.sort(event_names)
    local event_counts = {}
    for index, name in ipairs(event_names) do
        event_counts[index] = ("%s = %d"):format(name, recording.event_counts[name])
    end
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion)
    local home_roster = {}
    local away_roster = {}
    for index = 1, #ownership.rosters.home do
        home_roster[index] = ("%q"):format(ownership.rosters.home[index])
        away_roster[index] = ("%q"):format(ownership.rosters.away[index])
    end
    local assignment_lines = {}
    for index, assignment in ipairs(ownership.slots) do
        assignment_lines[index] = ("                { slot = %q, team = %q, player_id = %q },"):format(
            assignment.slot,
            assignment.team,
            assignment.player_id
        )
    end
    return table.concat({
        "-- OMP-1 authoritative fixed-input recording.",
        "--",
        "-- Generated only by `love . --determinism-refresh`. Normal verification",
        "-- decodes these effective frames and never invokes their source bots.",
        "",
        "---@class Omp1Window",
        "---@field name string",
        "---@field first_boundary integer",
        "---@field last_boundary integer",
        "---@field event_kind string?",
        "---@field event_tick integer?",
        "",
        "---@class Omp1DeterminismFixture",
        "---@field version integer",
        "---@field fixture_id string",
        "---@field duration_seconds integer",
        "---@field frame_count integer",
        "---@field boundary_count integer",
        "---@field identity InputTapeIdentity",
        "---@field source_seeds integer[]",
        "---@field windows Omp1Window[]",
        "---@field event_counts table<string, integer>",
        "---@field expected_score { home: integer, away: integer }",
        "---@field expected_final_hash string",
        "---@field expected_sequence_digest string",
        "---@field frame_wires string",
        "---@field boundary_hashes string",
        "",
        "---@type Omp1DeterminismFixture",
        "return {",
        "    version = 1,",
        ("    fixture_id = %q,"):format(fixture.fixture_id),
        ("    duration_seconds = %d,"):format(fixture.duration_seconds),
        ("    frame_count = %d,"):format(#recording.frame_wires),
        ("    boundary_count = %d,"):format(#recording.boundary_hashes),
        "    identity = {",
        ("        tape_version = %d,"):format(input_tape.VERSION),
        ("        input_version = %d,"):format(input_frame.VERSION),
        ("        snapshot_version = %d,"):format(match_snapshot.VERSION),
        '        build = "omp1-determinism-v1",',
        '        source = "issue-39-canonical-recording-v1",',
        '        content = "nebula-orion-showcase-content-v1",',
        ("        tuning = %q,"):format(tuning.serialize()),
        '        config = "field=960x540;duration=120;max_goals=3;tick_rate=60",',
        ("        fixture = %q,"):format(fixture.fixture_id),
        "        seed = 19,",
        ("        tick_rate = %d,"):format(fixed_clock.TICK_RATE),
        "        ownership = {",
        ("            version = %d,"):format(input_frame.VERSION),
        "            rosters = {",
        ("                home = { %s },"):format(table.concat(home_roster, ", ")),
        ("                away = { %s },"):format(table.concat(away_roster, ", ")),
        "            },",
        "            slots = {",
        table.concat(assignment_lines, "\n"),
        "            },",
        "        },",
        "    },",
        ("    source_seeds = { %s },"):format(table.concat(seeds, ", ")),
        "    windows = {",
        table.concat(window_lines, "\n"),
        "    },",
        ("    event_counts = { %s },"):format(table.concat(event_counts, ", ")),
        ("    expected_score = { home = %d, away = %d },"):format(
            recording.score_home,
            recording.score_away
        ),
        ('    expected_final_hash = "%s",'):format(
            recording.boundary_hashes[#recording.boundary_hashes]
        ),
        ('    expected_sequence_digest = "%s",'):format(fnv1a64.hex(sequence)),
        "    frame_wires = [=[",
        frame_payload .. "]=],",
        "    boundary_hashes = [=[",
        hash_payload .. "]=],",
        "}",
        "",
    }, "\n")
end

return determinism_evidence
