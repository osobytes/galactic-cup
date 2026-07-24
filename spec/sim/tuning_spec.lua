local t = require("spec.support.runner")
local tuning = require("sim.tuning")

t.describe("sim.tuning", function()
    t.it("starts at defaults and clamps sets to each knob's range", function()
        tuning.reset()
        t.eq(tuning.values.MOVE_ACCEL, 1100)
        tuning.set("MOVE_ACCEL", 99999)
        t.eq(tuning.values.MOVE_ACCEL, tuning.by_key.MOVE_ACCEL.max)
        tuning.set("MOVE_ACCEL", -5)
        t.eq(tuning.values.MOVE_ACCEL, tuning.by_key.MOVE_ACCEL.min)
        tuning.reset()
        t.eq(tuning.values.MOVE_ACCEL, 1100)
    end)

    t.it("nudges by steps and resets a single knob", function()
        tuning.reset()
        tuning.nudge("SHOT_WINDUP", 2)
        t.near(tuning.values.SHOT_WINDUP, 0.17, 1e-9)
        t.is_true(not tuning.is_default("SHOT_WINDUP"))
        tuning.reset("SHOT_WINDUP")
        t.is_true(tuning.is_default("SHOT_WINDUP"))
    end)

    t.it("serializes only non-default knobs and round-trips", function()
        tuning.reset()
        t.eq(tuning.serialize(), "")
        tuning.set("AI_STEAL_CD", 2.0)
        tuning.set("PUNT_MAX", 700)
        local blob = tuning.serialize()
        tuning.reset()
        tuning.deserialize(blob)
        t.eq(tuning.values.AI_STEAL_CD, 2.0)
        t.eq(tuning.values.PUNT_MAX, 700)
        t.is_true(tuning.is_default("MOVE_ACCEL"), "untouched knobs stay default")
        tuning.deserialize("garbage\nMOVE_ACCEL=abc\nPUNT_MAX=nope")
        t.is_true(tuning.is_default("PUNT_MAX"), "malformed lines are ignored")
        tuning.reset()
    end)

    t.it("the sim reads live values (a tuned knob changes behavior)", function()
        local match = require("sim.match")
        local teams = require("data.teams")
        local Vec2 = require("core.vec2")
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
            equipment_held = false,
            equipment_pressed = false,
            equipment_released = false,
        }
        -- Zero the shot wind-up: a human shot must now release the same frame.
        tuning.reset()
        tuning.set("SHOT_WINDUP", 0)
        local s =
            match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        s.players[s.controlled].facing = Vec2.new(1, 0)
        match.step(s, 0.016, {
            move = Vec2.new(0, 0),
            shoot = true,
            shoot_held = false,
            pass = false,
            pass_held = false,
            switch = false,
            dash = false,
            dodge = false,
            lob = false,
            sprint = false,
            jockey = false,
            equipment_held = false,
            equipment_pressed = false,
            equipment_released = false,
        })
        match.step(s, 0.016, NO_INPUT) -- windup_timer==0 resolution frame
        t.is_true(s.owner == nil, "with SHOT_WINDUP=0 the shot releases immediately")
        tuning.reset()
    end)
end)
