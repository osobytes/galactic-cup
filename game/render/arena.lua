local theme = require("game.ui.theme")

---@class ArenaRenderModule
local arena_render = {}

local STARS = {
    { 0.05, 0.09, 1 },
    { 0.12, 0.18, 2 },
    { 0.2, 0.06, 1 },
    { 0.29, 0.15, 1 },
    { 0.37, 0.05, 2 },
    { 0.46, 0.13, 1 },
    { 0.55, 0.07, 1 },
    { 0.64, 0.16, 2 },
    { 0.72, 0.05, 1 },
    { 0.81, 0.13, 1 },
    { 0.9, 0.07, 2 },
    { 0.96, 0.18, 1 },
}

---@param color number[]
---@param alpha number?
local function set(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
end

---@param value ArenaData
---@param viewport { w: number, h: number }
function arena_render.draw_backdrop(value, viewport)
    set(theme.colors.void)
    love.graphics.rectangle("fill", 0, 0, viewport.w, viewport.h)

    set(theme.colors.text, 0.35)
    for _, star in ipairs(STARS) do
        love.graphics.circle("fill", viewport.w * star[1], viewport.h * star[2], star[3])
    end

    local cx, cy = viewport.w * 0.5, viewport.h * 0.205
    set(value.highlight_color, 0.12)
    love.graphics.circle("fill", cx, cy, viewport.h * 0.075)
    set(value.highlight_color, 0.78)
    love.graphics.circle("fill", cx, cy, viewport.h * 0.034)
    love.graphics.setLineWidth(math.max(1, viewport.h / 270))
    set(value.highlight_color, 0.7)
    love.graphics.ellipse("line", cx, cy, viewport.w * 0.23, viewport.h * 0.068)
    set(value.rail_color, 0.35)
    love.graphics.ellipse("line", cx, cy, viewport.w * 0.31, viewport.h * 0.09)

    local ribbon_y = viewport.h * 0.222
    love.graphics.setLineWidth(math.max(2, viewport.h / 180))
    set(value.rail_color, 0.62)
    love.graphics.line(viewport.w * 0.07, ribbon_y, viewport.w * 0.39, ribbon_y)
    set(value.highlight_color, 0.62)
    love.graphics.line(viewport.w * 0.61, ribbon_y, viewport.w * 0.93, ribbon_y)

    for i = 0, 7 do
        local x = viewport.w * (0.16 + i * 0.098)
        set(i < 4 and value.rail_color or value.highlight_color, 0.18)
        love.graphics.rectangle(
            "fill",
            x,
            viewport.h * 0.202,
            viewport.w * 0.066,
            viewport.h * 0.028,
            3,
            3
        )
    end
end

---@param value ArenaData
---@param corners { ax: number, ay: number, bx: number, by: number, cx: number, cy: number, dx: number, dy: number }
---@param pulse number?
function arena_render.draw_frame(value, corners, pulse)
    local glow = 0.58 + 0.34 * (pulse or 0)
    love.graphics.setLineWidth(2 + 2 * (pulse or 0))
    set(value.rail_color, glow)
    love.graphics.line(corners.ax, corners.ay, corners.ax - 10, corners.ay - 25)
    love.graphics.line(corners.dx, corners.dy, corners.dx - 12, corners.dy + 16)
    set(value.highlight_color, glow)
    love.graphics.line(corners.bx, corners.by, corners.bx + 10, corners.by - 25)
    love.graphics.line(corners.cx, corners.cy, corners.cx + 12, corners.cy + 16)
    love.graphics.setLineWidth(1)
end

return arena_render
