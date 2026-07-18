local focus = require("game.ui.focus")
local tactics = require("data.tactics")

---@class TacticScreenContext
---@field selected string
---@field formation_id string

---@class TacticScreenState
---@field viewport { w: number, h: number }
---@field selected string
---@field formation_id string
---@field focus string

---@class TacticScreenModule
local tactic = {}

---@return string[]
local function sorted_tactic_ids()
    local ids = {}
    for id in pairs(tactics) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

---@param viewport { w: number, h: number }
---@param context TacticScreenContext?
---@return TacticScreenState
function tactic.new_state(viewport, context)
    local selected = context and context.selected or "balanced"
    return {
        viewport = viewport,
        selected = selected,
        formation_id = context and context.formation_id or "2-1-1",
        focus = "tactic_" .. selected,
    }
end

---@param state TacticScreenState
---@return Layout
function tactic.layout(state)
    local layout = {
        {
            id = "title",
            kind = "title",
            text = "PLAY THE PLAN",
            rect = { x = 0, y = 38, w = state.viewport.w, h = 34 },
            data = { align = "center" },
        },
        {
            id = "shape",
            kind = "eyebrow",
            text = "FORMATION  " .. state.formation_id,
            rect = { x = 0, y = 76, w = state.viewport.w, h = 24 },
            data = { align = "center" },
        },
    }
    for i, id in ipairs(sorted_tactic_ids()) do
        local data = tactics[id]
        layout[#layout + 1] = {
            id = "tactic_" .. id,
            kind = "button",
            text = data.name:upper()
                .. "\n+ "
                .. (data.strength or "A clear team-wide intention.")
                .. "\n− "
                .. (data.risk or "Creates a readable tradeoff."),
            selected = state.selected == id,
            focused = state.focus == "tactic_" .. id,
            rect = { x = 220, y = 124 + (i - 1) * 104, w = 520, h = 86 },
            data = { align = "left" },
        }
    end
    layout[#layout + 1] = {
        id = "back",
        kind = "button",
        text = "BACK",
        focused = state.focus == "back",
        rect = { x = 254, y = 466, w = 190, h = 42 },
    }
    layout[#layout + 1] = {
        id = "kickoff",
        kind = "button",
        text = "KICK OFF",
        focused = state.focus == "kickoff",
        rect = { x = 516, y = 466, w = 190, h = 42 },
    }
    return layout
end

---@param state TacticScreenState
---@param event InputEvent
---@return TacticScreenState, table?
function tactic.update(state, event)
    local layout = tactic.layout(state)
    local next = {
        viewport = state.viewport,
        selected = state.selected,
        formation_id = state.formation_id,
        focus = focus.navigate(layout, state.focus, event) or state.focus,
    }
    if event.kind == "action" and event.action == "back" then
        return next,
            {
                go = "formation",
                tactic_id = next.selected,
                tactic = next.selected,
            }
    end
    local id = focus.activated(layout, next.focus, event)
    if id then
        next.focus = id
        local tactic_id = id:match("^tactic_(.+)$")
        if tactic_id and tactics[tactic_id] then
            next.selected = tactic_id
        elseif id == "back" then
            return next,
                {
                    go = "formation",
                    tactic_id = next.selected,
                    tactic = next.selected,
                }
        elseif id == "kickoff" then
            return next,
                {
                    go = "match",
                    tactic_id = next.selected,
                    tactic = next.selected,
                }
        end
    end
    return next
end

return tactic
