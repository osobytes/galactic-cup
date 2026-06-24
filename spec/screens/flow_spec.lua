local t = require("spec.support.runner")
local ScreenStack = require("game.screen_stack")
local Flow = require("game.flow")
local hit = require("game.ui.hit")

local VP = { w = 960, h = 540 }

-- Click a widget on the current (menu) screen by id, using its pure layout.
---@param stack ScreenStack
---@param id string
local function click(stack, id)
    local top = stack:current() --[[@as any]]
    local w = assert(hit.find(top.def.layout(top.state), id), "missing widget " .. id)
    top:event({ kind = "click", x = w.rect.x + w.rect.w / 2, y = w.rect.y + w.rect.h / 2 })
end

t.describe("pre-match flow (tier 3)", function()
    t.it("walks Squad -> Formation -> Tactic -> Match, carrying choices", function()
        local stack = ScreenStack.new()
        Flow.start(stack, VP)

        click(stack, "next") -- squad -> formation
        click(stack, "formation_1-1-2") -- choose formation
        click(stack, "next") -- formation -> tactic
        click(stack, "tactic_press_high") -- choose tactic
        click(stack, "kickoff") -- tactic -> match

        local top = stack:current() --[[@as any]]
        t.is_true(top.state ~= nil and top.state.players ~= nil, "top should be the match screen")
        t.eq(#top.state.players, 10)
        t.eq(top.state.press.home, 2) -- press_high carried through
    end)
end)
