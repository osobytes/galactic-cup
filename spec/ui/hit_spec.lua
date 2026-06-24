local t = require("spec.support.runner")
local hit = require("game.ui.hit")

---@type Layout
local layout = {
    { id = "a", rect = { x = 0, y = 0, w = 100, h = 50 } },
    { id = "b", rect = { x = 0, y = 0, w = 40, h = 40 } }, -- overlaps a, drawn later
    { id = "c", rect = { x = 200, y = 200, w = 30, h = 30 } },
}

t.describe("hit.at", function()
    t.it("returns the topmost widget under the point", function()
        t.eq(hit.at(layout, 10, 10), "b") -- b is later in the list -> on top
    end)

    t.it("returns the lower widget where only it covers the point", function()
        t.eq(hit.at(layout, 80, 10), "a")
    end)

    t.it("returns nil when nothing is hit", function()
        t.is_true(hit.at(layout, 500, 500) == nil)
    end)
end)

t.describe("hit.find", function()
    t.it("finds a widget by id", function()
        t.eq(hit.find(layout, "c").id, "c")
    end)

    t.it("returns nil for an unknown id", function()
        t.is_true(hit.find(layout, "zzz") == nil)
    end)
end)
