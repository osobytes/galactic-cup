local Vec2 = require("core.vec2")
local audio = require("game.audio")
local match_observer = require("game.match_observer")
local effects = require("game.render.effects")
local replay = require("game.render.replay")
local Match = require("game.screens.match")
local RealMatch = require("game.screens.real_match")
local fixed_clock = require("sim.fixed_clock")
local sim_match = require("sim.match")
local teams = require("data.teams")
local t = require("spec.support.runner")

---@param id string
---@param tick integer
---@param kind string
---@param player string?
---@return RollbackWrappedMatchEvent
local function wrapped_match_event(id, tick, kind, player)
    return {
        id = id,
        tick = tick,
        domain = "match/" .. kind,
        ordinal = 1,
        payload = {
            kind = kind,
            x = 100 + tick,
            y = 200 + tick,
            player = player,
        },
    }
end

---@param id string
---@param tick integer
---@param kind RollbackLifecycleKind
---@return RollbackWrappedLifecycleEvent
local function wrapped_lifecycle_event(id, tick, kind)
    local domain = "lifecycle/" .. kind
    return {
        id = id,
        tick = tick,
        domain = domain,
        ordinal = 1,
        payload = {
            kind = kind,
            team = kind == "goal" and "home" or nil,
            score = { home = kind == "goal" and 1 or 0, away = 0 },
        },
    }
end

---@param tick integer
---@param events RollbackWrappedMatchEvent[]
---@param owner_team InputTeam?
---@param home_score integer?
---@return RollbackEventStep
local function confirmed_step(tick, events, owner_team, home_score)
    return {
        tick = tick,
        start_boundary = tick,
        end_boundary = tick + 1,
        state = {
            score = { home = home_score or 0, away = 0 },
            time_left = 120 - (tick + 1) * fixed_clock.TICK_SECONDS,
            finished = false,
            owner_id = nil,
            owner_team = owner_team,
        },
        match_events = events,
        lifecycle_events = {},
    }
end

