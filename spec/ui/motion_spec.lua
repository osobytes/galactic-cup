local motion = require("game.ui.motion")
local t = require("spec.support.runner")

t.describe("UI route motion", function()
    t.it("finishes quickly and never exceeds its normalized range", function()
        local progress = 0
        for _ = 1, 12 do
            progress = motion.advance(progress, 1 / 60)
        end
        t.eq(progress, 1)
        t.eq(motion.advance(progress, 1), 1)
        t.eq(motion.advance(0.5, -1), 0.5)
    end)

    t.it("reveals the full canvas from left to right", function()
        local x0, width0 = motion.wipe(0, 960)
        local x1, width1 = motion.wipe(1, 960)
        t.eq(x0, 0)
        t.eq(width0, 960)
        t.eq(x1, 960)
        t.eq(width1, 0)
    end)
end)
