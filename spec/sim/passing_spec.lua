local t = require("spec.support.runner")
local passing = require("sim.passing")
local Vec2 = require("core.vec2")

local from = Vec2.new(0, 0)

t.describe("passing.target", function()
    t.it("picks the nearest teammate within the aim cone", function()
        local mates = { Vec2.new(100, 0), Vec2.new(30, 0) }
        t.eq(passing.target(from, Vec2.new(1, 0), mates), 2)
    end)

    t.it("ignores teammates behind the aim direction", function()
        local mates = { Vec2.new(-50, 0) }
        t.is_true(passing.target(from, Vec2.new(1, 0), mates) == nil)
    end)

    t.it("returns nil for a zero aim direction", function()
        t.is_true(passing.target(from, Vec2.new(0, 0), { Vec2.new(10, 0) }) == nil)
    end)
end)
