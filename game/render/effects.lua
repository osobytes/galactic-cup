-- The "juice" layer: turns one-frame sim events (shots, passes, traps) into
-- short-lived particles, and samples a fading trail behind a fast loose ball.
-- Renderer-side state only — the sim stays pure. Rollback actions use stable
-- event keys; `update` remains the offline adapter. Drawing projects and paints.

local effects = {}

-- Match the ball's billboard lift in pitch.lua so flashes/trails sit on the ball.
local BALL_LIFT = 4
local TRAIL_LIFE = 0.32 -- base seconds a trail dot lingers (hot dots last longer)
local TRAIL_SPACING = 7 -- world units between samples (fps-independent spacing)
local TRAIL_MIN_SPEED = 80 -- only trail a ball moving faster than this
local TRAIL_HOT_SPEED = 900 -- ball speed that reads as full "heat" (charged shot)

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
---@field event_id string?

---@type Particle[]
local particles = {}
---@type { x: number, y: number, z: number, heat: number, life: number, max: number }[]
local trail = {}
local last_sample ---@type { x: number, y: number }?
---@type table<string, boolean>
local speculative_events = {}

local function add(x, y, vx, vy, life, size, color, kind, event_id)
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
        event_id = event_id,
    }
end

-- A radial spray of sparks. Direction is randomized; index-free so it's fine in
-- normal game code (unlike workflow scripts, math.random is available here).
local function burst(x, y, n, speed, life, size, color, event_id)
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
            "spark",
            event_id
        )
    end
end

local function ring(x, y, life, size, color, event_id)
    add(x, y, 0, 0, life, size, color, "ring", event_id)
end

-- Drop all live effects (call on a fresh match / kickoff so nothing carries over).
function effects.reset()
    particles = {}
    trail = {}
    last_sample = nil
    speculative_events = {}
end

---@param e MatchEvent
---@param event_id string?
local function spawn_event(e, event_id)
    if e.kind == "shot" then
        ring(e.x, e.y, 0.30, 16, { 1, 0.95, 0.7 }, event_id)
        burst(e.x, e.y, 10, 230, 0.35, 3, { 1, 0.9, 0.55 }, event_id)
    elseif e.kind == "pass" then
        ring(e.x, e.y, 0.24, 11, { 0.8, 0.95, 1 }, event_id)
        burst(e.x, e.y, 5, 150, 0.26, 2, { 0.8, 0.95, 1 }, event_id)
    elseif e.kind == "touch" then
        ring(e.x, e.y, 0.28, 13, { 1, 1, 1 }, event_id)
    elseif e.kind == "tackle" then
        -- A hard hit: punchier and warmer than the rest.
        ring(e.x, e.y, 0.34, 18, { 1, 0.6, 0.3 }, event_id)
        burst(e.x, e.y, 12, 260, 0.4, 3, { 1, 0.7, 0.4 }, event_id)
    elseif e.kind == "catch" or e.kind == "claim" then
        -- Clean grab/gather: a tight, confident double ring, no spray.
        ring(e.x, e.y, 0.3, 12, { 0.8, 1, 0.9 }, event_id)
        ring(e.x, e.y, 0.38, 20, { 0.6, 1, 0.8 }, event_id)
    elseif e.kind == "parry" then
        -- Deflection: a sharp cool spark fan.
        ring(e.x, e.y, 0.3, 16, { 0.7, 0.9, 1 }, event_id)
        burst(e.x, e.y, 9, 220, 0.34, 3, { 0.7, 0.9, 1 }, event_id)
    elseif e.kind == "header" then
        -- Aerial flick: a crisp high ring.
        ring(e.x, e.y, 0.28, 15, { 0.9, 1, 1 }, event_id)
        burst(e.x, e.y, 5, 170, 0.28, 2, { 0.9, 1, 1 }, event_id)
    elseif e.kind == "volley" then
        -- A volley is violence: big hot flash.
        ring(e.x, e.y, 0.34, 20, { 1, 0.8, 0.45 }, event_id)
        burst(e.x, e.y, 12, 280, 0.4, 3, { 1, 0.8, 0.45 }, event_id)
    elseif e.kind == "bicycle" then
        -- Acrobatic strike: a larger double flash, whether clean or wild.
        ring(e.x, e.y, 0.38, 24, { 1, 0.65, 0.35 }, event_id)
        ring(e.x, e.y, 0.28, 14, { 0.85, 0.95, 1 }, event_id)
        burst(e.x, e.y, 15, 310, 0.44, 3, { 1, 0.7, 0.4 }, event_id)
    elseif e.kind == "reception" then
        -- First touch: clean is compact; a heavy or missed touch splashes wider.
        local clean = e.outcome == "clean"
        ring(e.x, e.y, clean and 0.2 or 0.3, clean and 9 or 16, { 0.65, 1, 0.85 }, event_id)
        if not clean then
            burst(e.x, e.y, 5, 150, 0.26, 2, { 0.65, 1, 0.85 }, event_id)
        end
    elseif e.kind == "block" then
        -- Body block: a blunt thud off a defender, warmer and smaller than a parry.
        ring(e.x, e.y, 0.26, 14, { 1, 0.85, 0.6 }, event_id)
        burst(e.x, e.y, 6, 180, 0.3, 2, { 1, 0.85, 0.6 }, event_id)
    end
