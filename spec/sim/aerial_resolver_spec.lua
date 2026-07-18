local t = require("spec.support.runner")
local aerial = require("sim.aerial")
local stats = require("sim.stats")
local Vec2 = require("core.vec2")

---@param overrides table?
---@return AerialContext
local function context(overrides)
    overrides = overrides or {}
    return {
        ball_pos = overrides.ball_pos or Vec2.new(10, 0),
        ball_vel = overrides.ball_vel or Vec2.new(-120, 0),
        ball_z = overrides.ball_z or 50,
        ball_vz = overrides.ball_vz or -120,
        player_pos = overrides.player_pos or Vec2.new(0, 0),
        player_vel = overrides.player_vel or Vec2.new(0, 0),
        facing = overrides.facing or Vec2.new(1, 0),
        move_speed = overrides.move_speed or 200,
        skill = overrides.skill or 0.6,
        strength = overrides.strength or 0.5,
        opponent_distance = overrides.opponent_distance or 100,
        anticipated = overrides.anticipated == nil and true or overrides.anticipated,
        instability = overrides.instability or 0,
        extra_reach = overrides.extra_reach or 0,
        extra_lift = overrides.extra_lift or 0,
    }
end

t.describe("aerial contact resolver", function()
    t.it("derives reception and strike skills from the existing stat vocabulary", function()
        local technical = { pace = 5, strength = 4, technique = 9, stamina = 5, mental = 7 }
        local raw = { pace = 5, strength = 8, technique = 2, stamina = 5, mental = 3 }
        t.is_true(stats.first_touch(technical) > stats.first_touch(raw))
        t.is_true(stats.volley(technical) > stats.volley(raw))
        t.is_true(stats.bicycle(technical) > stats.bicycle(raw))
        t.is_true(stats.header(raw) > stats.volley(raw), "strength and mental keep headers viable")
    end)

    t.it("chooses chest control above the standing leg band", function()
        local contact = assert(aerial.best_contact(context({ ball_z = 55 }), "receive"))
        t.eq(contact.style, "chest_control")
        t.is_true(not contact.jumping)
    end)

    t.it("marks a high header as jumping", function()
        local contact = assert(aerial.best_contact(context({ ball_z = 88 }), "strike"))
        t.eq(contact.style, "header")
        t.is_true(contact.jumping)
        t.is_true(contact.jump_ratio > 0)
    end)

    t.it("rejects a ball above the maximum jumping reach", function()
        t.eq(aerial.best_contact(context({ ball_z = 110 }), "strike"), nil)
    end)

    t.it("requires overhead or behind geometry for a bicycle", function()
        local in_front = context({ ball_pos = Vec2.new(18, 0), ball_z = 60 })
        local front_contact = assert(aerial.best_contact(in_front, "acrobatic"))
        t.is_true(front_contact.style ~= "bicycle", "front ball falls back to a conventional hit")

        local behind = context({ ball_pos = Vec2.new(-10, 0), ball_z = 60 })
        local behind_contact = assert(aerial.best_contact(behind, "acrobatic"))
        t.eq(behind_contact.style, "bicycle")
        t.is_true(behind_contact.jumping)
    end)

    t.it("makes stretch, pace, jump, instability, and pressure increase difficulty", function()
        local easy = assert(aerial.best_contact(context({ ball_z = 38 }), "receive"))
        local hard = assert(aerial.best_contact(
            context({
                ball_pos = Vec2.new(25, 0),
                ball_vel = Vec2.new(-560, 0),
                ball_z = 60,
                ball_vz = -480,
                opponent_distance = 8,
                anticipated = false,
                instability = 1,
            }),
            "receive"
        ))
        t.is_true(hard.difficulty > easy.difficulty)
    end)

    t.it("is deterministic for the same seed and context", function()
        local ctx = context({ ball_z = 60, ball_pos = Vec2.new(-10, 0) })
        local contact = assert(aerial.best_contact(ctx, "acrobatic"))
        local a = aerial.resolve(ctx, contact, 4471)
        local b = aerial.resolve(ctx, contact, 4471)
        t.eq(a.outcome, b.outcome)
        t.eq(a.rng, b.rng)
        t.near(a.angle_error, b.angle_error)
        t.near(a.weight_error, b.weight_error)
    end)

    t.it("raises both outcome probabilities when skill increases", function()
        local low_ctx = context({ skill = 0.2 })
        local high_ctx = context({ skill = 0.9 })
        local low_contact = assert(aerial.best_contact(low_ctx, "receive"))
        local high_contact = assert(aerial.best_contact(high_ctx, "receive"))
        local low = aerial.resolve(low_ctx, low_contact, 91)
        local high = aerial.resolve(high_ctx, high_contact, 91)
        t.is_true(high.contact_probability > low.contact_probability)
        t.is_true(high.clean_probability > low.clean_probability)
    end)

    t.it("rewards position and skill in aerial contests", function()
        local good_ctx = context({ skill = 0.9, ball_pos = Vec2.new(4, 0) })
        local bad_ctx = context({ skill = 0.2, ball_pos = Vec2.new(25, 0) })
        local good_contact = assert(aerial.best_contact(good_ctx, "receive"))
        local bad_contact = assert(aerial.best_contact(bad_ctx, "receive"))
        local good = aerial.claim_score(good_ctx, good_contact, 0, 0, 0)
        local bad = aerial.claim_score(bad_ctx, bad_contact, 0, 0, 0)
        t.is_true(good > bad)
    end)
end)
