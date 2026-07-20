local t = require("spec.support.runner")
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
}

---@return MatchState
---@return MatchPlayer
local function new_save_state()
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 73,
    })
    local keeper
    local parking_x = 80
    for _, player in ipairs(state.players) do
        if player.team == "away" and player.is_keeper then
            keeper = player
        elseif not player.is_keeper then
            player.pos = Vec2.new(parking_x, 60)
            parking_x = parking_x + 40
        end
    end
    keeper = assert(keeper)
    keeper.pos = Vec2.new(938, 220)
    keeper.run_vel = Vec2.new(0, 0)
    keeper.vel = Vec2.new(0, 0)
    state.owner = nil
    state.pickup_cd = 1
    state.block_grace = 1
    state.ball_z = 0
    state.ball_vz = 0
    return state, keeper
end

---@param distance number
---@param dive_distance number
---@param speed number?
---@return MatchState
---@return MatchPlayer
local function setup_attempt(distance, dive_distance, speed)
    local state, keeper = new_save_state()
    local horizontal_speed = speed or 500
    state.ball = Vec2.new(keeper.pos.x - distance, keeper.pos.y)
    state.ball_vel = Vec2.new(horizontal_speed, dive_distance * horizontal_speed / distance)
    return state, keeper
end

---@param state MatchState
---@param kind string
---@return MatchEvent?
local function event_of(state, kind)
    for _, event in ipairs(state.events) do
        if event.kind == kind then
            return event
        end
    end
    return nil
end

---@param state MatchState
---@return MatchEvent?
local function save_event(state)
    return event_of(state, "catch") or event_of(state, "parry")
end

t.describe("keeper save-style integration", function()
    t.it("propagates the exact 26 and 78 pixel spread boundaries", function()
        local smother_edge, edge_keeper = setup_attempt(26, 0)
        match.step(smother_edge, 0, NO_INPUT)
        local close_event = assert(save_event(smother_edge))
        t.eq(close_event.save_style, nil, "26px remains outside save-style classification")
        t.eq(edge_keeper.save_style, nil)

        local above_smother = setup_attempt(26.000001, 0)
        match.step(above_smother, 0, NO_INPUT)
        t.eq(assert(save_event(above_smother)).save_style, "spread")

        local spread_edge, spread_keeper = setup_attempt(78, 50)
        match.step(spread_edge, 0, NO_INPUT)
        t.eq(spread_keeper.save_style, "spread")

        local beyond_spread, beyond_keeper = setup_attempt(78.000001, 20)
        match.step(beyond_spread, 0, NO_INPUT)
        t.eq(beyond_keeper.save_style, "central")
    end)

    t.it("uses effective physical reach for the exact central/stretch boundary", function()
        local state, keeper = setup_attempt(100, 0)
        keeper.reach = 100
        state.ball_vel.y = 40 * state.ball_vel.x / 100
        match.step(state, 0, NO_INPUT)
        t.eq(keeper.save_style, "central")

        local beyond, beyond_keeper = setup_attempt(100, 0)
        beyond_keeper.reach = 100
        beyond.ball_vel.y = 40.000001 * beyond.ball_vel.x / 100
        match.step(beyond, 0, NO_INPUT)
        t.eq(beyond_keeper.save_style, "stretch")
    end)

    t.it("keeps identical geometry, outcome, RNG, and style deterministic", function()
        local first = setup_attempt(100, 35, 420)
        local second = setup_attempt(100, 35, 420)

        match.step(first, 0, NO_INPUT)
        match.step(second, 0, NO_INPUT)

        local first_event = save_event(first)
        local second_event = save_event(second)
        t.eq(first.rng, second.rng)
        t.eq(first.players[6].save_pending, second.players[6].save_pending)
        t.eq(first.players[6].save_style, second.players[6].save_style)
        if first_event or second_event then
            local first_resolved = assert(first_event)
            local second_resolved = assert(second_event)
            t.eq(first_resolved.kind, second_resolved.kind)
            t.eq(first_resolved.save_style, second_resolved.save_style)
        end
    end)

    t.it("carries style on catch/parry then clears it at completed resolution", function()
        local state, keeper = setup_attempt(29, 0, 300)
        match.step(state, 0, NO_INPUT)

        local event = assert(save_event(state))
        t.eq(event.save_style, "spread")
        t.eq(keeper.save_style, nil)
    end)

    t.it("does not change the away-from-goal parry invariant", function()
        local state, keeper = setup_attempt(29, 20, 500)
        keeper.save_pending = "parry"
        keeper.save_timer = 1
        keeper.save_vx = state.ball_vel.x
        keeper.save_style = "spread"
        local before_score = state.score.home
        local before_rng = state.rng
        match.step(state, 0, NO_INPUT)

        local event = assert(save_event(state))
        t.eq(event.kind, "parry")
        t.eq(event.save_style, "spread")
        t.eq(state.score.home, before_score)
        t.eq(state.rng, before_rng)
        t.is_true(state.ball_vel.x < 0, "away keeper parries away from its goal")
        t.is_true(state.ball.x < state.goal_away.x, "parry stays outside the goal line")
        t.eq(keeper.save_style, nil)
    end)
end)

