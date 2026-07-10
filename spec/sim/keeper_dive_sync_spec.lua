-- Regression: the keeper's dive and a committed save must stay in sync with
-- the ball's real (friction-decelerated) flight. The old constant-velocity
-- timing made keepers dive the instant they committed (long before slow shots
-- arrived) and force-resolved saves mid-air — the ball stopped at an
-- "invisible wall" tens of px from the keeper.
local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local Vec2 = require("core.vec2")

local KEEPER_HANDS = 30 -- mirror of the sim constant: glove-contact radius
local DIVE_FRAMES = math.ceil(0.32 * 60) -- KEEPER_DIVE_DURATION at 60 fps

local NO_INPUT = {
    move = Vec2.new(0, 0),
    shoot = false,
    shoot_held = false,
    pass = false,
    pass_held = false,
    switch = false,
    dash = false,
    dodge = false,
    lob = false,
    sprint = false,
    jockey = false,
}

-- Fire a straight-ish shot at the away keeper from 120px out and watch it:
-- returns the frame the dive started (nil = never), the frame and distance of
-- the save resolution, and the keeper.
local function shoot_at_keeper(speed)
    local s = match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
    local k
    for _, p in ipairs(s.players) do
        if p.team == "away" and p.is_keeper then
            k = p
        end
    end
    k.pos = Vec2.new(938, 270)
    s.owner = nil
    s.pickup_cd = 0.3
    s.ball = Vec2.new(818, 268)
    s.ball_vel = Vec2.new(speed, 10)
    local dive_frame, resolve_frame, resolve_dist
    for f = 1, 240 do
        match.step(s, 1 / 60, NO_INPUT)
        if not dive_frame and k.dive_timer > 0 then
            dive_frame = f
        end
        for _, e in ipairs(s.events) do
            if e.kind == "catch" or e.kind == "parry" then
                resolve_frame = f
                resolve_dist = k.pos:dist(Vec2.new(e.x, e.y))
            end
        end
        if resolve_frame then
            break
        end
    end
    return dive_frame, resolve_frame, resolve_dist, k
end

t.describe("keeper save/dive sync", function()
    t.it("a save always resolves at glove contact, never in mid-air", function()
        for _, speed in ipairs({ 500, 400, 300, 200 }) do
            local _, resolve_frame, resolve_dist = shoot_at_keeper(speed)
            t.is_true(resolve_frame ~= nil, ("speed %d: the shot is saved"):format(speed))
            t.is_true(
                resolve_dist <= KEEPER_HANDS + 1,
                ("speed %d: resolved %.1fpx from the keeper (mid-air wall)"):format(
                    speed,
                    resolve_dist or -1
                )
            )
        end
    end)

    t.it("the dive is timed to the ball's arrival, not to the commit", function()
        for _, speed in ipairs({ 300, 200 }) do
            local dive_frame, resolve_frame = shoot_at_keeper(speed)
            t.is_true(dive_frame ~= nil and resolve_frame ~= nil)
            -- The lunge must still be fresh when the ball arrives: no diving
            -- half a second early and lying on the grass as the shot rolls in.
            t.is_true(
                resolve_frame - dive_frame <= DIVE_FRAMES + 10,
                ("speed %d: dive at f%d but save at f%d — dive long over"):format(
                    speed,
                    dive_frame,
                    resolve_frame
                )
            )
        end
    end)

    t.it("a shot dying short of the keeper is never vacuumed mid-air", function()
        -- 140 px/s can only ever roll ~117px: it dies just short of the line.
        local s =
            match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        local k
        for _, p in ipairs(s.players) do
            if p.team == "away" and p.is_keeper then
                k = p
            end
        end
        k.pos = Vec2.new(938, 270)
        s.owner = nil
        s.pickup_cd = 0.3
        s.ball = Vec2.new(818, 268)
        s.ball_vel = Vec2.new(140, 0)
        for _ = 1, 240 do
            match.step(s, 1 / 60, NO_INPUT)
            for _, e in ipairs(s.events) do
                if e.kind == "catch" or e.kind == "parry" then
                    t.is_true(
                        k.pos:dist(Vec2.new(e.x, e.y)) <= KEEPER_HANDS + 1,
                        "a dying ball resolved away from the gloves"
                    )
                end
            end
        end
    end)

    t.it("the dive stops at the intercept point instead of lunging past it", function()
        -- Nearly straight shot: the needed correction is ~2px. The keeper must
        -- not fly 50+px off its spot chasing a normalized direction.
        local s =
            match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        local k
        for _, p in ipairs(s.players) do
            if p.team == "away" and p.is_keeper then
                k = p
            end
        end
        k.pos = Vec2.new(938, 270)
        local start_y = k.pos.y
        s.owner = nil
        s.pickup_cd = 0.3
        s.ball = Vec2.new(818, 269)
        s.ball_vel = Vec2.new(350, 2)
        local max_drift = 0
        for _ = 1, 120 do
            match.step(s, 1 / 60, NO_INPUT)
            max_drift = math.max(max_drift, math.abs(k.pos.y - start_y))
            if s.owner ~= nil then
                break
            end
        end
        t.is_true(
            max_drift < 25,
            ("keeper drifted %.1fpx off its line for a straight shot"):format(max_drift)
        )
    end)
end)
