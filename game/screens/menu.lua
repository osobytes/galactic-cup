-- Adapter that drives a pure screen definition (new_state/layout/update) as a
-- Screen in the stack. All logic stays pure in the def; this only gathers events,
-- routes returned actions, and renders the layout. See AGENTS.md §9.

local ui_draw = require("game.ui.draw")

---@class ScreenDef
---@field new_state function
---@field layout function
---@field update function

---@class Menu : Screen
---@field def ScreenDef
---@field state table
---@field on_action fun(action: table)?
---@field transition number
local Menu = {}
Menu.__index = Menu

---@param def any
---@param viewport { w: number, h: number }
---@param on_action fun(action: table)?
---@param context any?
---@return Menu
function Menu.new(def, viewport, on_action, context)
    ---@cast def ScreenDef
    return setmetatable({
        def = def,
        state = def.new_state(viewport, context),
        on_action = on_action,
        transition = 0,
    }, Menu)
end

---@param dt number
function Menu:update(dt)
    local motion = require("game.ui.motion")
    self.transition = motion.advance(self.transition, dt)
end

---@param evt InputEvent
function Menu:event(evt)
    local state, action = self.def.update(self.state, evt)
    self.state = state
    if action and self.on_action then
        self.on_action(action)
    end
end

function Menu:draw()
    ui_draw.layout(self.def.layout(self.state), self.state.viewport, self.transition)
end

return Menu
