-- Pure hit-testing over a layout. A layout is just an ordered list of widgets;
-- later widgets are "on top", so hit-testing scans back-to-front.

---@class Widget
---@field id string
---@field rect Rect
---@field kind string?  -- "button" | "label" | "card" | ...
---@field text string?
---@field selected boolean?
---@field data any?

---@alias Layout Widget[]

local hit = {}

---@param r Rect
---@param x number
---@param y number
---@return boolean
local function inside(r, x, y)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- Id of the topmost widget containing (x, y), or nil.
---@param layout Layout
---@param x number
---@param y number
---@return string?
function hit.at(layout, x, y)
    for i = #layout, 1, -1 do
        local w = layout[i]
        if w.rect and inside(w.rect, x, y) then
            return w.id
        end
    end
    return nil
end

---@param layout Layout
---@param id string
---@return Widget?
function hit.find(layout, id)
    for _, w in ipairs(layout) do
        if w.id == id then
            return w
        end
    end
    return nil
end

return hit
