---@class FocusModule
local focus = {}

---@param widget Widget
---@return boolean
local function focusable(widget)
    if widget.data and widget.data.focusable == false then
        return false
    end
    return widget.kind == "button" or widget.kind == "card"
end

---@param widget Widget
---@return boolean
local function clickable(widget)
    if widget.data and (widget.data.focusable == false or widget.data.disabled) then
        return false
    end
    return focusable(widget) or widget.kind == "formation_preview"
end

---@param layout Layout
---@return string[]
function focus.ids(layout)
    local result = {}
    for _, widget in ipairs(layout) do
        if focusable(widget) and not (widget.data and widget.data.disabled) then
            result[#result + 1] = widget.id
        end
    end
    return result
end

---@param layout Layout
---@param current string?
---@return string?
function focus.ensure(layout, current)
    local ids = focus.ids(layout)
    for _, id in ipairs(ids) do
        if id == current then
            return current
        end
    end
    return ids[1]
end

---@param layout Layout
---@param current string?
---@param delta integer
---@return string?
function focus.move(layout, current, delta)
    local ids = focus.ids(layout)
    if #ids == 0 then
        return nil
    end
    local index = 1
    for i, id in ipairs(ids) do
        if id == current then
            index = i
            break
        end
    end
    index = ((index - 1 + delta) % #ids) + 1
    return ids[index]
end

---@param layout Layout
---@param current string?
---@param event InputEvent
---@return string?
function focus.activated(layout, current, event)
    if event.kind == "click" then
        local hit = require("game.ui.hit")
        local id = hit.at(layout, event.x, event.y)
        local widget = id and hit.find(layout, id) or nil
        return widget and clickable(widget) and id or nil
    elseif event.kind == "action" and event.action == "confirm" then
        return focus.ensure(layout, current)
    end
    return nil
end

---@param layout Layout
---@param current string?
---@param event InputEvent
---@return string?
function focus.navigate(layout, current, event)
    if event.kind ~= "action" then
        return focus.ensure(layout, current)
    end
    if event.action == "up" or event.action == "left" then
        return focus.move(layout, current, -1)
    elseif event.action == "down" or event.action == "right" then
        return focus.move(layout, current, 1)
    end
    return focus.ensure(layout, current)
end

return focus
