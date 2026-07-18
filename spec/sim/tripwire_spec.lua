local t = require("spec.support.runner")
local tripwire = require("sim.tripwire")

-- A signature table covering every tracked metric, offset by `bump` on `key`.
---@param bump number?
---@param key string?
---@return table<string, number>
local function signature(bump, key)
    local sig = {}
    for i, k in ipairs(tripwire.TRACKED) do
        sig[k] = i * 0.5
    end
    if key then
        sig[key] = sig[key] + (bump or 0)
    end
    return sig
end

t.describe("sim.tripwire", function()
    t.it("pins normalized controlled-vs-AI dribble diagnostics", function()
        local tracked = {}
        for _, key in ipairs(tripwire.TRACKED) do
            tracked[key] = true
        end
        t.is_true(tracked.controlled_dribble_sprint_share)
        t.is_true(tracked.controlled_dribble_touches_per_min)
        t.is_true(tracked.ai_dribble_sprint_share)
        t.is_true(tracked.ai_dribble_touches_per_min)
    end)

    t.it("passes when the signature matches the baseline", function()
        local ok, rows = tripwire.compare(signature(), signature())
        t.is_true(ok, "identical signatures pass")
        t.eq(#rows, #tripwire.TRACKED)
        for _, r in ipairs(rows) do
            t.is_true(r.ok, r.key .. " row ok")
        end
    end)

    t.it("tolerates drift inside the tolerance band", function()
        -- fun baseline is 0.5 here; 5% = 0.025 tolerance.
        local ok = tripwire.compare(signature(), signature(0.02, "fun"))
        t.is_true(ok, "sub-tolerance drift passes")
    end)

    t.it("fails when one metric drifts beyond tolerance", function()
        local ok, rows = tripwire.compare(signature(), signature(0.1, "fun"))
        t.is_true(not ok, "a drifted metric fails the whole check")
        local drifted = 0
        for _, r in ipairs(rows) do
            if not r.ok then
                drifted = drifted + 1
                t.eq(r.key, "fun")
            end
        end
        t.eq(drifted, 1, "only the drifted metric is flagged")
    end)

    t.it("reports DRIFT rows and refresh instructions", function()
        local ok, rows = tripwire.compare(signature(), signature(0.1, "fun"))
        local rep = tripwire.report(rows, ok, 30)
        t.is_true(rep:find("DRIFT") ~= nil, "report names the drift")
        t.is_true(rep:find("tripwire write", 1, true) ~= nil, "and how to refresh")
    end)

    t.it("serializes a loadable baseline covering every tracked metric", function()
        local sig = signature()
        local chunk = tripwire.serialize(sig, 30)
        local loaded = assert(loadstring(chunk))()
        t.eq(loaded.n, 30)
        for _, k in ipairs(tripwire.TRACKED) do
            t.near(loaded[k], sig[k], 1e-5, k .. " round-trips")
        end
    end)
end)
