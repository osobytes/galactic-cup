-- Headless match batches: play unattended seeded matches with the human-proxy
-- bot on the controlled slot and fold each into fun-proxy metrics
-- (sim/metrics.lua). Pure — no love, no I/O; `report` returns a string and the
-- caller decides where it goes. Entry point: `love . --sim [n]` in main.lua.

local match = require("sim.match")
local bot = require("sim.bot")
local metrics = require("sim.metrics")
local tuning = require("sim.tuning")
local teams = require("data.teams")

local headless = {}

local FIELD = { w = 960, h = 540 } -- the real game's pitch (game/screens/match.lua)
local DT = 1 / 60 -- fixed step: matches the game loop, keeps runs reproducible
local DEFAULT_DURATION = 120
local DEFAULT_MAX_GOALS = 3
local MAX_STEPS_SLACK = 600 -- overtime guard: a stuck sim must not hang the batch

---@class HeadlessOpts
---@field seed number
---@field duration number?
---@field max_goals integer?
---@field reaction number?  -- bot latency override
---@field tuning_blob string?  -- knob overrides in sim/tuning serialize format

---@class MatchResult
---@field seed number
---@field metrics MatchMetrics  -- includes `fun` (the composite score)
---@field desirability table<string, number>  -- per-banded-metric 0..1

-- Play one full match and measure it. Applies `tuning_blob` on top of the
-- defaults for the run and restores the previous knob values afterwards, so
-- batches never leak balance state into the live game or other configs.
---@param opts HeadlessOpts
---@return MatchResult
function headless.run_match(opts)
    local saved = opts.tuning_blob ~= nil and tuning.serialize() or nil
    if opts.tuning_blob then
        tuning.deserialize(opts.tuning_blob)
    end

    local s = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = FIELD.w, h = FIELD.h },
        duration = opts.duration or DEFAULT_DURATION,
        max_goals = opts.max_goals or DEFAULT_MAX_GOALS,
        seed = opts.seed,
    })
    local b = bot.new({ seed = opts.seed, reaction = opts.reaction })
    local c = metrics.new(s)

    local max_steps = math.ceil((opts.duration or DEFAULT_DURATION) / DT) + MAX_STEPS_SLACK
    for _ = 1, max_steps do
        if s.finished then
            break
        end
        match.step(s, DT, bot.input(b, s, DT))
        metrics.observe(c, s, DT)
    end

    if saved ~= nil then
        tuning.deserialize(saved)
    end

    local m = metrics.finish(c, s)
    local fun, per = metrics.fun_score(m)
    m.fun = fun
    return { seed = opts.seed, metrics = m, desirability = per }
end

---@class BatchOpts
---@field n integer?  -- number of matches (seeds 1..n) when `seeds` not given
---@field seeds number[]?
---@field duration number?
---@field max_goals integer?
---@field reaction number?
---@field tuning_blob string?

---@class BatchResult
---@field matches MatchResult[]
---@field agg table<string, MetricStats>

-- Play a batch over a fixed seed set. Compare knob configs on the SAME seeds
-- (common random numbers): differences then come from the knobs, not luck.
---@param opts BatchOpts
---@return BatchResult
function headless.run_batch(opts)
    local seeds = opts.seeds
    if not seeds then
        seeds = {}
        for i = 1, opts.n or 20 do
            seeds[i] = i
        end
    end
    local matches, all = {}, {}
    for _, seed in ipairs(seeds) do
        local r = headless.run_match({
            seed = seed,
            duration = opts.duration,
            max_goals = opts.max_goals,
            reaction = opts.reaction,
            tuning_blob = opts.tuning_blob,
        })
        matches[#matches + 1] = r
        all[#all + 1] = r.metrics
    end
    return { matches = matches, agg = metrics.aggregate(all) }
end

-- Display order: the banded fun-proxy metrics first, context counts after.
local REPORT_ROWS = {
    "fun",
    "goals_total",
    "shots_per_goal",
    "save_rate",
    "pass_completion",
    "turnovers_per_min",
    "possession_balance",
    "longest_drought_s",
    "decided_late",
    "lead_changes",
    "margin",
    "shots",
    "passes",
    "duration",
}

---@param batch BatchResult
---@return string
function headless.report(batch)
    local out = {}
    local n = #batch.matches
    -- Mean per-metric desirability across the batch: when the fun score is
    -- low, this column names the dimension that collapsed.
    local desir = {}
    for _, r in ipairs(batch.matches) do
        for k, d in pairs(r.desirability) do
            desir[k] = desir[k] or { sum = 0, n = 0 }
            desir[k].sum = desir[k].sum + d
            desir[k].n = desir[k].n + 1
        end
    end
    out[#out + 1] = ("fun-proxy metrics over %d matches (mean +/- sd [min .. max])"):format(n)
    out[#out + 1] = ("%-20s %10s %9s %9s %9s %7s  %s"):format(
        "metric",
        "mean",
        "sd",
        "min",
        "max",
        "desir",
        "band"
    )
    for _, key in ipairs(REPORT_ROWS) do
        local st = batch.agg[key]
        if st then
            local band = metrics.bands[key]
            local band_str = band and ("[%g .. %g]"):format(band[2], band[3]) or ""
            local d = desir[key]
            local d_str = d and ("%7.2f"):format(d.sum / d.n) or ("%7s"):format("-")
            local miss = st.n < n and (" (n=%d)"):format(st.n) or ""
            out[#out + 1] = ("%-20s %10.3f %9.3f %9.3f %9.3f %s  %s%s"):format(
                key,
                st.mean,
                st.sd,
                st.min,
                st.max,
                d_str,
                band_str,
                miss
            )
        end
    end
    return table.concat(out, "\n")
end

return headless
