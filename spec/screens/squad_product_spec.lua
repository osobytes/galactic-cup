local hit = require("game.ui.hit")
local squad = require("game.screens.squad")
local t = require("spec.support.runner")

local VP = { w = 960, h = 540 }

---@param state SquadScreenState
---@param id string
---@return SquadScreenState, table?
local function click(state, id)
    local widget = assert(hit.find(squad.layout(state), id), "missing widget " .. id)
    return squad.update(state, {
        kind = "click",
        x = widget.rect.x + widget.rect.w / 2,
        y = widget.rect.y + widget.rect.h / 2,
        button = 1,
    })
end

t.describe("product squad picker", function()
    t.it("shows eight authored cards and starts with a valid five", function()
        local state = squad.new_state(VP)
        t.eq(#state.roster, 8)
        t.eq(#state.selected_ids, 5)
        local layout = squad.layout(state)
        for _, player in ipairs(state.roster) do
            local card = assert(hit.find(layout, "player_" .. player.id))
            t.eq(card.kind, "card")
            t.is_true(assert(card.text):match("PAC") ~= nil)
            t.is_true(card.data.accent ~= nil)
            t.is_true(card.data.species_shape ~= nil)
        end
    end)

    t.it("locks the keeper and supports an explicit outfielder replacement", function()
        local state = squad.new_state(VP)
        state = click(state, "player_ozzo")
        t.eq(#state.selected_ids, 5)
        t.is_true(state.message:match("keeper") ~= nil)

        state = click(state, "player_brakka")
        t.eq(#state.selected_ids, 4)
        state = click(state, "player_tib_quell")
        t.eq(#state.selected_ids, 5)
        local _, action = click(state, "next")
        action = assert(action)
        t.eq(action.go, "formation")
        t.eq(#action.starter_ids, 5)
    end)

    t.it("does not activate disabled continuation or static labels", function()
        local state = squad.new_state(VP)
        state = click(state, "player_brakka")
        local unchanged, action = click(state, "next")
        t.is_true(action == nil)
        t.eq(#unchanged.selected_ids, 4)

        local message = assert(hit.find(squad.layout(state), "message"))
        local _, label_action = squad.update(state, {
            kind = "click",
            x = message.rect.x + 2,
            y = message.rect.y + 2,
            button = 1,
        })
        t.is_true(label_action == nil)
    end)
end)
