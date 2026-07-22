local t = require("spec.support.runner")
local metrics = require("sim.metrics")
local Vec2 = require("core.vec2")

-- A minimal MatchState-shaped table: enough surface for the collector.
local function fake_state()
    return {
        players = {
            {
                id = "h_keeper",
                team = "home",
                is_keeper = true,
                vel = Vec2.new(0, 0),
                move_speed = 180,
                sprinting = false,
                dodge_timer = 0,
                keeper_state = "base",
            },
            {
                id = "h1",
                team = "home",
                is_keeper = false,
                vel = Vec2.new(0, 0),
                move_speed = 180,
                sprinting = false,
                dodge_timer = 0,
                keeper_state = "base",
            },
            {
                id = "h2",
                team = "home",
                is_keeper = false,
                vel = Vec2.new(0, 0),
                move_speed = 180,
                sprinting = false,
                dodge_timer = 0,
            },
            {
                id = "a_keeper",
                team = "away",
                is_keeper = true,
                vel = Vec2.new(0, 0),
                move_speed = 180,
                sprinting = false,
                dodge_timer = 0,
            },
            {
                id = "a1",
                team = "away",
                is_keeper = false,
                vel = Vec2.new(0, 0),
                move_speed = 180,
                sprinting = false,
                dodge_timer = 0,
            },
        },
        human_controlled = true,
        controlled = 2,
        score = { home = 0, away = 0 },
        owner = nil,
        events = {},
    }
end

-- One observed frame: set the frame's events/owner, then observe dt.
local function frame(c, s, o)
    s.events = o.events or {}
    s.owner = o.owner
    metrics.observe(c, s, o.dt or 1)
end

t.describe("metrics.observe", function()
    t.it("counts outfield strikes but not keeper punts as shots", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { events = { { kind = "shot", player = "h1" } } })
        frame(c, s, { events = { { kind = "shot", player = "h_keeper" } } })
        frame(c, s, { events = { { kind = "header", player = "a1" } } })
        t.eq(c.shots, 2, "keeper 'shot' events are clearances, not strikes")
    end)

    t.it("resolves a pass as completed when the same team regains ownership", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { events = { { kind = "pass", player = "h1" } } })
        frame(c, s, { owner = 3 }) -- h2 collects
        t.eq(c.passes, 1)
        t.eq(c.passes_completed, 1)
    end)

    t.it("an intercepted pass is incomplete and counts a turnover", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { owner = 2 }) -- h1 owns
        frame(c, s, { events = { { kind = "pass", player = "h1" } } })
        frame(c, s, { owner = 5 }) -- a1 cuts it out
        t.eq(c.passes_completed, 0)
        t.eq(c.turnovers, 1)
    end)

    t.it("splits possession time by owning team and bridges loose spells", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { owner = 2, dt = 3 })
        frame(c, s, { owner = nil, dt = 5 }) -- loose: no turnover, no owned time
        frame(c, s, { owner = 3, dt = 1 }) -- same team regains
        frame(c, s, { owner = 5, dt = 2 })
        t.near(c.own_time.home, 4, 1e-9)
        t.near(c.own_time.away, 2, 1e-9)
        t.eq(c.turnovers, 1, "home->home across the gap is not a turnover")
    end)

    t.it("ownership flicker below the settle threshold is not a turnover", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { owner = 2, dt = 1 }) -- settled home
        -- A poke-and-scramble: the ball ping-pongs in sub-settle touches.
        frame(c, s, { owner = 5, dt = 0.2 })
        frame(c, s, { owner = 2, dt = 0.2 })
        frame(c, s, { owner = 5, dt = 0.2 })
        frame(c, s, { owner = 2, dt = 1 }) -- home rides out the scramble
        t.eq(c.turnovers, 0, "the scramble never settled with the other team")
    end)

    t.it("records goals from score deltas and tracks droughts", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { dt = 30 })
        s.score.home = 1
        frame(c, s, { dt = 1 })
        frame(c, s, { dt = 50 })
        local m = metrics.finish(c, s)
        t.eq(m.goals_home, 1)
        t.near(c.goals[1].t, 31, 1e-9)
        t.near(m.longest_drought_s, 50, 1e-9, "the post-goal tail is a drought")
    end)

    t.it("observes keeper state, release depth, and chip outcomes without changing play", function()
        local s = fake_state()
        local c = metrics.new(s)
        s.players[1].keeper_state = "advance"
        s.players[4].keeper_state = "set"
        frame(c, s, {
            dt = 0.5,
            events = {
                {
                    kind = "shot",
                    player = "h1",
                    shot_type = "chip",
                    keeper_state = "advance",
                    keeper_depth = 42,
                    on_target = true,
                },
            },
        })
        s.score.home = 1
        frame(c, s, { dt = 0.5 })
        frame(c, s, {
            events = {
                { kind = "parry", player = "a_keeper", keeper_state = "set" },
            },
        })

        local result = metrics.finish(c, s)
        t.near(result.keeper_advance_s, 2)
        t.near(result.keeper_set_s, 2)
        t.eq(result.keeper_shot_depth_mean, 42)
        t.eq(result.chip_shots, 1)
        t.eq(result.chip_on_target, 1)
        t.eq(result.chip_goals, 1)
        t.eq(result.chip_conversion, 1)
        t.eq(result.keeper_goals_advance, 1)
        t.eq(result.keeper_saves_set, 1)
    end)

    t.it("keeps aerial goals and context-free saves explicitly unclassified", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { events = { { kind = "header", player = "a1" } } })
        s.score.away = 1
        frame(c, s, {})
        frame(c, s, { events = { { kind = "catch", player = "h_keeper" } } })

        local result = metrics.finish(c, s)
        t.eq(result.keeper_goals_unclassified, 1)
        t.eq(result.keeper_saves_unclassified, 1)
        t.eq(result.keeper_goals_base, 0)
        t.eq(result.keeper_saves_base, 0)
    end)

    t.it("separates controlled and team-AI dribble usage", function()
        local s = fake_state()
        local c = metrics.new(s)
        frame(c, s, { owner = 2, dt = 1 }) -- controlled close control
        s.players[2].vel = Vec2.new(260, 0)
        s.players[2].sprinting = true
        s.players[2].dodge_timer = 0.1
        frame(c, s, {
            owner = 2,
            dt = 1,
            events = {
                { kind = "touch", player = "h1" },
                { kind = "juke", player = "h1" },
            },
        })
        frame(c, s, { owner = nil, events = { { kind = "touch", player = "h1" } } })
        s.players[5].vel = Vec2.new(-180, 0)
        frame(c, s, { owner = 5, dt = 2 }) -- team AI, close control
        local m = metrics.finish(c, s)
        t.near(m.controlled_dribble_carry_s, 2, 1e-9)
        t.near(m.controlled_dribble_close_share, 0.5, 1e-9)
        t.near(m.controlled_dribble_sprint_share, 0.5, 1e-9)
        t.eq(m.controlled_jukes, 1)
        t.near(m.controlled_dribble_touches_per_min, 30, 1e-9)
        t.near(m.controlled_dribble_heavy_losses_per_min, 30, 1e-9)
        t.near(m.ai_dribble_carry_s, 2, 1e-9)
        t.near(m.ai_dribble_close_share, 1, 1e-9)
    end)
