local Vec2 = require("core.vec2")
local player_pool = require("data.players")
local teams = require("data.teams")
local fixed_clock = require("sim.fixed_clock")
local input_frame = require("sim.input_frame")
local keeper = require("sim.keeper")
local match = require("sim.match")
local t = require("spec.support.runner")

local DT = fixed_clock.TICK_SECONDS
local CLAIM_DEPTH = 160
local KEEPER_1V1_SUPPORT = 120

---@param keeper_mental integer
---@return table<string, PlayerData>
local function player_index(keeper_mental)
    local result = {}
    for _, source in ipairs(player_pool) do
        local copy = {}
        for key, value in pairs(source) do
            copy[key] = value
        end
        copy.stats = {
            pace = source.stats.pace,
            strength = source.stats.strength,
            technique = source.stats.technique,
            stamina = source.stats.stamina,
            mental = source.id == "ozzo" and keeper_mental or source.stats.mental,
        }
        ---@cast copy PlayerData
        result[copy.id] = copy
    end
    return result
end

---@class KeeperPositionScenario
---@field state MatchState
---@field keeper integer
---@field carrier integer
---@field support integer

---@param keeper_mental integer
---@param ball_pos Vec2
---@return KeeperPositionScenario
local function scenario(keeper_mental, ball_pos)
    local by_id = player_index(keeper_mental)
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion, by_id)
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 42,
        players_by_id = by_id,
        input_ownership = ownership,
    })
    local keeper_idx, carrier_idx, support_idx
    for index, player in ipairs(state.players) do
        if player.team == "home" and player.is_keeper then
            keeper_idx = index
        elseif player.team == "away" and not player.is_keeper then
            if not carrier_idx then
                carrier_idx = index
            elseif not support_idx then
                support_idx = index
            end
        end
    end
    local keeper_idx_value = assert(keeper_idx)
    local carrier_idx_value = assert(carrier_idx)
    local support_idx_value = assert(support_idx)

    local home_y = 60
    local away_y = 60
    for _, player in ipairs(state.players) do
        if player.team == "home" and not player.is_keeper then
            player.pos = Vec2.new(560, home_y)
            home_y = home_y + 120
        elseif player.team == "away" and not player.is_keeper then
            player.pos = Vec2.new(700, away_y)
            away_y = away_y + 120
        end
        player.anchor = player.pos
        player.vel = Vec2.new(0, 0)
        player.run_vel = Vec2.new(0, 0)
        player.receive_timer = 0
    end

    local defending_keeper = state.players[keeper_idx_value]
    defending_keeper.pos = Vec2.new(12, 270)
    defending_keeper.anchor = defending_keeper.pos
    local carrier = state.players[carrier_idx_value]
    carrier.facing = Vec2.new(-1, 0)
    carrier.pos = ball_pos:add(Vec2.new(18, 0))
    carrier.anchor = carrier.pos
    state.owner = carrier_idx_value
    state.ball = ball_pos
    state.ball_vel = Vec2.new(0, 0)
    state.ball_z = 0
    state.ball_vz = 0
    state.pickup_cd = 0
    return {
        state = state,
        keeper = keeper_idx_value,
        carrier = carrier_idx_value,
        support = support_idx_value,
    }
end

---@param state MatchState
local function step(state)
    match.step(state, DT, assert(input_frame.neutral(state.input_tick)))
end

---@param state MatchState
---@param carrier_idx integer
---@param ball_pos Vec2
local function move_carrier(state, carrier_idx, ball_pos)
    local carrier = state.players[carrier_idx]
    carrier.pos = ball_pos:add(Vec2.new(18, 0))
    carrier.anchor = carrier.pos
    carrier.facing = Vec2.new(-1, 0)
    carrier.vel = Vec2.new(0, 0)
    carrier.run_vel = Vec2.new(0, 0)
    state.ball = ball_pos
    state.ball_vel = Vec2.new(0, 0)
end

---@return KeeperPositionScenario
local function locked_scenario()
    local value = scenario(8, Vec2.new(150, 220))
    step(value.state)
    t.is_true(value.state.players[value.keeper].keeper_1v1_target ~= nil, "precondition: locked")
    return value
end

