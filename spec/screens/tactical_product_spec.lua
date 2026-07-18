local formation = require("game.screens.formation")
local hit = require("game.ui.hit")
local session = require("game.session")
local t = require("spec.support.runner")
local tactic = require("game.screens.tactic")

local VP = { w = 960, h = 540 }

t.describe("product tactical setup", function()
    t.it("carries all five visual identities into every formation preview", function()
        local state = session.new()
        local layout = formation.layout(formation.new_state(VP, {
            selected = state.formation_id,
            starter_ids = state.starter_ids,
        }))
        for _, id in ipairs({ "1-1-2", "1-2-1", "2-1-1" }) do
            local preview = assert(hit.find(layout, "preview_" .. id))
            t.eq(#preview.data.markers, 5)
            t.is_true(preview.data.markers[1].name ~= nil)
            t.is_true(preview.data.markers[1].shape ~= nil)
        end
        t.is_true(assert(assert(hit.find(layout, "lineup")).text):match("OZZO") ~= nil)
    end)

    t.it("uses authored strengths and risks without exposing tuning values", function()
        local formation_state = formation.new_state(VP)
        for _, widget in ipairs(formation.layout(formation_state)) do
            if widget.id:match("^formation_") then
                t.is_true(assert(widget.text):match("%+") ~= nil)
                t.is_true(widget.text:match("−") ~= nil)
            end
        end

        local tactic_state = tactic.new_state(VP)
        for _, widget in ipairs(tactic.layout(tactic_state)) do
            if widget.id:match("^tactic_") then
                t.is_true(assert(widget.text):match("%+") ~= nil)
                t.is_true(widget.text:match("−") ~= nil)
                t.is_true(widget.text:match("stamina_drain") == nil)
            end
        end
    end)
end)
