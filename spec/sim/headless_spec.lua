local t = require("spec.support.runner")
local headless = require("sim.headless")
local match = require("sim.match")
local bot = require("sim.bot")
local input_frame = require("sim.input_frame")
local slot_input = require("sim.slot_input")
local tuning = require("sim.tuning")
local players = require("data.players")
local teams = require("data.teams")
local tactics = require("data.tactics")

---@param ticks integer
---@return InputFrame[]
local function recorded_frames(ticks)
    local frames = {}
    for tick = 0, ticks - 1 do
        local slots = {}
        for index = 1, input_frame.SLOT_COUNT do
            slots[index] = input_frame.neutral_sample()
        end
        slots[1] = assert(input_frame.new_sample({ move_x = 127 }))
        slots[5] = assert(input_frame.new_sample({ move_x = -127 }))
        frames[tick + 1] = assert(input_frame.new(tick, slots))
    end
    return frames
end

---@param ticks integer
---@return InputFrame[]
local function recorded_simultaneous_actions(ticks)
    local frames = recorded_frames(ticks)
    for tick = 0, math.min(4, ticks - 1) do
        frames[tick + 1].slots[4] =
            assert(input_frame.new_sample({ held = input_frame.HELD_BITS.pass }))
        frames[tick + 1].slots[5] =
            assert(input_frame.new_sample({ held = input_frame.HELD_BITS.jockey }))
    end
    if ticks > 5 then
        frames[6].slots[4] = assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.pass }))
        frames[6].slots[5] = assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.dash }))
    end
    return frames
end

---@param a MatchMetrics
---@param b MatchMetrics
local function assert_same_metrics(a, b)
    for k, v in pairs(a) do
        t.near(v, b[k], 1e-12, "metric " .. k .. " must reproduce")
    end
    for k, v in pairs(b) do
        t.near(v, a[k], 1e-12, "metric " .. k .. " must reproduce")
    end
end

---@param opts HeadlessOpts
---@return boolean ok
---@return any result
---@return SlotInputProducerState? producer
local function run_capturing_producer(opts)
    local original_new = slot_input.new_producer
    ---@type SlotInputProducerState?
    local captured = nil
    slot_input.new_producer = function(sources)
        captured = original_new(sources)
        return captured
    end
    local ok, result = pcall(headless.run_match, opts)
    slot_input.new_producer = original_new
    return ok, result, captured
end

---@return table<string, PlayerData>
local function players_by_id()
    local by_id = {}
    for _, player in ipairs(players) do
        by_id[player.id] = player
    end
    return by_id
end

