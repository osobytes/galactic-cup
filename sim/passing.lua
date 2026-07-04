-- Pass target selection: the teammate that best matches the aim direction.

local passing = {}

local CONE_COS = 0.5 -- accept teammates within ~60 degrees of the aim direction
local ALIGN_WEIGHT = 4 -- how strongly alignment beats proximity
local DIST_NORM = 300 -- px of distance that costs one point of score

-- Pick the index of the best teammate to pass to. Alignment with the aim
-- direction dominates — pointing at a far, well-lined-up teammate beats a near
-- one off to the side — with a mild preference for the closer of two equally
-- aligned options. Returns nil if nobody is inside the aim cone.
---@param from Vec2
---@param dir Vec2  -- aim direction (need not be normalized)
---@param teammates Vec2[]  -- candidate positions (must exclude the passer)
---@return integer? index
function passing.target(from, dir, teammates)
    local ndir = dir:normalized()
    if ndir.x == 0 and ndir.y == 0 then
        return nil
    end

    local best, best_score
    for i, p in ipairs(teammates) do
        local to = p:sub(from)
        local d = to:length()
        if d > 1 then
            local cos = (to.x * ndir.x + to.y * ndir.y) / d
            if cos >= CONE_COS then
                local score = cos * ALIGN_WEIGHT - d / DIST_NORM
                if not best_score or score > best_score then
                    best_score = score
                    best = i
                end
            end
        end
    end
    return best
end

return passing
