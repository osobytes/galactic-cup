-- Impure 2.5D match renderer: draws the simulation state through the camera
-- projection as a perspective pitch with depth-sorted billboard players.
-- (Bloom/neon post-processing is a later pass; this is the geometry layer.)

local camera = require("game.render.camera")

local pitch = {}

local HEX_RADIUS = 42 -- world units, centre to corner

---@param c number[]
---@param a number?
local function set(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

-- Draw a pointy-top hex tiling over the pitch, projected per-corner so the cells
-- follow the perspective. Corners are clamped to the field so edge cells meet the
-- touchlines instead of spilling onto the space backdrop.
---@param project fun(wx: number, wy: number): number, number, number
---@param field { w: number, h: number }
local function draw_hex_floor(project, field)
    local r = HEX_RADIUS
    local col_step = math.sqrt(3) * r
    local row_step = 1.5 * r

    set({ 0.13, 0.5, 0.62 }, 0.18)
    local row, cy = 0, 0
    while cy <= field.h + r do
        local x_off = (row % 2 == 1) and (col_step / 2) or 0
        local cx = x_off
        while cx <= field.w + r do
            local pts = {}
            for i = 0, 5 do
                local ang = math.rad(60 * i - 30)
                local wx = math.min(field.w, math.max(0, cx + r * math.cos(ang)))
                local wy = math.min(field.h, math.max(0, cy + r * math.sin(ang)))
                local sx, sy = project(wx, wy)
                pts[#pts + 1] = sx
                pts[#pts + 1] = sy
            end
            love.graphics.polygon("line", pts)
            cx = cx + col_step
        end
        row = row + 1
        cy = cy + row_step
    end
end

-- Render the whole pitch + entities for one frame.
---@param s MatchState
---@param vp { w: number, h: number }
---@param opts { home_color: number[], away_color: number[] }
function pitch.draw(s, vp, opts)
    local field = s.field
    local function project(wx, wy)
        return camera.project(wx, wy, field, vp)
    end

    -- Space backdrop.
    love.graphics.setColor(0.03, 0.04, 0.10)
    love.graphics.rectangle("fill", 0, 0, vp.w, vp.h)

    -- Pitch surface (projected trapezoid).
    local ax, ay = project(0, 0)
    local bx, by = project(field.w, 0)
    local cx, cy = project(field.w, field.h)
    local dx, dy = project(0, field.h)
    set({ 0.05, 0.13, 0.19 })
    love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)

    -- Hex floor.
    draw_hex_floor(project, field)

    -- Pitch outline.
    set({ 0.2, 0.6, 0.85 }, 0.7)
    love.graphics.polygon("line", ax, ay, bx, by, cx, cy, dx, dy)

    -- Goals.
    ---@param g Rect
    ---@param color number[]
    local function draw_goal(g, color)
        local g0x, g0y = project(g.x, g.y)
        local g1x, g1y = project(g.x + g.w, g.y)
        local g2x, g2y = project(g.x + g.w, g.y + g.h)
        local g3x, g3y = project(g.x, g.y + g.h)
        set(color, 0.9)
        love.graphics.polygon("line", g0x, g0y, g1x, g1y, g2x, g2y, g3x, g3y)
    end
    draw_goal(s.goal_home, opts.home_color)
    draw_goal(s.goal_away, opts.away_color)

    -- Depth-sorted drawables (far first).
    local items = {}
    for i, p in ipairs(s.players) do
        items[#items + 1] = { kind = "player", p = p, idx = i, depth = p.pos.y }
    end
    items[#items + 1] = { kind = "ball", depth = s.ball.y }
    table.sort(items, function(a, b)
        return a.depth < b.depth
    end)

    for _, it in ipairs(items) do
        if it.kind == "player" then
            local p = it.p
            local sx, sy, scale = project(p.pos.x, p.pos.y)
            local r = p.radius * scale
            local cy2 = sy - r * 0.9 -- lift the billboard so it "stands" on the ground

            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.ellipse("fill", sx, sy, r * 1.1, r * 0.5)

            if it.idx == s.controlled then
                set({ 1, 1, 1 })
                love.graphics.circle("line", sx, cy2, r + 3)
            end

            local color = (p.team == "home") and opts.home_color or opts.away_color
            love.graphics.setColor(color[1], color[2], color[3], p.is_keeper and 0.65 or 1.0)
            love.graphics.circle("fill", sx, cy2, r)
            set({ 1, 1, 1 }, 0.9)
            love.graphics.line(sx, cy2, sx + p.facing.x * r, cy2 + p.facing.y * r)
        else
            local sx, sy, scale = project(s.ball.x, s.ball.y)
            love.graphics.setColor(0, 0, 0, 0.3)
            love.graphics.ellipse("fill", sx, sy, 6 * scale, 3 * scale)
            love.graphics.setColor(1, 0.95, 0.7)
            love.graphics.circle("fill", sx, sy - 4 * scale, 5 * scale)
        end
    end
end

return pitch