t.describe("headless.run_match", function()
    t.it("plays a full short match and produces sane metrics", function()
        local r = headless.run_match({ seed = 5, duration = 30 })
        local m = r.metrics
        t.eq(r.score.home, m.goals_home)
        t.eq(r.score.away, m.goals_away)
        if r.score.home == r.score.away then
            t.is_true(r.winner == nil, "draws have no winner")
        else
            t.eq(r.winner, r.score.home > r.score.away and "home" or "away")
        end
        t.is_true(m.duration >= 29, "the match ran (close to) its full length")
        t.is_true(m.goals_total >= 0)
        t.is_true(m.turnovers_per_min >= 0)
        t.is_true(m.fun ~= nil and m.fun >= 0 and m.fun <= 1, "fun score is 0..1")
        if m.possession_balance then
            t.is_true(m.possession_balance > 0 and m.possession_balance < 1)
        end
    end)

    t.it("is deterministic: same seed, identical metrics", function()
        local a = headless.run_match({ seed = 9, duration = 30 })
        local b = headless.run_match({ seed = 9, duration = 30 })
        assert_same_metrics(a.metrics, b.metrics)
    end)

    t.it("different seeds diverge", function()
        local a = headless.run_match({ seed = 1, duration = 30 })
        local b = headless.run_match({ seed = 2, duration = 30 })
        local differ = false
        for k, v in pairs(a.metrics) do
            if b.metrics[k] ~= v then
                differ = true
            end
        end
        t.is_true(differ, "two seeds should not play the identical match")
    end)

    t.it("applies a tuning blob for the run and restores the knobs after", function()
        tuning.reset()
        local before = tuning.values.AI_SHOOT_RANGE
        headless.run_match({ seed = 3, duration = 10, tuning_blob = "AI_SHOOT_RANGE=340" })
        t.eq(tuning.values.AI_SHOOT_RANGE, before, "knobs restored after the batch")
    end)

    t.it("keeps default fixture options on the home-proxy mode", function()
        local implicit = headless.run_match({ seed = 17, duration = 20 })
        local explicit = headless.run_match({
            seed = 17,
            duration = 20,
            home = teams.nebula,
            away = teams.orion,
            home_formation = teams.nebula.formation,
            away_formation = teams.orion.formation,
            tactic = tactics.balanced,
            away_tactic = tactics.balanced,
            field = { w = 960, h = 540 },
            bot = "home",
        })
        assert_same_metrics(implicit.metrics, explicit.metrics)
    end)

    t.it("keeps no-frame runs on the legacy MatchInput path", function()
        local original_new = match.new
        local original_bot_new = bot.new
        ---@type MatchState?
        local captured = nil
        local bot_calls = 0
        match.new = function(opts)
            captured = original_new(opts)
            return captured
        end
        bot.new = function(opts)
            bot_calls = bot_calls + 1
            return original_bot_new(opts)
        end
        local ok, result = pcall(headless.run_match, { seed = 19, duration = 3 })
        match.new = original_new
        bot.new = original_bot_new

        t.is_true(ok, tostring(result))
        local state = assert(captured)
        t.is_true(not state.slot_mode)
        t.eq(bot_calls, 1, "legacy home-proxy bot is constructed once")
    end)

    t.it(
        "runs a non-default fixture with formation, tactic, roster, and field overrides",
        function()
            local by_id = players_by_id()
            local keeper = by_id.gax_oru
            by_id.gax_oru = {
                id = keeper.id,
                name = "Harness Gax",
                number = keeper.number,
                position = keeper.position,
                stats = keeper.stats,
                presentation_id = keeper.presentation_id,
                cosmetic_variant_id = keeper.cosmetic_variant_id,
                loadout_id = keeper.loadout_id,
            }

            local original_new = match.new
            ---@type MatchState?
            local captured = nil
            match.new = function(opts)
                captured = original_new(opts)
                return captured
            end
            local ok, result = pcall(headless.run_match, {
                seed = 31,
                duration = 5,
                home = teams.orion,
                away = teams.nebula,
                home_formation = "1-2-1",
                away_formation = "1-1-2",
                tactic = tactics.counter,
                away_tactic = tactics.press_high,
                players_by_id = by_id,
                field = { w = 800, h = 450 },
            })
            match.new = original_new

            t.is_true(ok, tostring(result))
            local s = assert(captured)
            t.eq(s.players[1].id, "gax_oru", "Orion is the home side")
            t.eq(s.players[1].name, "Harness Gax", "custom player lookup reached match.new")
            t.eq(s.players[6].id, "ozzo", "Nebula is the away side")
            t.eq(s.field.w, 800)
            t.eq(s.field.h, 450)
            t.near(s.players[2].anchor.x, 112, 1e-12, "home formation and tactic were applied")
            t.near(s.players[7].anchor.x, 496, 1e-12, "away formation and tactic were applied")
            t.near(s.players[7].anchor.y, 225, 1e-12, "away formation override changed its shape")
            t.eq(s.press.home, tactics.counter.press)
            t.eq(s.press.away, tactics.press_high.press)
            t.eq(teams.nebula.formation, "2-1-1", "canonical away team data was not mutated")

            ---@cast result MatchResult
            t.is_true(result.metrics.goals_total >= 0, "the fixture produced a valid MatchResult")
        end
    )

    t.it("runs deterministic match-AI vs match-AI fixtures without constructing a bot", function()
        local original_new = bot.new
        local calls = 0
        bot.new = function(opts)
            calls = calls + 1
            return original_new(opts)
        end
        local ok, a = pcall(headless.run_match, { seed = 43, duration = 20, bot = "none" })
        bot.new = original_new

        t.is_true(ok, tostring(a))
        t.eq(calls, 0, "AI/AI mode must not construct the human-proxy bot")
        ---@cast a MatchResult
        local b = headless.run_match({ seed = 43, duration = 20, bot = "none" })
        t.is_true(a.metrics.duration >= 19, "the AI/AI fixture ran to full time")
        assert_same_metrics(a.metrics, b.metrics)
    end)

    t.it(
        "replays a complete eight-stream fixture with simultaneous actions deterministically",
        function()
            local frames = recorded_simultaneous_actions(200)
            local a = headless.run_match({
                seed = 67,
                duration = 3,
                frames = frames,
            })
            local b = headless.run_match({
                seed = 67,
                duration = 3,
                frames = frames,
            })
            t.is_true(a.metrics.duration >= 2.9)
            t.eq(a.score.home, b.score.home)
            t.eq(a.score.away, b.score.away)
            assert_same_metrics(a.metrics, b.metrics)
        end
    )

    t.it("defaults a complete recording to all frame sources", function()
        local ok, result, producer = run_capturing_producer({
            seed = 69,
            duration = 3,
            frames = recorded_frames(200),
        })

        t.is_true(ok, tostring(result))
        local state = assert(producer)
        for index = 1, input_frame.SLOT_COUNT do
            t.eq(state.sources[index].kind, "frame")
        end
    end)

    t.it("does not inject a legacy proxy when explicit sources omit frames", function()
        local sources = {}
        for index = 1, input_frame.SLOT_COUNT do
            sources[index] = { kind = "neutral" }
        end
        local original_new = bot.new
        local calls = 0
        bot.new = function(opts)
            calls = calls + 1
            return original_new(opts)
        end
        local ok, result, producer = run_capturing_producer({
            seed = 70,
            duration = 3,
            slot_sources = sources,
        })
        bot.new = original_new

        t.is_true(ok, tostring(result))
        t.eq(calls, 0, "only explicitly configured slot bots may be created")
        local state = assert(producer)
        for index = 1, input_frame.SLOT_COUNT do
            t.eq(state.sources[index].kind, "neutral")
        end
    end)

    t.it("supports a deterministic mixture of recorded and explicitly bot-filled slots", function()
        local sources = {}
        for index = 1, input_frame.SLOT_COUNT do
            sources[index] = index == 1 and { kind = "frame" }
                or { kind = "bot", seed = 800 + index }
        end
        local frames = recorded_frames(200)
        local a = headless.run_match({
            seed = 71,
            duration = 3,
            frames = frames,
            slot_sources = sources,
        })
        local b = headless.run_match({
            seed = 71,
            duration = 3,
            frames = frames,
            slot_sources = sources,
        })
        t.is_true(a.metrics.duration >= 2.9)
        assert_same_metrics(a.metrics, b.metrics)
    end)
end)

