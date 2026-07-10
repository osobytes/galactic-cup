local t = require("spec.support.runner")
local headless = require("sim.headless")
local tuning = require("sim.tuning")

t.describe("headless.run_match", function()
    t.it("plays a full short match and produces sane metrics", function()
        local r = headless.run_match({ seed = 5, duration = 30 })
        local m = r.metrics
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
        for k, v in pairs(a.metrics) do
            t.near(v, b.metrics[k], 1e-12, "metric " .. k .. " must reproduce")
        end
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
end)
