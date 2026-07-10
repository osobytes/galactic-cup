local t = require("spec.support.runner")
local headless = require("sim.headless")
local match = require("sim.match")
local bot = require("sim.bot")
local tuning = require("sim.tuning")
local players = require("data.players")
local teams = require("data.teams")
local tactics = require("data.tactics")

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

    t.it("preserves the historical fixture and home bot on the default path", function()
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

    t.it(
        "runs a non-default fixture with formation, tactic, roster, and field overrides",
        function()
            local by_id = players_by_id()
            local keeper = by_id.gax_oru
            by_id.gax_oru = {
                id = keeper.id,
                name = "Harness Gax",
                planet = keeper.planet,
                position = keeper.position,
                species = keeper.species,
                stats = keeper.stats,
                trait = keeper.trait,
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
