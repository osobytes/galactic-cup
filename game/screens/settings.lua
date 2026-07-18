local focus = require("game.ui.focus")
local settings_model = require("game.settings")

---@class SettingsScreenContext
---@field settings GameSettings

---@class SettingsScreenState
---@field viewport { w: number, h: number }
---@field settings GameSettings
---@field focus string

---@class SettingsScreenModule
local settings_screen = {}

---@param value GameSettings
---@return GameSettings
local function copy_settings(value)
    return settings_model.validate(value)
end

---@param viewport { w: number, h: number }
---@param context SettingsScreenContext?
---@return SettingsScreenState
function settings_screen.new_state(viewport, context)
    local value = context and context.settings or settings_model.defaults()
    return {
        viewport = viewport,
        settings = copy_settings(value),
        focus = "master_volume",
    }
end

---@param value number
---@return string
local function percent(value)
    return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

---@param value boolean
---@return string
local function on_off(value)
    return value and "ON" or "OFF"
end

---@param state SettingsScreenState
---@return Layout
function settings_screen.layout(state)
    local values = {
        { "master_volume", "MASTER VOLUME", percent(state.settings.master_volume) },
        { "sfx_volume", "SFX VOLUME", percent(state.settings.sfx_volume) },
        { "crowd_volume", "CROWD VOLUME", percent(state.settings.crowd_volume) },
        { "muted", "MUTE", on_off(state.settings.muted) },
        { "fullscreen", "FULLSCREEN", on_off(state.settings.fullscreen) },
        { "screen_shake", "SCREEN SHAKE", on_off(state.settings.screen_shake) },
    }
    local layout = {
        {
            id = "title",
            kind = "title",
            text = "SETTINGS",
            rect = { x = 0, y = 38, w = state.viewport.w, h = 36 },
            data = { align = "center" },
        },
        {
            id = "instructions",
            kind = "label",
            text = "LEFT / RIGHT TO ADJUST",
            rect = { x = 0, y = 82, w = state.viewport.w, h = 22 },
            data = { align = "center", tone = "muted" },
        },
    }
    for i, item in ipairs(values) do
        layout[#layout + 1] = {
            id = item[1],
            kind = "button",
            text = item[2] .. "     " .. item[3],
            focused = state.focus == item[1],
            rect = { x = 300, y = 120 + (i - 1) * 48, w = 360, h = 38 },
        }
    end
    layout[#layout + 1] = {
        id = "back",
        kind = "button",
        text = "SAVE & BACK",
        focused = state.focus == "back",
        rect = { x = 380, y = 474, w = 200, h = 42 },
    }
    return layout
end

---@param state SettingsScreenState
---@param key string
---@param delta number
local function adjust(state, key, delta)
    if key == "master_volume" or key == "sfx_volume" or key == "crowd_volume" then
        state.settings[key] = math.max(0, math.min(1, state.settings[key] + delta))
    elseif key == "muted" or key == "fullscreen" or key == "screen_shake" then
        state.settings[key] = not state.settings[key]
    end
end

---@param state SettingsScreenState
---@param event InputEvent
---@return SettingsScreenState, table?
function settings_screen.update(state, event)
    local next = {
        viewport = state.viewport,
        settings = copy_settings(state.settings),
        focus = state.focus,
    }
    local layout = settings_screen.layout(next)
    if event.kind == "action" and event.action == "back" then
        return next, { go = "back", settings = next.settings }
    end
    if event.kind == "action" and (event.action == "left" or event.action == "right") then
        adjust(next, next.focus, event.action == "left" and -0.1 or 0.1)
        return next, { go = "settings_changed", settings = next.settings }
    end

    next.focus = focus.navigate(layout, next.focus, event) or next.focus
    local id = focus.activated(layout, next.focus, event)
    if id == "back" then
        return next, { go = "back", settings = next.settings }
    elseif id then
        next.focus = id
        adjust(next, id, 0.1)
        return next, { go = "settings_changed", settings = next.settings }
    end
    return next
end

return settings_screen
