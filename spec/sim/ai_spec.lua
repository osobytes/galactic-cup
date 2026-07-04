local t = require("spec.support.runner")
local ai = require("sim.ai")
local Vec2 = require("core.vec2")

t.describe("ai.closest", function()
    t.it("returns the index of the nearest position", function()
        local ps = { Vec2.new(10, 0), Vec2.new(3, 0), Vec2.new(20, 0) }
        t.eq(ai.closest(Vec2.new(0, 0), ps), 2)
    end)

    t.it("honours the exclude index", function()
        local ps = { Vec2.new(1, 0), Vec2.new(5, 0) }
        t.eq(ai.closest(Vec2.new(0, 0), ps, 1), 2)
    end)

    t.it("returns nil when there are no candidates", function()
        t.is_true(ai.closest(Vec2.new(0, 0), {}) == nil)
    end)
end)

t.describe("ai.steer", function()
    t.it("snaps to the target when within range", function()
        local np, dir = ai.steer(Vec2.new(0, 0), Vec2.new(3, 0), 10)
        t.eq(np.x, 3)
        t.eq(np.y, 0)
        t.near(dir:length(), 1)
    end)

    t.it("moves at most max_dist toward the target", function()
        local np = ai.steer(Vec2.new(0, 0), Vec2.new(100, 0), 10)
        t.near(np.x, 10)
    end)

    t.it("yields a zero direction when already at the target", function()
        local _, dir = ai.steer(Vec2.new(5, 5), Vec2.new(5, 5), 10)
        t.eq(dir.x, 0)
        t.eq(dir.y, 0)
    end)
end)

t.describe("ai.pursue", function()
    t.it("returns the target itself when it is not moving", function()
        local p = ai.pursue(Vec2.new(0, 0), Vec2.new(50, 0), Vec2.new(0, 0), 0.01)
        t.eq(p.x, 50)
        t.eq(p.y, 0)
    end)

    t.it("leads a moving target ahead of its position", function()
        -- dist 100, lead 0.01 -> horizon 1.0s; vel (10,0) -> +10 ahead
        local p = ai.pursue(Vec2.new(0, 0), Vec2.new(100, 0), Vec2.new(10, 0), 0.01)
        t.near(p.x, 110)
    end)
end)

t.describe("ai.interpose", function()
    t.it("returns the midpoint at frac 0.5", function()
        local m = ai.interpose(Vec2.new(0, 0), Vec2.new(10, 20), 0.5)
        t.eq(m.x, 5)
        t.eq(m.y, 10)
    end)

    t.it("returns the endpoints at 0 and 1", function()
        local a = ai.interpose(Vec2.new(2, 3), Vec2.new(9, 9), 0)
        local b = ai.interpose(Vec2.new(2, 3), Vec2.new(9, 9), 1)
        t.eq(a.x, 2)
        t.eq(b.x, 9)
    end)
end)

t.describe("ai.separation", function()
    t.it("cancels to zero for symmetric neighbours", function()
        local off = ai.separation(Vec2.new(0, 0), { Vec2.new(5, 0), Vec2.new(-5, 0) }, 20)
        t.near(off.x, 0)
        t.near(off.y, 0)
    end)

    t.it("pushes directly away from a single neighbour", function()
        local off = ai.separation(Vec2.new(0, 0), { Vec2.new(5, 0) }, 20)
        t.is_true(off.x < 0, "pushed away along -x")
        t.near(off.y, 0)
    end)

    t.it("ignores neighbours outside the radius", function()
        local off = ai.separation(Vec2.new(0, 0), { Vec2.new(50, 0) }, 20)
        t.eq(off.x, 0)
        t.eq(off.y, 0)
    end)
end)

