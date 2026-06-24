local t = require("spec.support.runner")
local tactic = require("game.screens.tactic")
local hit = require("game.ui.hit")

local VP = { w = 960, h = 540 }

---@param layout Layout
---@param id string
---@return InputEvent
local function click_on(layout, id)
    local w = assert(hit.find(layout, id), "missing widget " .. id)
    return { kind = "click", x = w.rect.x + w.rect.w / 2, y = w.rect.y + w.rect.h / 2 }
end

t.describe("tactic screen", function()
    t.it("defaults to balanced and offers all three tactics", function()
        local s = tactic.new_state(VP)
        t.eq(s.selected, "balanced")
        local layout = tactic.layout(s)
        t.is_true(hit.find(layout, "tactic_balanced") ~= nil)
        t.is_true(hit.find(layout, "tactic_press_high") ~= nil)
        t.is_true(hit.find(layout, "tactic_counter") ~= nil)
    end)

    t.it("selects the clicked tactic", function()
        local s = tactic.new_state(VP)
        local s2 = tactic.update(s, click_on(tactic.layout(s), "tactic_press_high"))
        t.eq(s2.selected, "press_high")
    end)

    t.it("emits a match transition carrying the tactic on Kick Off", function()
        local s = tactic.new_state(VP)
        s = tactic.update(s, click_on(tactic.layout(s), "tactic_counter"))
        local _, action = tactic.update(s, click_on(tactic.layout(s), "kickoff"))
        action = assert(action, "expected a transition action")
        t.eq(action.go, "match")
        t.eq(action.tactic, "counter")
    end)
end)
