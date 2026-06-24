local t = require("spec.support.runner")
local stats = require("sim.stats")

---@param speed integer
---@param power integer
---@return StatBlock
local function block(speed, power)
    return { speed = speed, power = power, technique = 5, defense = 5, stamina = 5 }
end

t.describe("stats", function()
    t.it("move_speed increases with the speed stat", function()
        local slow = stats.move_speed(block(2, 5))
        local fast = stats.move_speed(block(8, 5))
        t.is_true(fast > slow, "faster player should have higher move speed")
    end)

    t.it("shot_speed increases with the power stat", function()
        local weak = stats.shot_speed(block(5, 2))
        local strong = stats.shot_speed(block(5, 8))
        t.is_true(strong > weak, "stronger player should shoot faster")
    end)

    t.it("move_speed is positive at zero speed", function()
        t.is_true(stats.move_speed(block(0, 0)) > 0)
    end)
end)
