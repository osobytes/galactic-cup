local t = require("spec.support.runner")
local stats = require("sim.stats")

---@param pace integer
---@param strength integer
---@param mental integer?
---@return StatBlock
local function block(pace, strength, mental)
    return {
        pace = pace,
        strength = strength,
        technique = 5,
        stamina = 5,
        mental = mental or 5,
    }
end

t.describe("stats", function()
    t.it("move_speed increases with pace without changing the established mapping", function()
        local slow = stats.move_speed(block(2, 5))
        local fast = stats.move_speed(block(8, 5))
        t.is_true(fast > slow, "faster player should have higher move speed")
        t.eq(fast, 220, "pace 8 keeps the pre-migration derived speed")
    end)

    t.it("shot_speed increases with strength without changing the established mapping", function()
        local weak = stats.shot_speed(block(5, 2))
        local strong = stats.shot_speed(block(5, 8))
        t.is_true(strong > weak, "stronger player should shoot faster")
        t.eq(strong, 550, "strength 8 keeps the pre-migration derived shot speed")
    end)

    t.it("move_speed is positive at zero pace", function()
        t.is_true(stats.move_speed(block(0, 0)) > 0)
    end)

    t.it("derives keeper reach from mental and pace", function()
        local composed = stats.keeper_reach(block(4, 5, 8))
        local unsettled = stats.keeper_reach(block(4, 5, 2))
        t.eq(composed, 78, "the migrated mental value keeps the existing reach mapping")
        t.is_true(composed > unsettled, "mental should improve derived defensive reach")
    end)
end)
