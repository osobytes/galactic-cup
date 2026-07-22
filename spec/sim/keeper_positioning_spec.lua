local Vec2 = require("core.vec2")
local player_pool = require("data.players")
local teams = require("data.teams")
local fixed_clock = require("sim.fixed_clock")
local input_frame = require("sim.input_frame")
local match = require("sim.match")
local t = require("spec.support.runner")

local DT = fixed_clock.TICK_SECONDS
local SUPPORT_DISTANCE = 120

---@return table<string, PlayerData>
local function player_index()
    local result = {}
    for _, source in ipairs(player_pool) do
        result[source.id] = source
    end
    return result
end

---@class KeeperPositionScenario
---@field state MatchState
---@field keeper integer
---@field carrier integer
---@field support integer
---@field defender integer

---@param defending_team "home"|"away"
---@param ball_pos Vec2
---@return KeeperPositionScenario
local function scenario(defending_team, ball_pos)
    local attacking_team = defending_team == "home" and "away" or "home"
    local by_id = player_index()
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion, by_id)
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 42,
        players_by_id = by_id,
        input_ownership = ownership,
    })
    local keeper_idx, carrier_idx, support_idx, defender_idx
    for index, player in ipairs(state.players) do
        if player.team == defending_team and player.is_keeper then
            keeper_idx = index
        elseif player.team == defending_team and not player.is_keeper and not defender_idx then
            defender_idx = index
        elseif player.team == attacking_team and not player.is_keeper then
            if not carrier_idx then
                carrier_idx = index
            elseif not support_idx then
                support_idx = index
            end
        end
    end
    local keeper_value = assert(keeper_idx)
    local carrier_value = assert(carrier_idx)
    local support_value = assert(support_idx)
    local defender_value = assert(defender_idx)

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

    local defending_keeper = state.players[keeper_value]
    defending_keeper.pos = Vec2.new(defending_team == "home" and 12 or 948, 270)
    defending_keeper.anchor = defending_keeper.pos
    local carrier = state.players[carrier_value]
    local facing_x = carrier.team == "home" and 1 or -1
    carrier.facing = Vec2.new(facing_x, 0)
    carrier.pos = ball_pos:add(Vec2.new(-facing_x * 18, 0))
    carrier.anchor = carrier.pos
    state.owner = carrier_value
    state.ball = ball_pos
    state.ball_vel = Vec2.new(0, 0)
    state.ball_z = 0
    state.ball_vz = 0
    state.pickup_cd = 0
    return {
        state = state,
        keeper = keeper_value,
        carrier = carrier_value,
        support = support_value,
        defender = defender_value,
    }
end

---@param state MatchState
local function step(state)
    match.step(state, DT, assert(input_frame.neutral(state.input_tick)))
end

---@param value KeeperPositionScenario
---@param offset number
local function place_support(value, offset)
    local carrier = value.state.players[value.carrier]
    local support = value.state.players[value.support]
    support.pos = carrier.pos:add(Vec2.new(0, offset))
    support.anchor = support.pos
end

