-- Formation selection screen. Pure: new_state/layout/update.

local hit = require("game.ui.hit")
local formations = require("data.formations")

local ORDER = { "2-1-1", "1-2-1", "1-1-2" }

local M = {}

---@param viewport { w: number, h: number }
---@return table
function M.new_state(viewport)
    return { viewport = viewport, selected = "2-1-1" }
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
            text = "Choose Formation",
            rect = { x = 0, y = 60, w = vp.w, h = 30 },
            data = { align = "center" },
        },
    }

    local y = 140
    for _, id in ipairs(ORDER) do
        local f = formations[id]
        layout[#layout + 1] = {
            id = "formation_" .. id,
            kind = "button",
            text = id .. "   " .. f.name,
            selected = state.selected == id,
            rect = { x = vp.w / 2 - 150, y = y, w = 300, h = 52 },
        }
        y = y + 64
    end

    layout[#layout + 1] = {
        id = "next",
        kind = "button",
        text = "Next",
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
            local fid = id:match("^formation_(.+)$")
            if fid then
                state.selected = fid
                return state
            elseif id == "next" then
                return state, { go = "tactic", formation = state.selected }
            end
        end
    end
    return state
end

return M
