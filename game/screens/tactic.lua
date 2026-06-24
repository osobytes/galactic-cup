-- Tactic selection screen, ending the pre-match flow with Kick Off. Pure.

local hit = require("game.ui.hit")
local tactics = require("data.tactics")

local ORDER = { "balanced", "press_high", "counter" }

local M = {}

---@param viewport { w: number, h: number }
---@return table
function M.new_state(viewport)
    return { viewport = viewport, selected = "balanced" }
end

---@param state table
---@return Layout
function M.layout(state)
    local vp = state.viewport
    ---@type Layout
    local layout = {
        {
            id = "title",
            kind = "title",
            text = "Choose Tactic",
            rect = { x = 0, y = 60, w = vp.w, h = 30 },
            data = { align = "center" },
        },
    }

    local y = 140
    for _, id in ipairs(ORDER) do
        local tac = tactics[id]
        layout[#layout + 1] = {
            id = "tactic_" .. id,
            kind = "button",
            text = tac.name,
            selected = state.selected == id,
            rect = { x = vp.w / 2 - 150, y = y, w = 300, h = 52 },
        }
        y = y + 64
    end

    layout[#layout + 1] = {
        id = "kickoff",
        kind = "button",
        text = "Kick Off",
        rect = { x = vp.w / 2 - 80, y = y + 20, w = 160, h = 44 },
    }
    return layout
end

---@param state table
---@param event InputEvent
---@return table, table?
function M.update(state, event)
    if event.kind == "click" then
        local id = hit.at(M.layout(state), event.x, event.y)
        if id then
            local tid = id:match("^tactic_(.+)$")
            if tid then
                state.selected = tid
                return state
            elseif id == "kickoff" then
                return state, { go = "match", tactic = state.selected }
            end
        end
    end
    return state
end

return M