t.describe("keeper arc positioning integration", function()
    t.it("pins the authored keeper's normal central depth trace", function()
        local value = scenario(8, Vec2.new(480, 270))
        local defending_keeper = value.state.players[value.keeper]
        t.eq(defending_keeper.keeper_aggression, 42)
        local trace = {
            { ball_x = 480, target_x = 0 },
            { ball_x = 400, target_x = 10.5 },
            { ball_x = 320, target_x = 21 },
            { ball_x = 240, target_x = 31.5 },
            { ball_x = 160, target_x = 42 },
        }
        for _, point in ipairs(trace) do
            local target = keeper.arc_target({
                keeper_pos = defending_keeper.pos,
                ball_pos = Vec2.new(point.ball_x, 270),
                goal = value.state.goal_home,
                team = "home",
                aggression = defending_keeper.keeper_aggression,
                in_1v1 = false,
            })
            t.near(target.x, point.target_x, 1e-9, "ball depth " .. point.ball_x)
        end
    end)

    t.it("steers through locomotion to different depths and keeps the 28px guard target", function()
        local deep = scenario(8, Vec2.new(400, 270))
        local approaching = scenario(8, Vec2.new(CLAIM_DEPTH + 0.01, 500))
        local approaching_keeper = approaching.state.players[approaching.keeper]
        local expected = keeper.arc_target({
            keeper_pos = approaching_keeper.pos,
            ball_pos = approaching.state.ball,
            goal = approaching.state.goal_home,
            team = "home",
            aggression = approaching_keeper.keeper_aggression,
            in_1v1 = false,
        })
        t.near(expected.y, approaching.state.goal_home.y + approaching.state.goal_home.h / 2 + 28)

        local start = approaching_keeper.pos
        step(approaching.state)
        t.is_true(
            approaching_keeper.pos:dist(expected) > 1,
            "arc positioning must steer, not teleport"
        )
        t.is_true(
            approaching_keeper.pos:dist(start) < 1,
            "the first acceleration tick stays incremental"
        )
        for _ = 1, 120 do
            step(deep.state)
            step(approaching.state)
        end
        t.is_true(
            approaching_keeper.pos.x > deep.state.players[deep.keeper].pos.x + 10,
            "the keeper comes farther out as the ball approaches"
        )
        t.is_true(
            approaching_keeper.pos.y > start.y,
            "the keeper steers toward the guarded lateral target"
        )
    end)

    t.it(
        "uses the exact claim depth and conservative support radius for 1v1 eligibility",
        function()
            local at_depth = scenario(8, Vec2.new(CLAIM_DEPTH, 220))
            step(at_depth.state)
            t.is_true(at_depth.state.players[at_depth.keeper].keeper_1v1_target ~= nil)

            local beyond_depth = scenario(8, Vec2.new(CLAIM_DEPTH + 0.01, 220))
            step(beyond_depth.state)
            t.eq(beyond_depth.state.players[beyond_depth.keeper].keeper_1v1_target, nil)

            local supported = scenario(8, Vec2.new(150, 220))
            supported.state.players[supported.support].pos =
                supported.state.players[supported.carrier].pos:add(Vec2.new(0, KEEPER_1V1_SUPPORT))
            step(supported.state)
            t.eq(supported.state.players[supported.keeper].keeper_1v1_target, nil)

            local alone = scenario(8, Vec2.new(150, 220))
            alone.state.players[alone.support].pos =
                alone.state.players[alone.carrier].pos:add(Vec2.new(0, KEEPER_1V1_SUPPORT + 0.01))
            step(alone.state)
            t.is_true(alone.state.players[alone.keeper].keeper_1v1_target ~= nil)
        end
    )

    t.it("enters hold-and-narrow at the inclusive 0.6 anticipation gate", function()
        local at_gate = scenario(6, Vec2.new(150, 220))
        step(at_gate.state)
        t.near(at_gate.state.players[at_gate.keeper].keeper_anticipation, 0.6)
        t.is_true(at_gate.state.players[at_gate.keeper].keeper_1v1_target ~= nil)

        local below_gate = scenario(5, Vec2.new(150, 220))
        step(below_gate.state)
        t.near(below_gate.state.players[below_gate.keeper].keeper_anticipation, 0.5)
        t.eq(below_gate.state.players[below_gate.keeper].keeper_1v1_target, nil)
        t.is_true(
            below_gate.state.players[below_gate.keeper].pos.x < 13,
            "a sub-threshold keeper follows the normal reactive arc instead of rushing"
        )
    end)

    t.it("locks the 1v1 target laterally while the carrier feints", function()
        local value = locked_scenario()
        local defending_keeper = value.state.players[value.keeper]
        local locked = assert(defending_keeper.keeper_1v1_target)
        move_carrier(value.state, value.carrier, Vec2.new(150, 340))
        step(value.state)
        local after = assert(defending_keeper.keeper_1v1_target)
        t.eq(after.x, locked.x)
        t.eq(after.y, locked.y)
    end)
end)

