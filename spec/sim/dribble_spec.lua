local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local tuning = require("sim.tuning")
local Vec2 = require("core.vec2")

local function new_match()
    return match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
end

---@param o table?
---@return MatchInput
local function input(o)
    o = o or {}
    return {
        move = o.move or Vec2.new(0, 0),
        shoot = false,
        shoot_held = false,
        pass = false,
        pass_held = false,
        switch = false,
        dash = false,
        dodge = false,
        lob = false,
        sprint = o.sprint or false,
        jockey = false,
    }
end

-- Forward offset of the ball from the carrier's feet, along their facing.
local function forward_offset(s)
    local p = s.players[s.owner]
    local off = s.ball:sub(p.pos)
    return off.x * p.facing.x + off.y * p.facing.y
end

-- Park everyone except the controlled carrier far away: these tests isolate
-- BALL CONTROL. Duels (pokes, body-blocks) are contested elsewhere.
---@param s MatchState
local function isolate_carrier(s)
    for i, p in ipairs(s.players) do
        if i ~= s.controlled then
            p.pos = (p.team == "home") and Vec2.new(80, 40 + i * 30) or Vec2.new(880, 40 + i * 30)
            p.anchor = p.pos
        end
    end
end

t.describe("touch-based dribble", function()
    t.it("keeps a grounded ball within the carrier's control while dribbling", function()
        tuning.reset()
        local s = new_match()
        local run = input({ move = Vec2.new(1, 0), sprint = true })
        for _ = 1, 40 do
            match.step(s, 1 / 60, run)
            if not s.owner then
                break -- a heavy touch got away; that's covered elsewhere
            end
            local p = s.players[s.owner]
            local control = tuning.values.DRIBBLE_CONTROL + 26 * p.dribble
            t.is_true(s.ball_z == 0, "an owned ball is grounded")
            t.is_true(p.pos:dist(s.ball) <= control + 1, "ball stays within control radius")
        end
    end)

    t.it("pushes the ball further ahead when sprinting than when standing", function()
        tuning.reset()
        -- Standing: the ball settles a short step ahead of the feet.
        local stand = new_match()
        for _ = 1, 20 do
            match.step(stand, 1 / 60, input())
        end
        local stand_lead = forward_offset(stand)

        -- Sprinting: the same carrier knocks the ball noticeably further ahead
        -- (45 frames: the standing-start ramp must reach knock-on speed first).
        local run = new_match()
        isolate_carrier(run)
        run.players[run.controlled].dribble = 1 -- retention is tested elsewhere
        for _ = 1, 45 do
            match.step(run, 1 / 60, input({ move = Vec2.new(1, 0), sprint = true }))
        end
        t.is_true(run.owner ~= nil, "still dribbling after the run")
        local run_lead = forward_offset(run)
        t.is_true(
            run_lead > stand_lead + 6,
            ("sprinting pushes the ball ahead: run=%.1f stand=%.1f"):format(run_lead, stand_lead)
        )
    end)

    t.it("close control at a jog: glued ball, no knock-ons, nothing to lose", function()
        tuning.reset()
        local s = new_match()
        isolate_carrier(s)
        local jog = input({ move = Vec2.new(1, 0) }) -- no sprint: ordinary running
        local touches = 0
        for _ = 1, 90 do
            match.step(s, 1 / 60, jog)
            t.is_true(s.owner ~= nil, "close control never risks possession")
            for _, e in ipairs(s.events) do
                if e.kind == "touch" then
                    touches = touches + 1
                end
            end
            t.is_true(
                s.players[s.owner].pos:dist(s.ball) <= 30,
                "the ball stays glued near the feet"
            )
        end
        t.eq(touches, 0, "no knock-on kicks below the close-control speed")
    end)

    t.it("dribbles in discrete kicks: repeated touches and a pulsing gap", function()
        tuning.reset()
        local s = new_match()
        isolate_carrier(s)
        s.players[s.controlled].dribble = 1 -- retention is tested elsewhere
        s.players[s.controlled].sprint_meter = 1
        local run = input({ move = Vec2.new(1, 0), sprint = true })
        local touches = 0
        local min_gap, max_gap = math.huge, 0
        for _ = 1, 240 do
            match.step(s, 1 / 60, run)
            if not s.owner then
                break -- a heavy touch got away; that's covered elsewhere
            end
            for _, e in ipairs(s.events) do
                if e.kind == "touch" then
                    touches = touches + 1
                end
            end
            local gap = s.players[s.owner].pos:dist(s.ball)
            min_gap = math.min(min_gap, gap)
            max_gap = math.max(max_gap, gap)
        end
        t.is_true(touches >= 3, ("kick-chase-kick, not a servo: %d touches"):format(touches))
        t.is_true(
            max_gap - min_gap > 8,
            ("the ball runs ahead and comes back: gap %.1f..%.1f"):format(min_gap, max_gap)
        )
    end)

    t.it("hooks the carrier back to a run-on ball; the stick turns the touch", function()
        tuning.reset()
        local s = new_match()
        local me = s.players[s.controlled]
        me.dribble = 1 -- clean feet: this test is about the hook, not error
        s.owner = s.controlled
        me.pos = Vec2.new(300, 270)
        me.facing = Vec2.new(1, 0)
        me.run_vel = Vec2.new(0, 0)
        s.ball = Vec2.new(340, 270) -- the touch ran on: beyond reach, within control
        s.ball_vel = Vec2.new(0, 0)
        for i, p in ipairs(s.players) do
            if i ~= s.controlled then
                -- Park everyone far away: nobody bumps or challenges the carrier.
                p.pos = (p.team == "home") and Vec2.new(80, 40 + i * 30)
                    or Vec2.new(880, 40 + i * 30)
                p.anchor = p.pos
            end
        end
        -- Sprint: knock-on touches only happen above close-control speed.
        local up = input({ move = Vec2.new(0, -1), sprint = true })
        -- Chase phase: the stick points up, but the carrier runs to the BALL.
        for _ = 1, 10 do
            match.step(s, 1 / 60, up)
        end
        t.eq(s.owner, s.controlled, "possession held through the chase")
        t.is_true(me.pos.x > 304, "the carrier ran toward the ball...")
        t.is_true(math.abs(me.pos.y - 270) < 3, "...not where the stick points")
        -- Touch phase: keep holding up until the ball is back at the feet —
        -- the next touch obeys the stick and turns the dribble upward.
        local turned = false
        for _ = 1, 60 do
            match.step(s, 1 / 60, up)
            for _, e in ipairs(s.events) do
                if e.kind == "touch" then
                    turned = true
                end
            end
            if turned then
                break
            end
        end
        t.is_true(turned, "a touch fired once the ball was back at the feet")
        t.is_true(s.ball_vel.y < 0, "and it went where the stick pointed (up)")
        t.is_true(
            math.abs(s.ball_vel.x) < -s.ball_vel.y,
            "clearly upward, not along the old chase line"
        )
    end)

    t.it("loses possession on a heavy touch at pace", function()
        tuning.reset()
        -- Crank the touch heavy and the control tight: a sprint runs the ball away.
        tuning.set("DRIBBLE_PUSH", tuning.by_key.DRIBBLE_PUSH.max)
        tuning.set("DRIBBLE_CONTROL", tuning.by_key.DRIBBLE_CONTROL.min)
        local s = new_match()
        local lost = false
        for _ = 1, 120 do
            match.step(s, 1 / 60, input({ move = Vec2.new(1, 0), sprint = true }))
            if not s.owner then
                lost = true
                break
            end
        end
        tuning.reset()
        t.is_true(lost, "a heavy touch at speed ran the ball out of control")
    end)
end)
