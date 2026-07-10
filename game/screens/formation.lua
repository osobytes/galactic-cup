-- Formation selection screen. Pure: new_state/layout/update.

local hit = require("game.ui.hit")
local formations = require("data.formations")

---@class FormationScreenState
---@field viewport { w: number, h: number }
---@field selected string

---@class FormationAction
---@field go "tactic"
---@field formation string

local DEFAULT_FORMATION = "2-1-1"
local OPTION_START_Y = 116
local OPTION_HEIGHT = 52
local OPTION_GAP = 12
local BUTTON_WIDTH = 280
local PREVIEW_WIDTH = 124
local PREVIEW_GAP = 12
local OPTION_WIDTH = BUTTON_WIDTH + PREVIEW_GAP + PREVIEW_WIDTH

local M = {}

---@return string[]
local function sorted_formation_ids()
    local ids = {}
    for id in pairs(formations) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

---@param viewport { w: number, h: number }
---@return FormationScreenState
function M.new_state(viewport)
    assert(formations[DEFAULT_FORMATION], "missing default formation: " .. DEFAULT_FORMATION)
    return { viewport = viewport, selected = DEFAULT_FORMATION }
end

---@param state FormationScreenState
---@return Layout
function M.layout(state)
    local vp = state.viewport
    ---@type Layout
    local layout = {
        {
            id = "title",
            kind = "title",
            text = "Choose Formation",
            rect = { x = 0, y = 60, w = vp.w, h = 30 },
            data = { align = "center" },
        },
    }

    local x = vp.w / 2 - OPTION_WIDTH / 2
    local y = OPTION_START_Y
    for _, id in ipairs(sorted_formation_ids()) do
        local formation = formations[id]
        layout[#layout + 1] = {
            id = "formation_" .. id,
            kind = "button",
            text = id .. "   " .. formation.name,
            selected = state.selected == id,
            rect = { x = x, y = y, w = BUTTON_WIDTH, h = OPTION_HEIGHT },
        }
        layout[#layout + 1] = {
            id = "preview_" .. id,
            kind = "formation_preview",
            selected = state.selected == id,
            rect = {
                x = x + BUTTON_WIDTH + PREVIEW_GAP,
                y = y,
                w = PREVIEW_WIDTH,
                h = OPTION_HEIGHT,
            },
            data = {
                keeper = formation.keeper,
                outfield = formation.outfield,
            },
        }
        y = y + OPTION_HEIGHT + OPTION_GAP
    end

    layout[#layout + 1] = {
        id = "next",
        kind = "button",
        text = "Next",
        rect = { x = vp.w / 2 - 80, y = y + 20, w = 160, h = 44 },
    }
    return layout
end

---@param state FormationScreenState
---@param event InputEvent
---@return FormationScreenState, FormationAction?
function M.update(state, event)
    if event.kind == "click" then
        local id = hit.at(M.layout(state), event.x, event.y)
        if id then
            local formation_id = id:match("^formation_(.+)$") or id:match("^preview_(.+)$")
            if formation_id and formations[formation_id] then
                return { viewport = state.viewport, selected = formation_id }
            elseif id == "next" then
                return state, { go = "tactic", formation = state.selected }
            end
        end
    end
    return state
end

return M
