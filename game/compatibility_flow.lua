local hit = require("game.ui.hit")
local viewport = require("game.ui.viewport")

---@class CompatibilityFlow
---@field next_action_at number
---@field action_delay number
---@field finished boolean
---@field record_input fun(kind: string)?
local CompatibilityFlow = {}
CompatibilityFlow.__index = CompatibilityFlow

local ROUTE_WIDGETS = {
    title = "play",
    squad = "next",
    formation = "next",
    tactic = "kickoff",
}

---@param record_input fun(kind: string)?
---@return CompatibilityFlow
function CompatibilityFlow.new(record_input)
    return setmetatable({
        next_action_at = 0,
        action_delay = 0.5,
        finished = false,
        record_input = record_input,
    }, CompatibilityFlow)
end

---@param app App
---@param id string
---@param before_click fun()?
---@return boolean
local function click_widget(app, id, before_click)
    local screen = app.stack:current()
    ---@cast screen Menu
    if not screen or not screen.def or not screen.def.layout or not screen.state then
        return false
    end
    local widget = hit.find(screen.def.layout(screen.state), id)
    if not widget then
        return false
    end
    local x, y = viewport.to_actual(
        app.transform,
        widget.rect.x + widget.rect.w / 2,
        widget.rect.y + widget.rect.h / 2
    )
    if before_click then
        before_click()
    end
    app:event({ kind = "click", x = x, y = y, button = 1 })
    return true
end

---@param self CompatibilityFlow
---@param app App
---@param now number
function CompatibilityFlow:update(app, now)
    if self.finished or now < self.next_action_at then
        return
    end
    local route = app:current_route()
    if route == "result" then
        self.finished = true
        return
    end
    local widget = ROUTE_WIDGETS[route]
    if route == "match" and app.adapter.kind == "fake" then
        widget = "complete"
    end
    if
        widget
        and click_widget(app, widget, function()
            if self.record_input then
                self.record_input("compat_click_" .. widget)
            end
        end)
    then
        self.next_action_at = now + self.action_delay
    end
end

return CompatibilityFlow