t.describe("keeper behavior integration", function()
    t.it("moves through the physical neutral depth range in both directions", function()
        for _, mirrored in ipairs({
            { team = "home", far = Vec2.new(480, 400), near = Vec2.new(161, 270), direction = 1 },
            { team = "away", far = Vec2.new(480, 140), near = Vec2.new(799, 270), direction = -1 },
        }) do
            local far = scenario(mirrored.team, mirrored.far)
            local far_keeper = far.state.players[far.keeper]
            for _ = 1, 120 do
                step(far.state)
            end
            local goal_line_x = mirrored.team == "home" and 0 or 960
            local far_depth = (far_keeper.pos.x - goal_line_x) * mirrored.direction
            t.near(far_depth, 12, 1e-6, mirrored.team .. " far neutral depth")
            t.eq(far_keeper.keeper_state, "base")

            local near = scenario(mirrored.team, mirrored.near)
            local near_keeper = near.state.players[near.keeper]
            local max_near_depth = 0
            for _ = 1, 120 do
                step(near.state)
                local step_depth = (near_keeper.pos.x - goal_line_x) * mirrored.direction
                max_near_depth = math.max(max_near_depth, step_depth)
                t.is_true(
                    step_depth <= 18.000001,
                    mirrored.team .. " actual neutral movement stays below its cap"
                )
            end
            local near_depth = (near_keeper.pos.x - goal_line_x) * mirrored.direction
            t.is_true(near_depth > 17.5, mirrored.team .. " keeper actually steps off its inset")
            t.is_true(max_near_depth > 17.5, mirrored.team .. " reaches the dynamic depth")
            t.eq(near_keeper.keeper_state, "base")
        end
    end)

    t.it("advances on the conservative centre ray without an anticipation stat gate", function()
        for _, mirrored in ipairs({
            { team = "home", ball = Vec2.new(150, 220), direction = 1 },
            { team = "away", ball = Vec2.new(810, 220), direction = -1 },
        }) do
            local value = scenario(mirrored.team, mirrored.ball)
            local keeper = value.state.players[value.keeper]
            local start_x = keeper.pos.x
            keeper.keeper_anticipation = 0

            step(value.state)

            t.eq(keeper.keeper_state, "advance")
            t.is_true((keeper.pos.x - start_x) * mirrored.direction >= 0)
        end
    end)

    t.it("contains at moderate depth when the attacker has visible support", function()
        for _, mirrored in ipairs({
            { team = "home", ball = Vec2.new(150, 220) },
            { team = "away", ball = Vec2.new(810, 220) },
        }) do
            local value = scenario(mirrored.team, mirrored.ball)
            place_support(value, SUPPORT_DISTANCE)
            step(value.state)
            t.eq(value.state.players[value.keeper].keeper_state, "contain")
        end
    end)

    t.it("uses defender context for a controlled touch but attacks a loose touch", function()
        local controlled = scenario("home", Vec2.new(150, 220))
        local defender = controlled.state.players[controlled.defender]
        defender.pos = controlled.state.players[controlled.carrier].pos:add(Vec2.new(0, 40))
        defender.anchor = defender.pos
        step(controlled.state)
        t.eq(controlled.state.players[controlled.keeper].keeper_state, "contain")

        local loose = scenario("home", Vec2.new(150, 220))
        local loose_carrier = loose.state.players[loose.carrier]
        loose_carrier.pos = loose.state.ball:add(Vec2.new(40, 0))
        loose_carrier.anchor = loose_carrier.pos
        local loose_defender = loose.state.players[loose.defender]
        loose_defender.pos = loose_carrier.pos:add(Vec2.new(0, 40))
        loose_defender.anchor = loose_defender.pos
        step(loose.state)
        t.eq(loose.state.players[loose.keeper].keeper_state, "advance")
    end)

    t.it("uses the same top-of-tick loose-touch threshold at both goals", function()
        for _, mirrored in ipairs({
            { team = "home", ball = Vec2.new(150, 270) },
            { team = "away", ball = Vec2.new(810, 270) },
        }) do
            local value = scenario(mirrored.team, mirrored.ball)
            local carrier = value.state.players[value.carrier]
            local direction = carrier.team == "home" and 1 or -1
            carrier.pos = value.state.ball:add(Vec2.new(-direction * 23.9, 0))
            carrier.anchor = carrier.pos
            carrier.run_vel = Vec2.new(-direction * carrier.move_speed, 0)
            carrier.vel = carrier.run_vel
            local defender = value.state.players[value.defender]
            defender.pos = carrier.pos:add(Vec2.new(0, 40))
            defender.anchor = defender.pos

            step(value.state)

            t.eq(
                value.state.players[value.keeper].keeper_state,
                "contain",
                mirrored.team .. " keeper uses the mirrored pre-movement controlled touch"
            )
        end
    end)

    t.it("sets for a readable ground windup and retreats for a chip windup", function()
        local ground = scenario("home", Vec2.new(150, 270))
        local ground_keeper = ground.state.players[ground.keeper]
        local ground_carrier = ground.state.players[ground.carrier]
        ground_carrier.windup_timer = 0.1
        ground_carrier.windup_shot = {
            dir = Vec2.new(-1, 0),
            speed = 400,
            vz = 0,
            spin = 0,
            shot_type = "ground",
        }
        step(ground.state)
        t.eq(ground_keeper.keeper_state, "set")
        t.is_true(ground_keeper.keeper_set > 0)

        local chip = scenario("home", Vec2.new(150, 270))
        local chip_keeper = chip.state.players[chip.keeper]
        chip_keeper.pos = Vec2.new(40, 270)
        chip_keeper.keeper_state = "contain"
        local chip_carrier = chip.state.players[chip.carrier]
        chip_carrier.windup_timer = 0.1
        chip_carrier.windup_shot = {
            dir = Vec2.new(-1, 0),
            speed = 400,
            vz = 350,
            spin = 0,
            shot_type = "chip",
        }
        step(chip.state)
        t.eq(chip_keeper.keeper_state, "retreat")
        t.eq(chip_keeper.keeper_set, 0)
    end)

    t.it("retreats for a prepared through ball with time to respond", function()
        local value = scenario("home", Vec2.new(150, 270))
        local keeper = value.state.players[value.keeper]
        keeper.pos = Vec2.new(40, 270)
        keeper.keeper_state = "contain"
        value.state.owner = nil
        value.state.ball_vel = Vec2.new(-300, 0)
        value.state.players[value.carrier].receive_timer = 1

        step(value.state)

        t.eq(keeper.keeper_state, "retreat")
    end)

    t.it("holds recover when an attacker gets behind an advance", function()
        local value = scenario("home", Vec2.new(30, 270))
        local keeper = value.state.players[value.keeper]
        keeper.pos = Vec2.new(40, 270)
        keeper.run_vel = Vec2.new(0, 0)
        keeper.keeper_state = "advance"
        local start = keeper.pos

        step(value.state)

        t.eq(keeper.keeper_state, "recover")
        t.is_true(keeper.pos.x > start.x - 10, "recover does not snap back to the line")
        t.is_true(keeper.keeper_state_timer > 0)
    end)

    t.it("preserves bespoke save and claim movement priorities", function()
        local diving = scenario("home", Vec2.new(150, 270))
        local diving_keeper = diving.state.players[diving.keeper]
        local dive_start = diving_keeper.pos
        diving_keeper.dive_timer = 0.2
        diving_keeper.dive_target = dive_start:add(Vec2.new(0, 20))
        diving_keeper.dive_dir = Vec2.new(0, 1)
        step(diving.state)
        t.is_true(diving_keeper.pos.y > dive_start.y)

        local claiming = scenario("home", Vec2.new(100, 270))
        local claiming_keeper = claiming.state.players[claiming.keeper]
        claiming.state.owner = nil
        claiming.state.ball_vel = Vec2.new(0, 0)
        local claim_start = claiming_keeper.pos
        step(claiming.state)
        t.is_true(claiming_keeper.pos.x >= claim_start.x)
    end)
end)
