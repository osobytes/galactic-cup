-- Pure steering/selection helpers used by the match AI.

local Vec2 = require("core.vec2")

local ai = {}

---@param point Vec2
---@param positions Vec2[]
---@param exclude integer?  -- index to skip (e.g. self)
---@return integer? index  -- index into positions of the closest, or nil if none
function ai.closest(point, positions, exclude)
    local best, best_dist
    for i, p in ipairs(positions) do
        if i ~= exclude then
            local d = point:dist(p)
            if not best_dist or d < best_dist then
                best_dist = d
                best = i
            end
        end
    end
    return best
end

-- Move `pos` toward `target`, covering at most `max_dist`. Returns the new
-- position and the unit direction travelled (zero direction if already there).
---@param pos Vec2
---@param target Vec2
---@param max_dist number
---@return Vec2 new_pos
---@return Vec2 dir
function ai.steer(pos, target, max_dist)
    local to = target:sub(pos)
    local d = to:length()
    if d == 0 then
        return Vec2.new(pos.x, pos.y), Vec2.new(0, 0)
    end
    local dir = to:normalized()
    if d <= max_dist then
        return Vec2.new(target.x, target.y), dir
    end
    return pos:add(dir:scale(max_dist)), dir
end

return ai
