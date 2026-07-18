---@class ViewportTransform
---@field base_w number
---@field base_h number
---@field actual_w number
---@field actual_h number
---@field scale number
---@field offset_x number
---@field offset_y number

---@class ViewportModule
local viewport = {}

---@param actual_w number
---@param actual_h number
---@param base_w number?
---@param base_h number?
---@return ViewportTransform
function viewport.new(actual_w, actual_h, base_w, base_h)
    base_w = base_w or 960
    base_h = base_h or 540
    assert(actual_w > 0 and actual_h > 0, "viewport dimensions must be positive")
    local scale = math.min(actual_w / base_w, actual_h / base_h)
    return {
        base_w = base_w,
        base_h = base_h,
        actual_w = actual_w,
        actual_h = actual_h,
        scale = scale,
        offset_x = (actual_w - base_w * scale) / 2,
        offset_y = (actual_h - base_h * scale) / 2,
    }
end

---@param transform ViewportTransform
---@param x number
---@param y number
---@return number?, number?
function viewport.to_virtual(transform, x, y)
    local vx = (x - transform.offset_x) / transform.scale
    local vy = (y - transform.offset_y) / transform.scale
    if vx < 0 or vy < 0 or vx > transform.base_w or vy > transform.base_h then
        return nil, nil
    end
    return vx, vy
end

---@param transform ViewportTransform
---@param x number
---@param y number
---@return number, number
function viewport.to_actual(transform, x, y)
    return transform.offset_x + x * transform.scale, transform.offset_y + y * transform.scale
end

return viewport
