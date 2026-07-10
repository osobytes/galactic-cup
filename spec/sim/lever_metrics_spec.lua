local t = require("spec.support.runner")
local lever_metrics = require("sim.lever_metrics")
local presets = require("data.tuning_presets")
local tactics = require("data.tactics")
local teams = require("data.teams")

---@param id string
---@return string
local function preset_blob(id)
    for _, preset in ipairs(presets) do
        if preset.id == id then
            return preset.blob
        end
    end
    assert(false, "missing preset: " .. id)
    return ""
end

---@param n integer
---@return number[]
local function seed_set(n)
    local seeds = {}
    for i = 1, n do
        seeds[i] = i
    end
    return seeds
end

local candidate_a = preset_blob("candidate_a")
local base = {
    home = teams.nebula,
    away = teams.orion,
    away_tactic = tactics.balanced,
    bot = "none",
    tuning_blob = candidate_a,
}
local press = {
    home = teams.nebula,
    away = teams.orion,
    tactic = tactics.press_high,
    away_tactic = tactics.balanced,
    bot = "none",
    tuning_blob = candidate_a,
}
local counter = {
    home = teams.nebula,
    away = teams.orion,
    tactic = tactics.counter,
    away_tactic = tactics.balanced,
    bot = "none",
    tuning_blob = candidate_a,
}

---@param a LeverLivenessResult
---@param b LeverLivenessResult
local function assert_same_result(a, b)
    t.near(a.dwin_pts, b.dwin_pts, 1e-12)
    t.eq(a.win_in_band, b.win_in_band)
    t.eq(a.passes, b.passes)
    t.eq(#a.metric_deltas, #b.metric_deltas)
    t.eq(#a.moved_metrics, #b.moved_metrics)
    for i, delta in ipairs(a.metric_deltas) do
        local other = b.metric_deltas[i]
        t.eq(delta.key, other.key)
        t.eq(delta.n, other.n)
        t.near(delta.band_widths, other.band_widths, 1e-12)
    end
end

t.describe("lever_metrics.lever_liveness", function()
    t.it("rejects an identical-fixture placebo", function()
        local result = lever_metrics.lever_liveness(base, base, seed_set(12))
        t.near(result.dwin_pts, 0, 1e-12)
        t.eq(#result.moved_metrics, 0)
        t.is_true(not result.passes)
    end)

    t.it("registers outcome and banded-metric movement for a real tactic lever", function()
        -- Thirty full matches per option make this fixture-level integration
        -- assertion resistant to a single anomalous seed while staying cheap.
        local result = lever_metrics.lever_liveness(press, counter, seed_set(30))
        t.is_true(math.abs(result.dwin_pts) > 0, "different tactics must move home win share")
        t.is_true(#result.moved_metrics > 0, "different tactics must move a banded metric")
    end)

    t.it("repeats deterministically on the same common seed set", function()
        local seeds = seed_set(16)
        local a = lever_metrics.lever_liveness(press, counter, seeds)
        local b = lever_metrics.lever_liveness(press, counter, seeds)
        assert_same_result(a, b)
    end)
end)
