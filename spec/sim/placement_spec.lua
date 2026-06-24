local t = require("spec.support.runner")
local placement = require("sim.placement")
local formations = require("data.formations")

local field = { w = 960, h = 540 }
local f = formations["2-1-1"]

t.describe("placement.anchors", function()
    t.it("produces a keeper plus four outfield anchors", function()
        t.eq(#placement.anchors(f, "home", field), 5)
    end)

    t.it("places the home keeper left of centre, away keeper right of centre", function()
        local home = placement.anchors(f, "home", field)
        local away = placement.anchors(f, "away", field)
        t.is_true(home[1].x < field.w / 2)
        t.is_true(away[1].x > field.w / 2)
    end)

    t.it("mirrors away anchors across the vertical centre line", function()
        local home = placement.anchors(f, "home", field)
        local away = placement.anchors(f, "away", field)
        for i = 1, #home do
            t.near(home[i].x + away[i].x, field.w)
            t.near(home[i].y, away[i].y)
        end
    end)
end)