t.describe("ai.support_spot", function()
    local field = { w = 960, h = 540 }

    t.it("prefers the central spot over a wide one when both are open", function()
        local carrier = Vec2.new(300, 270)
        local central = Vec2.new(600, 270)
        local wide = Vec2.new(600, 60)
        local best = ai.support_spot(carrier, { central, wide }, { Vec2.new(900, 900) }, 1, field)
        t.eq(best.x, 600)
        t.eq(best.y, 270)
    end)

    t.it("avoids a spot sitting on an opponent", function()
        local carrier = Vec2.new(300, 270)
        local open = Vec2.new(600, 270)
        local marked = Vec2.new(620, 280)
        local best = ai.support_spot(carrier, { open, marked }, { Vec2.new(620, 280) }, 1, field)
        t.eq(best.x, 600)
    end)

    t.it("prefers a lane-clear spot when the central lane is blocked", function()
        local carrier = Vec2.new(300, 270)
        local blocked = Vec2.new(600, 270) -- opponent stands on this passing lane
        local clear = Vec2.new(600, 100)
        local best = ai.support_spot(carrier, { blocked, clear }, { Vec2.new(450, 270) }, 1, field)
        t.eq(best.y, 100)
    end)
end)

t.describe("ai.pass_intercept", function()
    -- Match-like tuning: friction 1.2/s, control radius 22 px, collect cap 350 px/s.
    local F, REACH, CAP = 1.2, 22, 350

    t.it("flags a slow pass a nearby defender can step onto", function()
        -- 200px pass at 320 px/s with a defender parked on the midpoint: the
        -- ball needs ~0.39s to get there, the defender is already waiting.
        local f = ai.pass_intercept(Vec2.new(0, 0), Vec2.new(200, 0), 320, F, {
            { pos = Vec2.new(100, 0), speed = 200 },
        }, REACH, CAP)
        t.is_true(f ~= nil, "the lane is cut")
        t.is_true(f > 0 and f < 1, "the fraction lies on the lane")
    end)

    t.it("a hard-driven ball outruns the same defender", function()
        -- Launched at 620 px/s the ball never decays below the collection cap
        -- within 200px (620 - 1.2*200 = 380 > 350): nothing on the lane can take it.
        local f = ai.pass_intercept(Vec2.new(0, 0), Vec2.new(200, 0), 620, F, {
            { pos = Vec2.new(100, 0), speed = 200 },
        }, REACH, CAP)
        t.is_true(f == nil, "too fast to collect anywhere on the lane")
    end)

    t.it("is safe when the defender cannot reach any point in time", function()
        local f = ai.pass_intercept(Vec2.new(0, 0), Vec2.new(200, 0), 320, F, {
            { pos = Vec2.new(100, 250), speed = 200 },
        }, REACH, CAP)
        t.is_true(f == nil, "a far defender never beats the ball")
    end)

    t.it("a defender chasing from behind the passer never catches the ball", function()
        local f = ai.pass_intercept(Vec2.new(0, 0), Vec2.new(200, 0), 320, F, {
            { pos = Vec2.new(-60, 0), speed = 200 },
        }, REACH, CAP)
        t.is_true(f == nil, "the ball stays ahead of a trailing chaser")
    end)

    t.it("returns nil with no threats", function()
        t.is_true(
            ai.pass_intercept(Vec2.new(0, 0), Vec2.new(200, 0), 320, F, {}, REACH, CAP) == nil
        )
    end)
end)

t.describe("ai.assign_marks", function()
    t.it("matches each defender to its nearest opponent", function()
        local defs = { Vec2.new(0, 0), Vec2.new(100, 0) }
        local opps = { Vec2.new(5, 0), Vec2.new(105, 0) }
        local m = ai.assign_marks(defs, opps, {}, 0)
        t.eq(m[1], 1)
        t.eq(m[2], 2)
    end)

    t.it("breaks ties deterministically by index", function()
        local defs = { Vec2.new(0, 0), Vec2.new(0, 0) }
        local opps = { Vec2.new(5, 0), Vec2.new(5, 0) }
        local m = ai.assign_marks(defs, opps, {}, 0)
        t.eq(m[1], 1)
        t.eq(m[2], 2)
    end)

    t.it("keeps a prior mark under a small perturbation but switches under a large one", function()
        local defs = { Vec2.new(0, 0) }
        local opps = { Vec2.new(10, 0), Vec2.new(8, 0) } -- o2 is nearer
        t.eq(ai.assign_marks(defs, opps, {}, 5)[1], 2, "no history -> nearest (o2)")
        t.eq(ai.assign_marks(defs, opps, { [1] = 1 }, 5)[1], 1, "sticky bonus keeps o1")
        t.eq(ai.assign_marks(defs, opps, { [1] = 1 }, 1)[1], 2, "tiny bonus -> switches to o2")
    end)
end)
