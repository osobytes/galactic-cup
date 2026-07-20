local t = require("spec.support.runner")
local keeper = require("sim.keeper")
local Vec2 = require("core.vec2")

local HOME_GOAL = { x = -30, y = 215, w = 30, h = 110 }
local AWAY_GOAL = { x = 960, y = 215, w = 30, h = 110 }

---@param ball_pos Vec2
---@param aggression number?
---@param in_1v1 boolean?
---@return KeeperPositionContext
local function home_context(ball_pos, aggression, in_1v1)
    return {
        keeper_pos = Vec2.new(12, 270),
        ball_pos = ball_pos,
        goal = HOME_GOAL,
        team = "home",
        aggression = aggression or 80,
        in_1v1 = in_1v1 or false,
    }
end

---@param ball_pos Vec2
---@param aggression number?
---@param in_1v1 boolean?
---@return KeeperPositionContext
local function away_context(ball_pos, aggression, in_1v1)
    return {
        keeper_pos = Vec2.new(948, 270),
        ball_pos = ball_pos,
        goal = AWAY_GOAL,
        team = "away",
        aggression = aggression or 80,
        in_1v1 = in_1v1 or false,
    }
end

t.describe("keeper.arc_target", function()
    t.it("moves monotonically off the home goal line as the ball approaches", function()
        local midfield = keeper.arc_target(home_context(Vec2.new(480, 270)))
        local approaching = keeper.arc_target(home_context(Vec2.new(320, 270)))
        local claim_edge = keeper.arc_target(home_context(Vec2.new(160, 270)))

        t.near(midfield.x, 0)
        t.is_true(approaching.x > midfield.x)
        t.is_true(claim_edge.x > approaching.x)
        t.near(claim_edge.x, 80)
    end)

    t.it("mirrors the approaching arc for the away goal", function()
        local midfield = keeper.arc_target(away_context(Vec2.new(480, 270)))
        local approaching = keeper.arc_target(away_context(Vec2.new(640, 270)))
        local claim_edge = keeper.arc_target(away_context(Vec2.new(800, 270)))

        t.near(midfield.x, 960)
        t.is_true(approaching.x < midfield.x)
        t.is_true(claim_edge.x < approaching.x)
        t.near(claim_edge.x, 880)
    end)

    t.it("holds deep and centred while the ball is beyond midfield", function()
        local home = keeper.arc_target(home_context(Vec2.new(700, 400)))
        local away = keeper.arc_target(away_context(Vec2.new(260, 140)))

        t.near(home.x, 0)
        t.near(home.y, 270)
        t.near(away.x, 960)
        t.near(away.y, 270)
    end)

    t.it("clamps lateral targets to the 28-pixel guard on both sides", function()
        local low = keeper.arc_target(home_context(Vec2.new(160, 540), 120))
        local high = keeper.arc_target(away_context(Vec2.new(800, 0), 120))

        t.near(low.y, 298)
        t.near(high.y, 242)
    end)

    t.it("uses maximum aggression depth for a one-on-one", function()
        local normal_home = keeper.arc_target(home_context(Vec2.new(320, 270), 80))
        local one_on_one_home = keeper.arc_target(home_context(Vec2.new(320, 270), 80, true))
        local normal_away = keeper.arc_target(away_context(Vec2.new(640, 270), 80))
        local one_on_one_away = keeper.arc_target(away_context(Vec2.new(640, 270), 80, true))

        t.near(normal_home.x, 40)
        t.near(one_on_one_home.x, 80)
        t.near(normal_away.x, 920)
        t.near(one_on_one_away.x, 880)
    end)

    t.it("never exceeds aggression along the goal-to-ball ray", function()
        local home = home_context(Vec2.new(160, 500), 65, true)
        local away = away_context(Vec2.new(800, 40), 65, true)
        local home_target = keeper.arc_target(home)
        local away_target = keeper.arc_target(away)
        local home_center = Vec2.new(0, 270)
        local away_center = Vec2.new(960, 270)

        t.is_true(home_target:dist(home_center) <= 65)
        t.is_true(away_target:dist(away_center) <= 65)
    end)

    t.it("uses keeper position as a deterministic fallback for a degenerate ray", function()
        local context = home_context(Vec2.new(0, 270), 60, true)
        context.keeper_pos = Vec2.new(20, 270)
        local target = keeper.arc_target(context)

        t.near(target.x, 60)
        t.near(target.y, 270)
    end)
end)

t.describe("keeper.save_style", function()
    t.it("leaves the 26-pixel smother boundary to the claim branch", function()
        local ok = pcall(keeper.save_style, 26, 0, 100)
        t.is_true(not ok)
        t.eq(keeper.save_style(26.000001, 100, 100), "spread")
    end)

    t.it("keeps the 78-pixel boundary in the spread style", function()
        t.eq(keeper.save_style(78, 100, 100), "spread")
        t.eq(keeper.save_style(78.000001, 40, 100), "central")
    end)

    t.it("includes exactly 40 percent of reach in the central style", function()
        t.eq(keeper.save_style(100, 40, 100), "central")
        t.eq(keeper.save_style(100, 40.000001, 100), "stretch")
    end)
end)

t.describe("keeper.commit_lead", function()
    t.it("clamps anticipation and negative windups to safe bounds", function()
        t.near(keeper.commit_lead(-1, 2), 0)
        t.near(keeper.commit_lead(0.5, 2), 1)
        t.near(keeper.commit_lead(2, 2), 2)
        t.near(keeper.commit_lead(0.5, -2), 0)
    end)

    t.it("is monotonic in anticipation across the supported range", function()
        local previous = keeper.commit_lead(0, 0.3)
        for anticipation = 0.1, 1, 0.1 do
            local current = keeper.commit_lead(anticipation, 0.3)
            t.is_true(current >= previous)
            t.is_true(current >= 0 and current <= 0.3)
            previous = current
        end
    end)
end)
