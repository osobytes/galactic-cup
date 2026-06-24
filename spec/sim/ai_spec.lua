local t = require("spec.support.runner")
local ai = require("sim.ai")
local Vec2 = require("core.vec2")

t.describe("ai.closest", function()
    t.it("returns the index of the nearest position", function()
        local ps = { Vec2.new(10, 0), Vec2.new(3, 0), Vec2.new(20, 0) }
        t.eq(ai.closest(Vec2.new(0, 0), ps), 2)
    end)

    t.it("honours the exclude index", function()
        local ps = { Vec2.new(1, 0), Vec2.new(5, 0) }
        t.eq(ai.closest(Vec2.new(0, 0), ps, 1), 2)
    end)

    t.it("returns nil when there are no candidates", function()
        t.is_true(ai.closest(Vec2.new(0, 0), {}) == nil)
    end)
end)

t.describe("ai.steer", function()
    t.it("snaps to the target when within range", function()
        local np, dir = ai.steer(Vec2.new(0, 0), Vec2.new(3, 0), 10)
        t.eq(np.x, 3)
        t.eq(np.y, 0)
        t.near(dir:length(), 1)
    end)

    t.it("moves at most max_dist toward the target", function()
        local np = ai.steer(Vec2.new(0, 0), Vec2.new(100, 0), 10)
        t.near(np.x, 10)
    end)

    t.it("yields a zero direction when already at the target", function()
        local _, dir = ai.steer(Vec2.new(5, 5), Vec2.new(5, 5), 10)
        t.eq(dir.x, 0)
        t.eq(dir.y, 0)
    end)
end)