t.describe("keeper near-miss tip events", function()
    t.it(
        "emits once through exactly 110 percent of effective reach without side effects",
        function()
            local state, keeper = setup_attempt(120, 0)
            local effective_reach = keeper.reach -- includes the currently neutral species seam
            local dive_distance = effective_reach * 1.1
            state.ball_vel.y = dive_distance * state.ball_vel.x / 120
            local velocity = state.ball_vel
            local score = state.score.home
            local rng_state = state.rng
            local tip_count = 0

            for _ = 1, 3 do
                match.step(state, 0, NO_INPUT)
                if event_of(state, "tip") then
                    tip_count = tip_count + 1
                end
            end

            t.eq(tip_count, 1)
            t.is_true(keeper.save_tip_emitted)
            t.eq(state.owner, nil)
            t.eq(state.score.home, score)
            t.eq(state.rng, rng_state)
            t.eq(state.ball_vel.x, velocity.x)
            t.eq(state.ball_vel.y, velocity.y)
            t.eq(keeper.save_style, nil)
        end
    )

    t.it("emits nothing beyond the 110 percent boundary", function()
        local state, keeper = setup_attempt(120, 0)
        local dive_distance = keeper.reach * 1.1 + 0.000001
        state.ball_vel.y = dive_distance * state.ball_vel.x / 120

        match.step(state, 0, NO_INPUT)

        t.eq(event_of(state, "tip"), nil)
        t.is_true(not keeper.save_tip_emitted)
        t.eq(keeper.save_style, nil)
    end)
end)

t.describe("keeper save-style lifecycle", function()
    t.it("clears style when a pending shot reverses or dies before contact", function()
        local reversed, reversed_keeper = new_save_state()
        reversed.ball = Vec2.new(800, 220)
        reversed.ball_vel = Vec2.new(-300, 0)
        reversed_keeper.save_pending = "catch"
        reversed_keeper.save_timer = 1
        reversed_keeper.save_vx = 300
        reversed_keeper.save_style = "central"
        reversed_keeper.save_tip_emitted = true
        match.step(reversed, 0, NO_INPUT)
        t.eq(reversed_keeper.save_style, nil)
        t.is_true(not reversed_keeper.save_tip_emitted)

        local dead, dead_keeper = new_save_state()
        dead.ball = Vec2.new(800, 220)
        dead.ball_vel = Vec2.new(20, 0)
        dead_keeper.save_pending = "catch"
        dead_keeper.save_timer = 1
        dead_keeper.save_vx = 300
        dead_keeper.save_style = "central"
        dead_keeper.save_tip_emitted = true
        match.step(dead, 0, NO_INPUT)
        t.eq(dead_keeper.save_style, nil)
        t.is_true(not dead_keeper.save_tip_emitted)
    end)

    t.it("clears style at recovery completion and when possession cancels the attempt", function()
        local recovery, recovery_keeper = new_save_state()
        recovery.owner = 2
        recovery_keeper.dive_timer = 0.01
        recovery_keeper.save_style = "stretch"
        recovery_keeper.save_tip_emitted = true
        match.step(recovery, 0.02, NO_INPUT)
        t.eq(recovery_keeper.save_style, nil)
        t.is_true(not recovery_keeper.save_tip_emitted)

        local owned, owned_keeper = new_save_state()
        owned.owner = 2
        owned_keeper.save_style = "central"
        owned_keeper.save_tip_emitted = true
        match.step(owned, 0, NO_INPUT)
        t.eq(owned_keeper.save_style, nil)
        t.is_true(not owned_keeper.save_tip_emitted)
    end)

    t.it("clears style and the one-shot guard on kickoff reset", function()
        local state, keeper = new_save_state()
        keeper.save_style = "stretch"
        keeper.save_tip_emitted = true
        keeper.receive_timer = 1
        state.ball = Vec2.new(965, 270)
        state.ball_vel = Vec2.new(600, 0)
        state.ball_z = 0
        state.ball_vz = 0

        match.step(state, 0.01, NO_INPUT)

        t.eq(state.score.home, 1)
        t.eq(keeper.save_style, nil)
        t.is_true(not keeper.save_tip_emitted)
    end)
end)
