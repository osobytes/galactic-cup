-- Immutable 2D vector. Pure math, usable by every layer.

---@class Vec2
---@field x number
---@field y number
local Vec2 = {}
Vec2.__index = Vec2

---@param x number?
---@param y number?
---@return Vec2
function Vec2.new(x, y)
    return setmetatable({ x = x or 0, y = y or 0 }, Vec2)
end

---@param o Vec2
---@return Vec2
function Vec2:add(o)
    return Vec2.new(self.x + o.x, self.y + o.y)
end

---@param o Vec2
---@return Vec2
function Vec2:sub(o)
    return Vec2.new(self.x - o.x, self.y - o.y)
end

---@param s number
---@return Vec2
function Vec2:scale(s)
    return Vec2.new(self.x * s, self.y * s)
end

---@return number
function Vec2:length()
    return math.sqrt(self.x * self.x + self.y * self.y)
end

---@return Vec2
function Vec2:normalized()
    local len = self:length()
    if len == 0 then
        return Vec2.new(0, 0)
    end
    return Vec2.new(self.x / len, self.y / len)
end

---@param o Vec2
---@return number
function Vec2:dist(o)
    return self:sub(o):length()
end

return Vec2
