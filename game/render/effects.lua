-- The "juice" layer: turns one-frame sim events (shots, passes, traps) into
-- short-lived particles, and samples a fading trail behind a fast loose ball.
-- Renderer-side state only — the sim stays pure. `update` drains MatchState.events
-- and ages everything; `draw_trail`/`draw_over` project and paint.

local effects = {}

-- Match the ball's billboard lift in pitch.lua so flashes/trails sit on the ball.
local BALL_LIFT = 4
local TRAIL_LIFE = 0.32 -- seconds a trail dot lingers
local TRAIL_SPACING = 7 -- world units between samples (fps-independent spacing)
local TRAIL_MIN_SPEED = 80 -- only trail a ball moving faster than this

---@class Particle
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field life number
---@field max number
---@field size number
---@field color number[]
---@field kind "spark"|"ring"

---@type Particle[]
local particles = {}
---@type { x: number, y: number, life: number }[]
local trail = {}
local last_sample ---@type { x: number, y: number }?

local function add(x, y, vx, vy, life, size, color, kind)
    particles[#particles + 1] = {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        life = life,
        max = life,
        size = size,
        color = color,
        kind = kind,
    }
end

-- A radial spray of sparks. Direction is randomized; index-free so it's fine in
-- normal game code (unlike workflow scripts, math.random is available here).
local function burst(x, y, n, speed, life, size, color)
    for _ = 1, n do
        local a = math.random() * math.pi * 2
        local sp = speed * (0.45 + math.random() * 0.55)
        add(
            x,
            y,
            math.cos(a) * sp,
            math.sin(a) * sp,
            life * (0.6 + math.random() * 0.4),
            size,
            color,
            "spark"
        )
    end
end

local function ring(x, y, life, size, color)
    add(x, y, 0, 0, life, size, color, "ring")
end

-- Drop all live effects (call on a fresh match / kickoff so nothing carries over).
function effects.reset()
    particles = {}
    trail = {}
    last_sample = nil
end

---@param s MatchState
---@param dt number
function effects.update(s, dt)
    -- Spawn from this frame's events.
    for _, e in ipairs(s.events) do
        if e.kind == "shot" then
            ring(e.x, e.y, 0.30, 16, { 1, 0.95, 0.7 })
            burst(e.x, e.y, 10, 230, 0.35, 3, { 1, 0.9, 0.55 })
        elseif e.kind == "pass" then
            ring(e.x, e.y, 0.24, 11, { 0.8, 0.95, 1 })
            burst(e.x, e.y, 5, 150, 0.26, 2, { 0.8, 0.95, 1 })
        elseif e.kind == "touch" then
            ring(e.x, e.y, 0.28, 13, { 1, 1, 1 })
        elseif e.kind == "tackle" then
            -- A hard hit: punchier and warmer than the rest.
            ring(e.x, e.y, 0.34, 18, { 1, 0.6, 0.3 })
            burst(e.x, e.y, 12, 260, 0.4, 3, { 1, 0.7, 0.4 })
        elseif e.kind == "catch" or e.kind == "claim" then
            -- Clean grab/gather: a tight, confident double ring, no spray.
            ring(e.x, e.y, 0.3, 12, { 0.8, 1, 0.9 })
            ring(e.x, e.y, 0.38, 20, { 0.6, 1, 0.8 })
        elseif e.kind == "parry" then
            -- Deflection: a sharp cool spark fan.
            ring(e.x, e.y, 0.3, 16, { 0.7, 0.9, 1 })
            burst(e.x, e.y, 9, 220, 0.34, 3, { 0.7, 0.9, 1 })
        elseif e.kind == "block" then
            -- Body block: a blunt thud off a defender, warmer and smaller than a parry.
            ring(e.x, e.y, 0.26, 14, { 1, 0.85, 0.6 })
            burst(e.x, e.y, 6, 180, 0.3, 2, { 1, 0.85, 0.6 })
        end
    end

    -- Sample the ball trail only when it's a fast loose ball, spaced by distance
    -- so the trail looks the same regardless of framerate and never blobs at rest.
    local speed = s.ball_vel:length()
    if s.owner == nil and speed > TRAIL_MIN_SPEED then
        local dx = last_sample and (s.ball.x - last_sample.x) or math.huge
        local dy = last_sample and (s.ball.y - last_sample.y) or math.huge
        if dx * dx + dy * dy >= TRAIL_SPACING * TRAIL_SPACING then
            trail[#trail + 1] = { x = s.ball.x, y = s.ball.y, life = TRAIL_LIFE }
            last_sample = { x = s.ball.x, y = s.ball.y }
        end
    else
        last_sample = nil
    end

    for i = #trail, 1, -1 do
        trail[i].life = trail[i].life - dt
        if trail[i].life <= 0 then
            table.remove(trail, i)
        end
    end

    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        local drag = math.max(0, 1 - 4 * dt)
        p.vx = p.vx * drag
        p.vy = p.vy * drag
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

-- Ball trail. Draw under the ball (call before the depth-sorted entities).
---@param project fun(wx: number, wy: number): number, number, number
function effects.draw_trail(project)
    for _, t in ipairs(trail) do
        local sx, sy, scale = project(t.x, t.y)
        local a = t.life / TRAIL_LIFE
        love.graphics.setColor(1, 0.95, 0.7, a * 0.45)
        love.graphics.circle("fill", sx, sy - BALL_LIFT * scale, (2.5 + 3 * a) * scale)
    end
end

-- Bursts and rings. Draw on top (call after the entities).
---@param project fun(wx: number, wy: number): number, number, number
function effects.draw_over(project)
    for _, p in ipairs(particles) do
        local sx, sy, scale = project(p.x, p.y)
        local t = p.life / p.max
        local c = p.color
        if p.kind == "ring" then
            -- Expands as it fades.
            local rad = p.size * scale * (1.0 + (1 - t) * 0.6)
            love.graphics.setColor(c[1], c[2], c[3], t * 0.8)
            love.graphics.setLineWidth(math.max(1, 2 * scale))
            love.graphics.circle("line", sx, sy - BALL_LIFT * scale, rad)
        else
            love.graphics.setColor(c[1], c[2], c[3], t)
            love.graphics.circle("fill", sx, sy - BALL_LIFT * scale, p.size * scale * t + 0.5)
        end
    end
end

return effects
