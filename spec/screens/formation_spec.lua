local t = require("spec.support.runner")
local formation = require("game.screens.formation")
local hit = require("game.ui.hit")

local VP = { w = 960, h = 540 }

---@param layout Layout
---@param id string
---@return InputEvent
local function click_on(layout, id)
    local w = assert(hit.find(layout, id), "missing widget " .. id)
    return { kind = "click", x = w.rect.x + w.rect.w / 2, y = w.rect.y + w.rect.h / 2 }
end

t.describe("formation screen", function()
    t.it("defaults to 2-1-1 and offers all three formations", function()
        local s = formation.new_state(VP)
        t.eq(s.selected, "2-1-1")
        local layout = formation.layout(s)
        t.is_true(hit.find(layout, "formation_2-1-1") ~= nil)
        t.is_true(hit.find(layout, "formation_1-2-1") ~= nil)
        t.is_true(hit.find(layout, "formation_1-1-2") ~= nil)
    end)

    t.it("selects the clicked formation", function()
        local s = formation.new_state(VP)
        local s2 = formation.update(s, click_on(formation.layout(s), "formation_1-1-2"))
        t.eq(s2.selected, "1-1-2")
    end)

    t.it("emits a tactic transition carrying the selection on Next", function()
        local s = formation.new_state(VP)
        s = formation.update(s, click_on(formation.layout(s), "formation_1-2-1"))
        local _, action = formation.update(s, click_on(formation.layout(s), "next"))
        action = assert(action, "expected a transition action")
        t.eq(action.go, "tactic")
        t.eq(action.formation, "1-2-1")
    end)

    t.it("does nothing when clicking empty space", function()
        local s = formation.new_state(VP)
        local _, action = formation.update(s, { kind = "click", x = 5, y = 5 })
        t.is_true(action == nil)
    end)
end)