end)

t.describe("metrics.finish shape", function()
    t.it("computes decided_late as when the winner went ahead for good", function()
        local s = fake_state()
        local c = metrics.new(s)
        c.t = 100
        c.goals = {
            { t = 10, team = "away" },
            { t = 40, team = "home" },
            { t = 60, team = "home" }, -- home ahead for good from here
        }
        s.score.home, s.score.away = 2, 1
        c.prev_home, c.prev_away = 2, 1
        local m = metrics.finish(c, s)
        t.near(m.decided_late, 0.6, 1e-9)
        t.eq(m.lead_changes, 1, "away led, then home took over")
    end)

    t.it("a draw is undecided until the end", function()
        local s = fake_state()
        local c = metrics.new(s)
        c.t = 100
        c.goals = { { t = 10, team = "home" }, { t = 90, team = "away" } }
        s.score.home, s.score.away = 1, 1
        local m = metrics.finish(c, s)
        t.near(m.decided_late, 1, 1e-9)
    end)

    t.it("rate metrics are nil when their denominator never happened", function()
        local s = fake_state()
        local c = metrics.new(s)
        c.t = 100
        local m = metrics.finish(c, s)
        t.is_true(m.shots_per_goal == nil, "no goals -> no shots_per_goal")
        t.is_true(m.save_rate == nil, "nothing on target -> no save_rate")
        t.is_true(m.pass_completion == nil, "no passes -> no completion")
        t.is_true(m.possession_balance == nil, "never owned -> no balance")
    end)
end)

t.describe("metrics.desirability", function()
    local band = { 0, 2, 5, 8 }
    t.it("is 1 inside the good band and 0 at the hard edges", function()
        t.eq(metrics.desirability(3, band), 1)
        t.eq(metrics.desirability(0, band), 0)
        t.eq(metrics.desirability(8, band), 0)
        t.eq(metrics.desirability(10, band), 0)
    end)
    t.it("falls off linearly between the edges", function()
        t.near(metrics.desirability(1, band), 0.5, 1e-9)
        t.near(metrics.desirability(6.5, band), 0.5, 1e-9)
    end)
end)

t.describe("metrics.fun_score", function()
    local function good_match()
        return {
            goals_total = 3,
            shots_per_goal = 4,
            save_rate = 0.6,
            pass_completion = 0.7,
            turnovers_per_min = 4,
            possession_balance = 0.5,
            longest_drought_s = 20,
            decided_late = 0.8,
        }
    end

    t.it("scores 1 when every metric sits in its band", function()
        local score = metrics.fun_score(good_match())
        t.near(score, 1, 1e-9)
    end)

    t.it("a single collapsed dimension zeroes the score (geometric mean)", function()
        local m = good_match()
        m.goals_total = 0
        local score = metrics.fun_score(m)
        t.eq(score, 0)
    end)

    t.it("skips missing metrics instead of defaulting them", function()
        local m = good_match()
        m.save_rate = nil
        local score, per = metrics.fun_score(m)
        t.near(score, 1, 1e-9)
        t.is_true(per.save_rate == nil)
    end)
end)

t.describe("metrics.aggregate", function()
    t.it("computes mean/sd/min/max per key, skipping nils", function()
        local agg = metrics.aggregate({
            { goals_total = 2, save_rate = 0.5 },
            { goals_total = 4 },
            { goals_total = 6, save_rate = 0.7 },
        })
        t.eq(agg.goals_total.n, 3)
        t.near(agg.goals_total.mean, 4, 1e-9)
        t.near(agg.goals_total.sd, 2, 1e-9)
        t.eq(agg.goals_total.min, 2)
        t.eq(agg.goals_total.max, 6)
        t.eq(agg.save_rate.n, 2)
        t.near(agg.save_rate.mean, 0.6, 1e-9)
    end)
end)
