-- Procedural billboard avatar drawn entirely from love.graphics primitives
-- (no sprite sheets). The figure stands upright facing the camera; body motion
-- lives in screen space (bob, limb pump, lean) while aim/facing stays a
-- ground-plane vector. All sizes scale off `r` (the projected body radius) so
-- far players shrink with the perspective.

local renderer = {}

-- Global alpha multiplier for the current figure pass. Dash afterimages set this
-- below 1 to draw faded ghosts; `set` honours it so every body part fades at once
-- without threading an alpha through each call.
local alpha_mul = 1

local function set(c, a)
    love.graphics.setColor(c[1], c[2], c[3], (a or 1) * alpha_mul)
end

local function clamp(x, a, b)
    return math.max(a, math.min(b, x))
end

-- Lighten a colour toward white for joint/visor accents.
local function lighten(c, t)
    return { c[1] + (1 - c[1]) * t, c[2] + (1 - c[2]) * t, c[3] + (1 - c[3]) * t }
end

-- Draw just the standing body (legs, arms, torso, helmet) centred on screen-x
-- `bx`, feet at `gy`. No shadow / selection ring / facing tick — those are drawn
-- once by `renderer.draw` so afterimage ghosts don't duplicate them.
---@param bx number
---@param gy number
---@param r number
---@param color number[]
---@param v PlayerView?
---@param opts table
local function figure(bx, gy, r, color, v, opts)
    local sp = v and v.speed or 0
    local ph = v and v.phase or 0
    local run = clamp(sp / 90, 0, 1) -- 0 idle .. 1 full sprint
    local lean = v and v.lean or 0
    local accent = lighten(color, 0.55)

    local swing = math.sin(ph) -- fore/aft limb phase
    -- Whole-body bounce: a gentle idle breath plus a run bob that peaks twice
    -- per stride.
    local bounce = run * math.abs(math.sin(ph)) * r * 0.16
    local breath = (1 - run) * math.sin(ph * 0.5 + bx) * r * 0.04

    local cx = bx + lean * r * 0.5
    local foot_y = gy
    local hip_y = gy - r * 1.35 - bounce - breath
    local sh_y = gy - r * 2.15 - bounce - breath
    local head_y = gy - r * 2.75 - bounce - breath

    local stride = run * r * 0.65
    local hip_dx = r * 0.34

    -- Legs (pump in opposite phase). Boots are chunky blocks at the feet.
    love.graphics.setLineWidth(math.max(1.5, r * 0.34))
    set(color, opts.is_keeper and 0.8 or 1)
    local lfx = cx - hip_dx + swing * stride
    local rfx = cx + hip_dx - swing * stride
    love.graphics.line(cx - hip_dx, hip_y, lfx, foot_y)
    love.graphics.line(cx + hip_dx, hip_y, rfx, foot_y)
    set(accent, 1)
    love.graphics.setLineWidth(math.max(1.5, r * 0.42))
    love.graphics.line(lfx - r * 0.12, foot_y, lfx + r * 0.18, foot_y)
    love.graphics.line(rfx - r * 0.12, foot_y, rfx + r * 0.18, foot_y)

    -- Arms (opposite the legs, swinging the other way).
    love.graphics.setLineWidth(math.max(1.5, r * 0.26))
    set(color, opts.is_keeper and 0.8 or 1)
    love.graphics.line(cx - r * 0.5, sh_y, cx - r * 0.55 - swing * stride * 0.6, hip_y + r * 0.2)
    love.graphics.line(cx + r * 0.5, sh_y, cx + r * 0.55 + swing * stride * 0.6, hip_y + r * 0.2)

    -- Torso (capsule: rounded rect from hips to shoulders).
    local tw = r * 1.1
    set(color, opts.is_keeper and 0.7 or 1)
    love.graphics.rectangle("fill", cx - tw / 2, sh_y, tw, hip_y - sh_y, r * 0.45, r * 0.45)
    -- Team joint band across the chest.
    set(accent, 0.9)
    love.graphics.setLineWidth(math.max(1, r * 0.18))
    love.graphics.line(
        cx - tw / 2,
        sh_y + (hip_y - sh_y) * 0.4,
        cx + tw / 2,
        sh_y + (hip_y - sh_y) * 0.4
    )

    -- Helmet + visor. The visor sits on the side the player aims toward (its
    -- ground-plane x), giving a readable facing cue without rotating the body.
    local hr = r * 0.62
    set(color, 1)
    love.graphics.circle("fill", cx, head_y, hr)
    local fx = opts.facing and opts.facing.x or 0
    set(accent, 0.95)
    love.graphics.arc(
        "fill",
        cx,
        head_y,
        hr * 0.82,
        math.rad(-40) + fx * 0.6,
        math.rad(90) + fx * 0.6
    )
end

-- Draw one player.
---@param sx number  -- screen x of the ground point (feet)
---@param gy number  -- screen y of the ground point (feet)
---@param r number   -- projected body radius (px)
---@param color number[]
---@param v PlayerView?  -- nil = idle fallback
---@param opts { facing: Vec2, is_keeper: boolean, controlled: boolean, dashing: boolean? }
function renderer.draw(sx, gy, r, color, v, opts)
    -- Ground shadow (kept here so it tracks the figure).
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", sx, gy, r * 1.15, r * 0.5)

    -- Selection ring on the ground, under everything.
    if opts.controlled then
        set({ 1, 1, 1 }, 0.9)
        love.graphics.setLineWidth(math.max(1, r * 0.12))
        love.graphics.ellipse("line", sx, gy, r * 1.25, r * 0.6)
    end

    -- Dash afterimage: faded copies trailing backward along the facing direction
    -- (which equals the move direction during a dash). Drawn before the figure so
    -- the solid body sits on top of its own smear.
    if opts.dashing and opts.facing then
        local fx, fy = opts.facing.x, opts.facing.y
        for n = 1, 2 do
            local k = n * 0.6
            alpha_mul = 0.24 / n
            figure(sx - fx * r * 1.1 * k, gy - fy * r * 0.55 * k, r, color, v, opts)
        end
        alpha_mul = 1
    end

    figure(sx, gy, r, color, v, opts)

    -- Ground-plane facing tick (kept from the old renderer as a clear aim cue).
    if opts.facing then
        set({ 1, 1, 1 }, 0.7)
        love.graphics.setLineWidth(math.max(1, r * 0.12))
        love.graphics.line(sx, gy, sx + opts.facing.x * r * 1.1, gy + opts.facing.y * r * 0.6)
    end
end

return renderer
