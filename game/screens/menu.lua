-- Adapter that drives a pure screen definition (new_state/layout/update) as a
-- Screen in the stack. All logic stays pure in the def; this only gathers events,
-- routes returned actions, and renders the layout. See AGENTS.md §9.

local ui_draw = require("game.ui.draw")

---@class ScreenDef
---@field new_state fun(viewport: { w: number, h: number }): table
---@field layout fun(state: table): Layout
---@field update fun(state: table, event: InputEvent): table, table?

---@class Menu : Screen
---@field def ScreenDef
---@field state table
---@field on_action fun(action: table)?
local Menu = {}
Menu.__index = Menu

---@param def ScreenDef
---@param viewport { w: number, h: number }
---@param on_action fun(action: table)?
---@return Menu
function Menu.new(def, viewport, on_action)
    return setmetatable({
        def = def,
        state = def.new_state(viewport),
        on_action = on_action,
    }, Menu)
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
    ui_draw.layout(self.def.layout(self.state))
end

return Menu
