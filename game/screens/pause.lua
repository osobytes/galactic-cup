local focus = require("game.ui.focus")

---@class PauseScreenState
---@field viewport { w: number, h: number }
---@field focus string
---@field confirm_restart boolean

---@class PauseScreenModule
local pause = {}

---@param viewport { w: number, h: number }
---@return PauseScreenState
function pause.new_state(viewport)
    return { viewport = viewport, focus = "resume", confirm_restart = false }
end

---@param state PauseScreenState
---@return Layout
function pause.layout(state)
    local layout = {
        {
            id = "title",
            kind = "title",
            text = "MATCH PAUSED",
            rect = { x = 0, y = 92, w = state.viewport.w, h = 40 },
            data = { align = "center" },
        },
    }
    local labels = {
        { "resume", "RESUME" },
        { "controls", "CONTROLS" },
        { "settings", "SETTINGS" },
        {
            "restart",
            state.confirm_restart and "CONFIRM RESTART" or "RESTART MATCH",
        },
        { "main_menu", "MAIN MENU" },
    }
    for i, item in ipairs(labels) do
        layout[#layout + 1] = {
            id = item[1],
            kind = "button",
            text = item[2],
            focused = state.focus == item[1],
            rect = { x = 350, y = 170 + (i - 1) * 56, w = 260, h = 44 },
        }
    end
    return layout
end

---@param state PauseScreenState
---@param event InputEvent
---@return PauseScreenState, table?
function pause.update(state, event)
    local layout = pause.layout(state)
    local next_focus = focus.navigate(layout, state.focus, event) or state.focus
    local confirmation = state.confirm_restart and next_focus == "restart"
    if event.kind == "action" and (event.action == "back" or event.action == "pause") then
        return {
            viewport = state.viewport,
            focus = next_focus,
            confirm_restart = false,
        }, { go = "resume" }
    end
    local id = focus.activated(layout, next_focus, event)
    local next = {
        viewport = state.viewport,
        focus = id or next_focus,
        confirm_restart = confirmation,
    }
    if id == "restart" and not state.confirm_restart then
        next.confirm_restart = true
        return next
    elseif id == "restart" then
        next.confirm_restart = false
        return next, { go = "restart" }
    elseif id then
        next.confirm_restart = false
        return next, { go = id }
    end
    return next
end

return pause
