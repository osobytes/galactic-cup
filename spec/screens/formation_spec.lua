local t = require("spec.support.runner")
local formation = require("game.screens.formation")
local hit = require("game.ui.hit")
local formations = require("data.formations")
local match_sim = require("sim.match")
local teams = require("data.teams")

local VP = { w = 960, h = 540 }

---@param layout Layout
---@param id string
---@return InputEvent
local function click_on(layout, id)
    local w = assert(hit.find(layout, id), "missing widget " .. id)
    return { kind = "click", x = w.rect.x + w.rect.w / 2, y = w.rect.y + w.rect.h / 2 }
end

---@return string[]
local function sorted_data_ids()
    local ids = {}
    for id in pairs(formations) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

---@param layout Layout
---@return string[]
local function offered_ids(layout)
    local ids = {}
    for _, widget in ipairs(layout) do
        if widget.kind == "button" then
            local id = widget.id:match("^formation_(.+)$")
            if id then
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

t.describe("formation screen", function()
    t.it("defaults to the balanced 2-1-1 formation", function()
        local s = formation.new_state(VP)
        t.eq(s.selected, "2-1-1")
        local selected = assert(hit.find(formation.layout(s), "formation_2-1-1"))
        t.is_true(selected.selected)
    end)

    t.it("offers every authored formation in stable key order", function()
        local actual = offered_ids(formation.layout(formation.new_state(VP)))
        local expected = sorted_data_ids()

        t.eq(#actual, #expected)
        for i, id in ipairs(expected) do
            t.eq(actual[i], id)
            t.is_true(formations[actual[i]] ~= nil)
        end
    end)

    t.it("discovers a newly authored formation without a screen edit", function()
        local id = "0-2-2-test"
        formations[id] = {
            id = id,
            name = "Test Shape",
            keeper = formations["2-1-1"].keeper,
            outfield = formations["2-1-1"].outfield,
        }

        local ok, err = pcall(function()
            local layout = formation.layout(formation.new_state(VP))
            local actual = offered_ids(layout)
            t.eq(actual[1], id)
            t.is_true(hit.find(layout, "formation_" .. id) ~= nil)
            t.is_true(hit.find(layout, "preview_" .. id) ~= nil)
        end)
        formations[id] = nil
        assert(ok, tostring(err))
    end)

    t.it("includes a legible anchor preview for every option", function()
        local layout = formation.layout(formation.new_state(VP))
        for _, id in ipairs(sorted_data_ids()) do
            local preview = assert(hit.find(layout, "preview_" .. id), "missing preview for " .. id)
            t.eq(preview.kind, "formation_preview")
            t.is_true(preview.rect.w >= 100)
            t.is_true(preview.rect.h >= 40)
            t.eq(preview.data.keeper, formations[id].keeper)
            t.eq(preview.data.outfield, formations[id].outfield)
            t.eq(#preview.data.outfield, 4)
        end
    end)

    t.it("selects the clicked formation", function()
        local s = formation.new_state(VP)
        local s2 = formation.update(s, click_on(formation.layout(s), "formation_1-1-2"))
        t.eq(s2.selected, "1-1-2")
        t.eq(s.selected, "2-1-1", "update should not mutate its input state")
    end)

    t.it("selects a formation when its shape preview is clicked", function()
        local s = formation.new_state(VP)
        local s2 = formation.update(s, click_on(formation.layout(s), "preview_1-2-1"))
        t.eq(s2.selected, "1-2-1")
    end)

    t.it("emits a tactic transition carrying the selection on Next", function()
        local s = formation.new_state(VP)
        s = formation.update(s, click_on(formation.layout(s), "formation_1-2-1"))
        local _, action = formation.update(s, click_on(formation.layout(s), "next"))
        action = assert(action, "expected a transition action")
        t.eq(action.go, "tactic")
        t.eq(action.formation, "1-2-1")
    end)

    t.it("only offers formations accepted by the match simulation", function()
        local ids = offered_ids(formation.layout(formation.new_state(VP)))
        for _, id in ipairs(ids) do
            local match = match_sim.new({
                home = teams.nebula,
                away = teams.orion,
                field = { w = VP.w, h = VP.h },
                home_formation = id,
            })
            t.eq(#match.players, 10)
        end
    end)

    t.it("does nothing when clicking empty space", function()
        local s = formation.new_state(VP)
        local _, action = formation.update(s, { kind = "click", x = 5, y = 5 })
        t.is_true(action == nil)
    end)
end)
