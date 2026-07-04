local t = require("spec.support.runner")
local rng = require("core.rng")

t.describe("core.rng", function()
    t.it("is reproducible: same seed, same sequence", function()
        local a, b = rng.seed(123), rng.seed(123)
        for _ = 1, 10 do
            local xa, xb
            a, xa = rng.roll(a)
            b, xb = rng.roll(b)
            t.eq(xa, xb)
        end
    end)

    t.it("samples stay in [0, 1) and vary", function()
        local s = rng.seed(7)
        local seen = {}
        for _ = 1, 100 do
            local x
            s, x = rng.roll(s)
            t.is_true(x >= 0 and x < 1, "sample in range")
            seen[x] = true
        end
        local n = 0
        for _ in pairs(seen) do
            n = n + 1
        end
        t.is_true(n > 90, "samples do not repeat degenerately")
    end)

    t.it("is roughly uniform", function()
        local s = rng.seed(99)
        local sum = 0
        for _ = 1, 2000 do
            local x
            s, x = rng.roll(s)
            sum = sum + x
        end
        local mean = sum / 2000
        t.is_true(mean > 0.45 and mean < 0.55, "mean near 0.5, got " .. mean)
    end)

    t.it("normalizes degenerate seeds", function()
        t.is_true(rng.seed(0) >= 1)
        t.is_true(rng.seed(-5) >= 1)
        t.is_true(rng.seed(2147483647 * 3 + 0.7) >= 1)
    end)
end)
