local t = require("spec.support.runner")
local sweep = require("sim.sweep")
local tuning = require("sim.tuning")

t.describe("sweep.paired_delta", function()
    t.it("computes the mean per-seed difference and its standard error", function()
        local d = sweep.paired_delta({ 0.2, 0.4, 0.6 }, { 0.3, 0.5, 0.7 })
        t.near(d.mean, 0.1, 1e-9)
        t.near(d.se, 0, 1e-9, "constant shift has zero spread")
        local d2 = sweep.paired_delta({ 0, 0 }, { 0.1, 0.3 })
        t.near(d2.mean, 0.2, 1e-9)
        t.is_true(d2.se > 0)
    end)
end)

t.describe("sweep.sensitivity", function()
    t.it("perturbs a knob to min/max and restores the defaults after", function()
        tuning.reset()
        local r = sweep.sensitivity({
            seeds = { 1, 2 },
            keys = { "AI_SHOOT_RANGE" },
            duration = 10,
        })
        t.eq(#r.rows, 1)
        t.eq(r.rows[1].key, "AI_SHOOT_RANGE")
        t.is_true(r.rows[1].impact >= 0)
        t.is_true(tuning.is_default("AI_SHOOT_RANGE"), "knobs restored after the sweep")
        local report = sweep.sensitivity_report(r)
        t.is_true(report:find("AI_SHOOT_RANGE") ~= nil)
    end)
end)

t.describe("sweep.parse_blob", function()
    t.it("round-trips the tuning blob line format, skipping junk", function()
        local o =
            sweep.parse_blob("AI_SHOOT_RANGE=300\nNOT_A_KNOB=5\ngarbage line\nJOCKEY_SLOW=0.6")
        t.eq(o.AI_SHOOT_RANGE, 300)
        t.eq(o.JOCKEY_SLOW, 0.6)
        t.is_true(o.NOT_A_KNOB == nil)
    end)
end)

t.describe("sweep.ascend", function()
    t.it("warm-starts from given overrides and still reports delta vs defaults", function()
        tuning.reset()
        local r = sweep.ascend({
            keys = { "AI_SHOOT_RANGE" },
            seeds = { 1, 2 },
            levels = 2,
            passes = 1,
            duration = 10,
            start = { AI_SHOOT_RANGE = 300 },
        })
        t.is_true(r.overrides.AI_SHOOT_RANGE ~= nil, "the start override is in play")
        t.is_true(tuning.is_default("AI_SHOOT_RANGE"), "knobs restored after the search")
    end)

    t.it("only accepts strict improvements and reports the winning blob", function()
        tuning.reset()
        local r = sweep.ascend({
            keys = { "AI_SHOOT_RANGE" },
            seeds = { 1, 2 },
            levels = 3,
            passes = 1,
            duration = 10,
        })
        t.is_true(r.delta.mean >= 0, "greedy ascent never ends below its baseline")
        for key, v in pairs(r.overrides) do
            local k = tuning.by_key[key]
            t.is_true(v >= k.min and v <= k.max, key .. " stays in range")
        end
        t.is_true(tuning.is_default("AI_SHOOT_RANGE"), "knobs restored after the search")
    end)
end)
