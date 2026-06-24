-- Impure 2.5D match renderer: draws the simulation state through the camera
-- projection as a perspective pitch with depth-sorted billboard players.
-- (Bloom/neon post-processing is a later pass; this is the geometry layer.)

local camera = require("game.render.camera")

local pitch = {}

local HEX_RADIUS = 26 -- world units, centre to corner

---@param c number[]
---@param a number?
local function set(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

-- Build the screen-space points of a world-space circle (each sample projected).
---@param project fun(wx: number, wy: number): number, number, number
---@param cx number
---@param cy number
---@param r number
---@param segs integer
---@return number[]
local function projected_circle(project, cx, cy, r, segs)
    local pts = {}
    for i = 0, segs do
        local ang = (i / segs) * 2 * math.pi
        local sx, sy = project(cx + r * math.cos(ang), cy + r * math.sin(ang))
        pts[#pts + 1] = sx
        pts[#pts + 1] = sy
    end
    return pts
end

-- Soft additive luminance toward the pitch centre so the floor reads as lit.
---@param project fun(wx: number, wy: number): number, number, number
---@param field { w: number, h: number }
local function draw_floor_glow(project, field)
    local cx, cy = project(field.w / 2, field.h / 2)
    love.graphics.setBlendMode("add")
    for i = 4, 1, -1 do
        set({ 0.05, 0.16, 0.20 }, 0.06)
        love.graphics.ellipse("fill", cx, cy, 130 * i, 64 * i)
    end
    love.graphics.setBlendMode("alpha")
end

-- Bright, blooming pitch markings: halfway line + circle + spot, and goal boxes.
---@param project fun(wx: number, wy: number): number, number, number
---@param field { w: number, h: number }
local function draw_markings(project, field)
    love.graphics.setLineWidth(2)
    set({ 0.35, 0.72, 1.0 }, 0.85)

    local x1, y1 = project(field.w / 2, 0)
    local x2, y2 = project(field.w / 2, field.h)
    love.graphics.line(x1, y1, x2, y2)

    love.graphics.polygon("line", projected_circle(project, field.w / 2, field.h / 2, 70, 36))

    local sx, sy = project(field.w / 2, field.h / 2)
    love.graphics.circle("fill", sx, sy, 3)

    local depth, box_h = 95, 200
    local top, bot = field.h / 2 - box_h / 2, field.h / 2 + box_h / 2
    ---@param xa number
    ---@param xb number
    local function box(xa, xb)
        local p1x, p1y = project(xa, top)
        local p2x, p2y = project(xb, top)
        local p3x, p3y = project(xb, bot)
        local p4x, p4y = project(xa, bot)
        love.graphics.polygon("line", p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
    end
    box(0, depth)
    box(field.w - depth, field.w)

    love.graphics.setLineWidth(1)
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

    set({ 0.16, 0.5, 0.6 }, 0.1)
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
    set({ 0.06, 0.15, 0.20 })
    love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)

    -- Floor luminance (soft additive glow toward the centre).
    draw_floor_glow(project, field)

    -- Hex floor (faint texture).
    draw_hex_floor(project, field)

    -- Field markings (halfway line/circle/spot + goal boxes).
    draw_markings(project, field)

    -- Pitch outline (bright neon border).
    love.graphics.setLineWidth(2)
    set({ 0.35, 0.75, 1.0 }, 0.9)
    love.graphics.polygon("line", ax, ay, bx, by, cx, cy, dx, dy)
    love.graphics.setLineWidth(1)

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
