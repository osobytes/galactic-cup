-- Pass target selection: the nearest teammate within an aim cone.

local passing = {}

local CONE_COS = 0.3 -- accept teammates within ~72 degrees of the aim direction

-- Pick the index of the best teammate to pass to: among teammates lying within
-- the aim cone around `dir` from `from`, the nearest one. Returns nil if none.
---@param from Vec2
---@param dir Vec2  -- aim direction (need not be normalized)
---@param teammates Vec2[]  -- candidate positions (must exclude the passer)
---@return integer? index
function passing.target(from, dir, teammates)
    local ndir = dir:normalized()
    if ndir.x == 0 and ndir.y == 0 then
        return nil
    end

    local best, best_dist
    for i, p in ipairs(teammates) do
        local to = p:sub(from)
        local d = to:length()
        if d > 1 then
            local cos = (to.x * ndir.x + to.y * ndir.y) / d
            if cos >= CONE_COS and (not best_dist or d < best_dist) then
                best_dist = d
                best = i
            end
        end
    end
    return best
end

return passing