t.describe("rollback presentation consumers", function()
    t.it("deduplicates confirmed event and lifecycle audio by stable ID", function()
        audio.reset()
        local shot = wrapped_match_event("shot-id", 4, "shot", "striker")
        local goal = wrapped_lifecycle_event("goal-id", 4, "goal")
        local kickoff = wrapped_lifecycle_event("kickoff-id", 4, "kickoff")
        local full_time = wrapped_lifecycle_event("full-time-id", 5, "full_time")

        t.is_true(audio.consume_confirmed(shot))
        t.is_true(not audio.consume_confirmed(shot))
        audio.consume_confirmed(goal)
        audio.consume_confirmed(goal)
        audio.consume_confirmed(kickoff)
        audio.consume_confirmed(full_time)
        local counts = audio.confirmed_cue_counts()
        t.eq(counts.shot, 1)
        t.eq(counts.goal, 1)
        t.eq(counts.kickoff, 1)
        t.eq(counts.full_time, 1)
    end)

    t.it("adds, replaces, and revokes speculative effects by event ID", function()
        effects.reset()
        local shot = wrapped_match_event("action-id", 8, "shot", "striker")
        effects.apply_event_diff({ added = { shot }, revoked = {}, replaced = {} })
        local added = effects.diagnostics()
        t.eq(added.particle_count, 11)
        t.eq(added.speculative_ids[1], "action-id")

        effects.apply_event_diff({ added = { shot }, revoked = {}, replaced = {} })
        t.eq(effects.diagnostics().particle_count, 11, "duplicate add is idempotent")

        local pass = wrapped_match_event("action-id", 8, "pass", "striker")
        effects.apply_event_diff({
            added = {},
            revoked = {},
            replaced = { { before = shot, after = pass } },
        })
        local replaced = effects.diagnostics()
        t.eq(replaced.particle_count, 6)
        t.eq(replaced.speculative_ids[1], "action-id")

        effects.apply_event_diff({ added = {}, revoked = { pass }, replaced = {} })
        local revoked = effects.diagnostics()
        t.eq(revoked.particle_count, 0)
        t.eq(#revoked.speculative_ids, 0)
    end)

    t.it("keeps speculative goal lifecycle changes silent and reversible", function()
        audio.reset()
        effects.reset()
        replay.reset()
        local goal = wrapped_lifecycle_event("predicted-goal", 9, "goal")
        effects.apply_event_diff({ added = { goal }, revoked = {}, replaced = {} })
        t.eq(effects.diagnostics().particle_count, 0)
        t.is_true(not replay.active())
        t.is_true(audio.confirmed_cue_counts().goal == nil)

        effects.apply_event_diff({ added = {}, revoked = { goal }, replaced = {} })
        t.eq(effects.diagnostics().particle_count, 0)
        t.is_true(not replay.active())
        t.is_true(audio.confirmed_cue_counts().kickoff == nil)
    end)

    t.it("drops an invalid loose-ball trail on correction", function()
        effects.reset()
        local state =
            sim_match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        state.owner = nil
        state.ball = Vec2.new(300, 200)
        state.ball_vel = Vec2.new(500, 0)
        effects.sample_ball(state)
        t.eq(effects.diagnostics().trail_count, 1)
        effects.reset_trail()
        t.eq(effects.diagnostics().trail_count, 0)
    end)

    t.it("accounts newly confirmed observer steps exactly once", function()
        local state =
            sim_match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        local home_id = state.players[2].id
        local pass = wrapped_match_event("pass-0", 0, "pass", home_id)
        local shot = wrapped_match_event("shot-1", 1, "shot", home_id)
        local delayed = match_observer.new(state)
        local reference = match_observer.new(state)
        local first = confirmed_step(0, { pass }, "home")
        local second = confirmed_step(1, { shot }, "home", 1)

        match_observer.observe_confirmed(reference, first)
        match_observer.observe_confirmed(reference, second)
        match_observer.observe_confirmed(delayed, first)
        t.is_true(not match_observer.observe_confirmed(delayed, first))
        match_observer.observe_confirmed(delayed, second)
        t.is_true(not match_observer.observe_confirmed(delayed, second))

        local expected = match_observer.finish(reference)
        local actual = match_observer.finish(delayed)
        t.eq(actual.home_stats.shots, expected.home_stats.shots)
        t.eq(actual.home_stats.pass_completion, expected.home_stats.pass_completion)
        t.near(actual.home_stats.possession, assert(expected.home_stats.possession), 1e-12)
        t.eq(actual.mvp_player_id, expected.mvp_player_id)
    end)

    t.it("truncates and replaces replay footage by simulation boundary", function()
        replay.reset()
        local state =
            sim_match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        for boundary = 0, 40 do
            state.ball = Vec2.new(boundary, 100)
            replay.record_boundary(boundary, state)
        end
        replay.truncate_from(20)
        for boundary = 20, 40 do
            state.ball = Vec2.new(1000 + boundary, 200)
            replay.record_boundary(boundary, state)
        end

        local diagnostics = replay.diagnostics()
        t.eq(diagnostics.count, 41)
        t.eq(diagnostics.oldest_boundary, 0)
        t.eq(diagnostics.newest_boundary, 40)
        t.eq(assert(replay.boundary_sample(19)).ball_x, 19)
        t.eq(assert(replay.boundary_sample(20)).ball_x, 1020)
        t.eq(assert(replay.boundary_sample(40)).ball_y, 200)
    end)

    t.it("gates RealMatch result completion on confirmed full time", function()
        local lab_match = Match.new({
            rollback_lab = {
                profile_name = "clean",
                duration = fixed_clock.TICK_SECONDS,
            },
        })
        local completed = 0
        local request = {
            home_team_id = "nebula",
            away_team_id = "orion",
            home_starter_ids = { "ozzo", "veil_nyx", "rok_tann", "mika_olu", "sela_dwin" },
            formation_id = "1-2-1",
            tactic_id = "balanced",
            arena_id = "helios_crown",
            seed = 75,
            show_onboarding = false,
        }
        ---@cast request ProductMatchRequest
        local screen = RealMatch.new(request, {
            on_finished = function()
                completed = completed + 1
            end,
            on_cancelled = function() end,
        })
        screen.match = lab_match
        screen.observer = match_observer.new(lab_match.state)

        lab_match.state.finished = true
        screen:update(0)
        t.eq(completed, 0, "speculative state.finished must not complete the result")
        lab_match._presentation_full_time = true
        screen:update(0.9)
        screen:update(1)
        t.eq(completed, 1)
    end)
end)
