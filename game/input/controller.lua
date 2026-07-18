local actions = require("game.input.actions")
local viewport = require("game.ui.viewport")

---@class RawGamepadEvent
---@field kind "gamepad"
---@field button string

---@class InputControllerModule
local controller = {}

---@param event InputEvent|RawGamepadEvent
---@param transform ViewportTransform
---@return InputEvent?
function controller.normalize(event, transform)
    if event.kind == "action" then
        return event
    elseif event.kind == "key" then
        return actions.from_key(event.key)
    elseif event.kind == "gamepad" then
        return actions.from_gamepad(event.button)
    elseif event.kind == "click" then
        local x, y = viewport.to_virtual(transform, event.x, event.y)
        if x and y then
            return { kind = "click", x = x, y = y, button = event.button or 1 }
        end
    end
    return nil
end

return controller
