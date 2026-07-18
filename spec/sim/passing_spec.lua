local t = require("spec.support.runner")
local passing = require("sim.passing")
local Vec2 = require("core.vec2")

local from = Vec2.new(0, 0)

t.describe("passing.target", function()
    t.it("picks the nearer of two equally aligned teammates", function()
        local mates = { Vec2.new(100, 0), Vec2.new(30, 0) }
        t.eq(passing.target(from, Vec2.new(1, 0), mates), 2)
    end)

    t.it("a tap goes short: the near man beats a far one dead on the line", function()
        local mates = {
            Vec2.new(60, 55), -- near, ~42 degrees off the aim
            Vec2.new(350, 0), -- far, dead on the aim line
        }
        t.eq(passing.target(from, Vec2.new(1, 0), mates), 1)
    end)

    t.it("a charged range picks out the far man on the line", function()
        local mates = {
            Vec2.new(60, 55), -- near, ~42 degrees off the aim
            Vec2.new(350, 0), -- far, dead on the aim line
        }
        t.eq(passing.target(from, Vec2.new(1, 0), mates, 350), 2)
    end)

    t.it("ignores teammates behind the aim direction", function()
        local mates = { Vec2.new(-50, 0) }
        t.is_true(passing.target(from, Vec2.new(1, 0), mates) == nil)
    end)

    t.it("ignores teammates outside the ~60 degree cone", function()
        local mates = { Vec2.new(10, 100) } -- ~84 degrees off the aim
        t.is_true(passing.target(from, Vec2.new(1, 0), mates) == nil)
    end)

    t.it("returns nil for a zero aim direction", function()
        t.is_true(passing.target(from, Vec2.new(0, 0), { Vec2.new(10, 0) }) == nil)
    end)
end)
