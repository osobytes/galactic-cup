-- Fun-signature tripwire: a fast, deterministic snapshot of the fun-proxy
-- metrics over a fixed seed set, compared against a checked-in baseline
-- (data/fun_baseline.lua). Any sim change that moves the signature beyond
-- tolerance FAILS check.sh — the point is not to forbid drift but to force
-- the ritual: confirm the drift is intended, re-run `love . --sim 100`, log
-- the shift in docs/design/fun_metrics.md's drift log, then refresh the
-- baseline with `love . --tripwire write`.
--
-- Pure module: measurement and comparison only. File reading/writing lives
-- in main.lua (sim/ does no IO).

local headless = require("sim.headless")

local tripwire = {}

-- Seeds in the snapshot. Small enough to keep check.sh quick (~4 s), large
-- enough that the signature reflects play, not one match's quirks. The run
-- is deterministic per seed, so this is a snapshot, not a sample — tolerance
-- expresses "drift a human should acknowledge", not statistical noise.
tripwire.DEFAULT_N = 30

-- The signature: the composite, every banded metric, and normalized dribble
-- diagnostics that make proxy-vs-team-AI tool parity visible (means).
tripwire.TRACKED = {
    "fun",
    "goals_total",
    "shots_per_goal",
    "save_rate",
    "pass_completion",
    "turnovers_per_min",
    "possession_balance",
    "longest_drought_s",
    "decided_late",
    "controlled_dribble_close_share",
    "controlled_dribble_sprint_share",
    "controlled_dribble_juke_share",
    "controlled_dribble_touches_per_min",
    "controlled_dribble_heavy_losses_per_min",
    "ai_dribble_close_share",
    "ai_dribble_sprint_share",
    "ai_dribble_juke_share",
    "ai_dribble_touches_per_min",
    "ai_dribble_heavy_losses_per_min",
}

-- Allowed drift per metric: 5% of the baseline magnitude, floored so
-- near-zero baselines don't demand impossible precision.
local REL_TOL = 0.05
local ABS_TOL_FLOOR = 0.015

---@param base number
---@return number
local function tolerance(base)
    return math.max(math.abs(base) * REL_TOL, ABS_TOL_FLOOR)
end

-- Run the snapshot batch and flatten to {metric = mean}.
---@param n integer?
---@return table<string, number>, integer
function tripwire.measure(n)
    n = n or tripwire.DEFAULT_N
    local batch = headless.run_batch({ n = n })
    local out = {}
    for _, key in ipairs(tripwire.TRACKED) do
        local a = batch.agg[key]
        out[key] = a and a.mean or 0
    end
    return out, n
end

---@class TripwireRow
---@field key string
---@field base number
---@field cur number
---@field delta number
---@field tol number
---@field ok boolean

-- Compare a measured signature against the baseline table.
---@param baseline table<string, number>  -- from data/fun_baseline.lua
---@param current table<string, number>  -- from tripwire.measure
---@return boolean ok, TripwireRow[] rows
function tripwire.compare(baseline, current)
    local ok = true
    local rows = {}
    for _, key in ipairs(tripwire.TRACKED) do
        local base = baseline[key] or 0
        local cur = current[key] or 0
        local tol = tolerance(base)
        local row_ok = math.abs(cur - base) <= tol
        ok = ok and row_ok
        rows[#rows + 1] = {
            key = key,
            base = base,
            cur = cur,
            delta = cur - base,
            tol = tol,
            ok = row_ok,
        }
    end
    return ok, rows
end

---@param rows TripwireRow[]
---@param ok boolean
---@param n integer
---@return string
function tripwire.report(rows, ok, n)
    local lines = {
        ("fun tripwire: %d seeded matches vs data/fun_baseline.lua"):format(n),
        ("%-20s %9s %9s %9s %7s"):format("metric", "base", "now", "delta", "tol"),
    }
    for _, r in ipairs(rows) do
        lines[#lines + 1] = ("%-20s %9.3f %9.3f %+9.3f %7.3f  %s"):format(
            r.key,
            r.base,
            r.cur,
            r.delta,
            r.tol,
            r.ok and "ok" or "DRIFT"
        )
    end
    if ok then
        lines[#lines + 1] = "TRIPWIRE OK"
    else
        lines[#lines + 1] = "TRIPWIRE DRIFT — if intended: re-run `love . --sim 100`, log the"
        lines[#lines + 1] = "shift in docs/design/fun_metrics.md (drift log), then refresh with"
        lines[#lines + 1] = "`love . --tripwire write`."
    end
    return table.concat(lines, "\n")
end

-- Baseline file content (data/fun_baseline.lua). Stable order, regenerable.
---@param current table<string, number>
---@param n integer
---@return string
function tripwire.serialize(current, n)
    local lines = {
        "-- Fun-signature tripwire baseline. REGENERATE, don't hand-edit:",
        "--   love . --tripwire write",
        "-- ...and only after confirming the drift is intended, re-running",
        "-- `love . --sim 100`, and logging the shift in the drift log of",
        "-- docs/design/fun_metrics.md.",
        "return {",
        ("    n = %d,"):format(n),
    }
    for _, key in ipairs(tripwire.TRACKED) do
        lines[#lines + 1] = ("    %s = %.6f,"):format(key, current[key] or 0)
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

return tripwire
