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

    t.it("pushes the ball further ahead when running than when standing", function()
        tuning.reset()
        -- Standing: the ball settles a short step ahead of the feet.
        local stand = new_match()
        for _ = 1, 20 do
            match.step(stand, 1 / 60, input())
        end
        local stand_lead = forward_offset(stand)

        -- Running: the same carrier pushes the ball noticeably further ahead.
        local run = new_match()
        for _ = 1, 20 do
            match.step(run, 1 / 60, input({ move = Vec2.new(1, 0), sprint = true }))
        end
        t.is_true(run.owner ~= nil, "still dribbling after the run")
        local run_lead = forward_offset(run)
        t.is_true(
            run_lead > stand_lead + 6,
            ("running pushes the ball ahead: run=%.1f stand=%.1f"):format(run_lead, stand_lead)
        )
    end)

    t.it("loses possession on a heavy touch at pace", function()
        tuning.reset()
        -- Crank the touch heavy and the control tight: a sprint runs the ball away.
        tuning.set("DRIBBLE_LEAD", tuning.by_key.DRIBBLE_LEAD.max)
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
