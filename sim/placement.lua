-- Converts a formation's normalized anchors into absolute pitch positions.
-- Home attacks right (anchors used as-is); away attacks left (x mirrored).

local Vec2 = require("core.vec2")

local placement = {}

---@param formation FormationData
---@param side "home"|"away"
---@param field { w: number, h: number }
---@return Vec2[] anchors  -- keeper first, then outfield in formation order
function placement.anchors(formation, side, field)
    ---@param nx number
    ---@param ny number
    ---@return Vec2
    local function place(nx, ny)
        local x = (side == "home") and nx or (1 - nx)
        return Vec2.new(x * field.w, ny * field.h)
    end

    local out = { place(formation.keeper.x, formation.keeper.y) }
    for _, a in ipairs(formation.outfield) do
        out[#out + 1] = place(a.x, a.y)
    end
    return out
end

return placement