end

---@param id string
local function revoke_event(id)
    speculative_events[id] = nil
    for index = #particles, 1, -1 do
        if particles[index].event_id == id then
            table.remove(particles, index)
        end
    end
end

---@param event RollbackWrappedEvent
local function add_speculative(event)
    if event.domain:sub(1, 6) ~= "match/" or speculative_events[event.id] then
        return
    end
    speculative_events[event.id] = true
    local payload = event.payload --[[@as MatchEvent]]
    spawn_event(payload, event.id)
end

-- Apply a complete stable-event delta. Speculative action visuals are keyed by
-- event ID, so a correction can revoke or atomically replace their particles.
---@param diff RollbackEventDiff
function effects.apply_event_diff(diff)
    for _, event in ipairs(diff.revoked) do
        revoke_event(event.id)
    end
    for _, replacement in ipairs(diff.replaced) do
        revoke_event(replacement.before.id)
        add_speculative(replacement.after)
    end
    for _, event in ipairs(diff.added) do
        add_speculative(event)
    end
end

-- Once an event is confirmed it cannot be revoked. Existing particles keep
-- aging naturally, while the rollback key is retired from bounded state.
---@param event_id string
function effects.confirm_event(event_id)
    speculative_events[event_id] = nil
end

-- A corrected authoritative boundary invalidates renderer-owned loose-ball
-- path samples. Action particles remain reconciled separately by stable ID.
function effects.reset_trail()
    trail = {}
    last_sample = nil
end

---@param s MatchState
function effects.sample_ball(s)
    -- Sample the ball trail only when it's a fast loose ball, spaced by distance
    -- so the trail looks the same regardless of framerate and never blobs at
    -- rest. Each dot remembers the ball's speed ("heat") and height, so a
    -- charged shot streaks hotter, longer and along its true flight path.
    local speed = s.ball_vel:length()
    if s.owner == nil and speed > TRAIL_MIN_SPEED then
        local dx = last_sample and (s.ball.x - last_sample.x) or math.huge
        local dy = last_sample and (s.ball.y - last_sample.y) or math.huge
        if dx * dx + dy * dy >= TRAIL_SPACING * TRAIL_SPACING then
            local heat = math.min(1, speed / TRAIL_HOT_SPEED)
            local life = TRAIL_LIFE * (0.7 + 0.9 * heat)
            trail[#trail + 1] =
                { x = s.ball.x, y = s.ball.y, z = s.ball_z, heat = heat, life = life, max = life }
            last_sample = { x = s.ball.x, y = s.ball.y }
        end
    else
        last_sample = nil
    end
end

-- Consume one simulated state's events and position sample. This is the
-- compatibility adapter used by the non-rollback match path.
---@param s MatchState
function effects.consume(s)
    for _, event in ipairs(s.events) do
        spawn_event(event, nil)
    end
    effects.sample_ball(s)
end

---@return { particle_count: integer, trail_count: integer, speculative_ids: string[] }
function effects.diagnostics()
    local ids = {}
    for id in pairs(speculative_events) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return {
        particle_count = #particles,
        trail_count = #trail,
        speculative_ids = ids,
    }
end

-- Advance renderer-owned particles at display cadence.
---@param dt number
function effects.tick(dt)
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

-- Compatibility helper for callers that have one simulation step per render
-- frame. Fixed-clock callers consume each tick then animate once per render.
---@param s MatchState
---@param dt number
function effects.update(s, dt)
    effects.consume(s)
    effects.tick(dt)
end

-- Ball trail. Draw under the ball (call before the depth-sorted entities).
-- Heat (sample-time ball speed) drives size, warmth and brightness: a tap-pass
-- leaves a faint wisp, a charged shot a hot comet tail the bloom pass lights up.
---@param project fun(wx: number, wy: number): number, number, number
function effects.draw_trail(project)
    for _, t in ipairs(trail) do
        local sx, sy, scale = project(t.x, t.y)
        local a = t.life / t.max
        local heat = t.heat or 0
        love.graphics.setColor(1, 0.95 - 0.35 * heat, 0.7 - 0.45 * heat, a * (0.35 + 0.4 * heat))
        local r = (2.5 + 3 * a) * (1 + 0.8 * heat) * scale
        love.graphics.circle("fill", sx, sy - (BALL_LIFT + (t.z or 0)) * scale, r)
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
