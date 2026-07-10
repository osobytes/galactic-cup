-- Knob-space exploration over headless batches: per-knob sensitivity sweeps
-- and greedy coordinate ascent toward higher fun scores. Pure — no love, no
-- I/O; long runs report progress through an injected `log` callback and every
-- result comes back as data + a formatted report string.
--
-- Statistics: every config is evaluated on the SAME seed set (common random
-- numbers), so config effects are paired per seed — deltas are mean paired
-- difference +/- their standard error, not a comparison of noisy means.

local headless = require("sim.headless")
local tuning = require("sim.tuning")

local sweep = {}

---@class ConfigEval
---@field blob string
---@field agg table<string, MetricStats>
---@field funs number[]  -- per-seed fun scores, seed order

---@class PairedDelta
---@field mean number  -- mean per-seed difference (config - reference)
---@field se number  -- standard error of that mean

---@param overrides table<string, number>  -- knob key -> value (defaults omitted)
---@return string blob
local function blob_of(overrides)
    local lines = {}
    for _, k in ipairs(tuning.knobs) do -- registry order: stable blobs
        local v = overrides[k.key]
        if v ~= nil and v ~= k.default then
            lines[#lines + 1] = ("%s=%.6g"):format(k.key, v)
        end
    end
    return table.concat(lines, "\n")
end

-- Parse a serialized tuning blob back into a knob->value table (the inverse
-- of blob_of, same line format as sim/tuning.lua). Unknown keys are skipped.
---@param blob string
---@return table<string, number>
function sweep.parse_blob(blob)
    local overrides = {}
    for line in tostring(blob):gmatch("[^\r\n]+") do
        local key, num = line:match("^([%w_]+)=([%-%d%.eE]+)$")
        local v = key and tonumber(num)
        if v and tuning.by_key[key] then
            overrides[key] = v
        end
    end
    return overrides
end

---@param blob string
---@param seeds number[]
---@param duration number?  -- shorter matches for tests; nil = the real 120 s
---@return ConfigEval
function sweep.evaluate(blob, seeds, duration)
    local batch = headless.run_batch({ seeds = seeds, tuning_blob = blob, duration = duration })
    local funs = {}
    for i, r in ipairs(batch.matches) do
        funs[i] = r.metrics.fun or 0
    end
    return { blob = blob, agg = batch.agg, funs = funs }
end

---@param ref number[]  -- reference per-seed fun scores
---@param funs number[]  -- same seeds, candidate config
---@return PairedDelta
function sweep.paired_delta(ref, funs)
    local n = #funs
    local diffs, sum = {}, 0
    for i = 1, n do
        diffs[i] = funs[i] - ref[i]
        sum = sum + diffs[i]
    end
    local mean = sum / n
    local var = 0
    for _, d in ipairs(diffs) do
        var = var + (d - mean) ^ 2
    end
    local se = n > 1 and math.sqrt(var / (n - 1) / n) or 0
    return { mean = mean, se = se }
end

---@class SensitivityRow
---@field key string
---@field lo_delta PairedDelta  -- knob at its min
---@field hi_delta PairedDelta  -- knob at its max
---@field lo_goals number  -- mean goals_total at min (context for the weak metric)
---@field hi_goals number
---@field impact number  -- max(|lo|, |hi|): the ranking key

---@class SensitivityResult
---@field baseline ConfigEval
---@field rows SensitivityRow[]  -- sorted by impact, largest first

-- Perturb every knob (or `opts.keys`) to its min and max, one at a time.
---@param opts { seeds: number[], keys: string[]?, duration: number?, log: fun(msg: string)? }
---@return SensitivityResult
function sweep.sensitivity(opts)
    local log = opts.log or function() end
    local keys = opts.keys
    if not keys then
        keys = {}
        for _, k in ipairs(tuning.knobs) do
            keys[#keys + 1] = k.key
        end
    end

    log(("sensitivity: baseline over %d seeds"):format(#opts.seeds))
    local baseline = sweep.evaluate("", opts.seeds, opts.duration)

    local rows = {}
    for i, key in ipairs(keys) do
        local k = assert(tuning.by_key[key], "unknown knob: " .. key)
        log(("sensitivity: %d/%d %s"):format(i, #keys, key))
        local lo = sweep.evaluate(blob_of({ [key] = k.min }), opts.seeds, opts.duration)
        local hi = sweep.evaluate(blob_of({ [key] = k.max }), opts.seeds, opts.duration)
        local lo_d = sweep.paired_delta(baseline.funs, lo.funs)
        local hi_d = sweep.paired_delta(baseline.funs, hi.funs)
        rows[#rows + 1] = {
            key = key,
            lo_delta = lo_d,
            hi_delta = hi_d,
            lo_goals = lo.agg.goals_total.mean,
            hi_goals = hi.agg.goals_total.mean,
            impact = math.max(math.abs(lo_d.mean), math.abs(hi_d.mean)),
        }
    end
    table.sort(rows, function(a, b)
        return a.impact > b.impact
    end)
    return { baseline = baseline, rows = rows }
end

---@param r SensitivityResult
---@return string
function sweep.sensitivity_report(r)
    local base_fun = 0
    for _, f in ipairs(r.baseline.funs) do
        base_fun = base_fun + f
    end
    base_fun = base_fun / #r.baseline.funs
    local out = {}
    out[#out + 1] = ("sensitivity over %d seeds — baseline fun %.3f, goals %.2f"):format(
        #r.baseline.funs,
        base_fun,
        r.baseline.agg.goals_total.mean
    )
    out[#out + 1] = ("%-22s %8s %8s | %8s %8s | %7s %7s"):format(
        "knob (min..max)",
        "dFun@min",
        "+/-se",
        "dFun@max",
        "+/-se",
        "gls@min",
        "gls@max"
    )
    for _, row in ipairs(r.rows) do
        out[#out + 1] = ("%-22s %+8.3f %8.3f | %+8.3f %8.3f | %7.2f %7.2f"):format(
            row.key,
            row.lo_delta.mean,
            row.lo_delta.se,
            row.hi_delta.mean,
            row.hi_delta.se,
            row.lo_goals,
            row.hi_goals
        )
    end
    return table.concat(out, "\n")
end

-- Evenly spaced candidate values across a knob's range, snapped to its step.
---@param k Knob
---@param levels integer
---@return number[]
local function level_values(k, levels)
    local vals, seen = {}, {}
    for i = 0, levels - 1 do
        local v = k.min + (k.max - k.min) * i / (levels - 1)
        v = k.min + math.floor((v - k.min) / k.step + 0.5) * k.step
        v = math.max(k.min, math.min(k.max, v))
        if not seen[v] then
            seen[v] = true
            vals[#vals + 1] = v
        end
    end
    return vals
end

---@class AscentResult
---@field overrides table<string, number>  -- the winning non-default knob values
---@field blob string
---@field eval ConfigEval  -- winning config on the search seeds
---@field delta PairedDelta  -- vs the default-knob baseline, search seeds
---@field trace string[]  -- accepted moves, in order

-- Greedy coordinate ascent on mean fun: sweep each knob through `levels`
-- values, keep any strict improvement, repeat for `passes`. Deterministic
-- (fixed seeds ⇒ same result every run) but greedy — it finds a good ridge,
-- not a proven optimum, and it can overfit the search seeds: always re-check
-- the result on held-out seeds (sweep.evaluate with fresh seeds).
-- `start` warm-starts from known-good overrides (e.g. a prior round's
-- candidate); the reported delta stays vs the DEFAULTS baseline either way.
---@param opts { keys: string[], seeds: number[], levels: integer?, passes: integer?, duration: number?, start: table<string, number>?, log: fun(msg: string)? }
---@return AscentResult
function sweep.ascend(opts)
    local log = opts.log or function() end
    local levels = opts.levels or 5
    local passes = opts.passes or 2

    local baseline = sweep.evaluate("", opts.seeds, opts.duration)
    local overrides = {}
    for key, v in pairs(opts.start or {}) do
        assert(tuning.by_key[key], "unknown start knob: " .. key)
        overrides[key] = v
    end
    local best = next(overrides) ~= nil
            and sweep.evaluate(blob_of(overrides), opts.seeds, opts.duration)
        or baseline
    local best_mean = 0
    for _, f in ipairs(best.funs) do
        best_mean = best_mean + f
    end
    best_mean = best_mean / #best.funs
    log(("ascent: start fun %.3f over %d seeds"):format(best_mean, #opts.seeds))

    local trace = {}
    for pass = 1, passes do
        for _, key in ipairs(opts.keys) do
            local k = assert(tuning.by_key[key], "unknown knob: " .. key)
            local current = overrides[key] or k.default
            for _, v in ipairs(level_values(k, levels)) do
                if v ~= current then
                    local trial = { [key] = v }
                    for ok, ov in pairs(overrides) do
                        if ok ~= key then
                            trial[ok] = ov
                        end
                    end
                    local eval = sweep.evaluate(blob_of(trial), opts.seeds, opts.duration)
                    local mean = 0
                    for _, f in ipairs(eval.funs) do
                        mean = mean + f
                    end
                    mean = mean / #eval.funs
                    if mean > best_mean then
                        best, best_mean = eval, mean
                        overrides = trial
                        current = v
                        local move = ("pass %d: %s=%g -> fun %.3f"):format(pass, key, v, mean)
                        trace[#trace + 1] = move
                        log("ascent: " .. move)
                    end
                end
            end
        end
    end

    return {
        overrides = overrides,
        blob = blob_of(overrides),
        eval = best,
        delta = sweep.paired_delta(baseline.funs, best.funs),
        trace = trace,
    }
end

return sweep