t.describe("keeper hold-and-narrow exits", function()
    t.it("clears when possession changes", function()
        local value = locked_scenario()
        local teammate = 2
        value.state.owner = teammate
        value.state.players[teammate].facing = Vec2.new(1, 0)
        value.state.ball = value.state.players[teammate].pos:add(Vec2.new(18, 0))
        step(value.state)
        t.eq(value.state.players[value.keeper].keeper_1v1_target, nil)
    end)

    t.it("clears when the carrier leaves the claim depth", function()
        local value = locked_scenario()
        move_carrier(value.state, value.carrier, Vec2.new(CLAIM_DEPTH + 0.01, 220))
        step(value.state)
        t.eq(value.state.players[value.keeper].keeper_1v1_target, nil)
    end)

    t.it("clears when support arrives", function()
        local value = locked_scenario()
        value.state.players[value.support].pos =
            value.state.players[value.carrier].pos:add(Vec2.new(0, KEEPER_1V1_SUPPORT))
        step(value.state)
        t.eq(value.state.players[value.keeper].keeper_1v1_target, nil)
    end)

    t.it("clears in the release tick when the carrier shoots", function()
        local value = locked_scenario()
        local carrier = value.state.players[value.carrier]
        carrier.windup_timer = 0
        carrier.windup_shot = {
            dir = Vec2.new(-1, 0),
            speed = 300,
            vz = 0,
            spin = 0,
        }
        step(value.state)
        t.eq(value.state.owner, nil)
        t.eq(value.state.players[value.keeper].keeper_1v1_target, nil)
    end)

    t.it("clears when a loose-ball claim begins", function()
        local value = locked_scenario()
        value.state.owner = nil
        value.state.ball = Vec2.new(100, 270)
        value.state.ball_vel = Vec2.new(0, 0)
        step(value.state)
        t.eq(value.state.players[value.keeper].keeper_1v1_target, nil)
        t.is_true(
            value.state.players[value.keeper].pos.x > 12,
            "the higher-priority claim pursuit moves toward the loose ball"
        )
    end)

    t.it("clears in the same tick as a smother", function()
        local value = locked_scenario()
        value.state.players[value.keeper].pos = value.state.ball:add(Vec2.new(-20, 0))
        value.state.players[value.keeper].run_vel = Vec2.new(0, 0)
        step(value.state)
        t.eq(value.state.owner, value.keeper)
        t.eq(value.state.players[value.keeper].keeper_1v1_target, nil)
    end)

    t.it("clears while a pending save has movement priority", function()
        local value = locked_scenario()
        local defending_keeper = value.state.players[value.keeper]
        value.state.owner = nil
        value.state.ball = Vec2.new(110, 270)
        value.state.ball_vel = Vec2.new(-200, 0)
        value.state.pickup_cd = 0.3
        defending_keeper.save_pending = "catch"
        defending_keeper.save_timer = 1
        defending_keeper.save_vx = -200
        defending_keeper.dive_delay = 0.2
        step(value.state)
        t.eq(defending_keeper.keeper_1v1_target, nil)
        t.is_true(defending_keeper.dive_delay > 0)
    end)

    t.it("clears while an active dive keeps its bespoke movement", function()
        local value = locked_scenario()
        local defending_keeper = value.state.players[value.keeper]
        local start = defending_keeper.pos
        defending_keeper.dive_timer = 0.2
        defending_keeper.dive_target = start:add(Vec2.new(0, 20))
        defending_keeper.dive_dir = Vec2.new(0, 1)
        step(value.state)
        t.eq(defending_keeper.keeper_1v1_target, nil)
        t.is_true(defending_keeper.pos.y > start.y, "the existing dive path still moves")
    end)
end)