t.describe("headless.run_batch", function()
    t.it("aggregates a batch and reports every match", function()
        local batch = headless.run_batch({ n = 3, duration = 20 })
        t.eq(#batch.matches, 3)
        t.eq(batch.agg.duration.n, 3)
        t.is_true(batch.agg.fun ~= nil, "the fun score aggregates like any metric")
        local report = headless.report(batch)
        t.is_true(report:find("fun%-proxy metrics over 3 matches") ~= nil)
        t.is_true(report:find("goals_total") ~= nil)
    end)

    t.it("forwards fixture and bot options to every match", function()
        local expected = headless.run_match({
            seed = 59,
            duration = 5,
            home = teams.orion,
            away = teams.nebula,
            home_formation = "1-2-1",
            away_formation = "1-1-2",
            tactic = tactics.counter,
            away_tactic = tactics.press_high,
            field = { w = 800, h = 450 },
            bot = "none",
        })
        local batch = headless.run_batch({
            seeds = { 59 },
            duration = 5,
            home = teams.orion,
            away = teams.nebula,
            home_formation = "1-2-1",
            away_formation = "1-1-2",
            tactic = tactics.counter,
            away_tactic = tactics.press_high,
            field = { w = 800, h = 450 },
            bot = "none",
        })

        t.eq(#batch.matches, 1)
        assert_same_metrics(batch.matches[1].metrics, expected.metrics)
    end)
end)
