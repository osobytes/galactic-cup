local match = require("sim.match")
local t = require("spec.support.runner")
local teams = require("data.teams")
local Vec2 = require("core.vec2")

---@param values table?
---@return MatchInput
local function input(values)
    values = values or {}
    return {
        move = values.move or Vec2.new(0, 0),
        shoot = false,
        shoot_held = false,
        pass = values.pass or false,
        pass_held = false,
        switch = false,
        dash = false,
        dodge = false,
        lob = false,
        sprint = false,
        jockey = false,
    }
end

local NO_INPUT = input()

local PASSER_POSITIONS = {
    Vec2.new(210, 125),
    Vec2.new(245, 170),
    Vec2.new(280, 220),
    Vec2.new(300, 270),
    Vec2.new(280, 320),
    Vec2.new(245, 370),
    Vec2.new(210, 415),
}

---@class BackpassScenario
---@field state MatchState
---@field keeper integer
---@field presser integer

---@param passer_pos Vec2
---@param pressure_side number
---@return BackpassScenario
local function scenario(passer_pos, pressure_side)
    local state = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 41,
    })
    local passer = state.controlled
    local keeper, presser
    for i, player in ipairs(state.players) do
        if player.team == "home" and player.is_keeper then
            keeper = i
        elseif player.team == "away" and not player.is_keeper and not presser then
            presser = i
        end
    end
    keeper = assert(keeper)
    presser = assert(presser)

    local keeper_pos = Vec2.new(64, 270)
    local aim = keeper_pos:sub(passer_pos):normalized()
    state.owner = passer
    state.ball = passer_pos:add(aim:scale(6))
    state.ball_vel = Vec2.new(0, 0)
    state.players[passer].pos = passer_pos
    state.players[passer].anchor = passer_pos
    state.players[passer].facing = aim
    state.players[keeper].pos = keeper_pos
    state.players[keeper].anchor = keeper_pos
    state.players[keeper].run_vel = Vec2.new(0, 0)

    local home_y = 60
    local away_y = 50
    for i, player in ipairs(state.players) do
        if player.team == "home" and i ~= passer and i ~= keeper then
            player.pos = Vec2.new(700, home_y)
            player.anchor = player.pos
            home_y = home_y + 100
        elseif player.team == "away" and i ~= presser then
            player.pos = Vec2.new(880, away_y)
            player.anchor = player.pos
            away_y = away_y + 90
        end
    end

    -- The opponent presses from the passer's upfield shoulder. It is close
    -- enough to chase the released ball, but not already standing between the
    -- passer and keeper; an interception should have to be earned.
    local pressure_offset = Vec2.new(34, 30 * pressure_side)
    state.players[presser].pos = passer_pos:add(pressure_offset)
    state.players[presser].anchor = state.players[presser].pos

    match.step(state, 1 / 60, input({ pass = true, move = aim }))
    t.is_true(state.owner == nil, "the back-pass released")
    t.is_true(state.players[keeper].receive_timer > 0, "the keeper is the designated receiver")
    return { state = state, keeper = keeper, presser = presser }
end

---@alias BackpassOutcome "keeper"|"attacker"|"own_goal"|"unresolved"

---@param passer_pos Vec2
---@param pressure_side number
---@return BackpassOutcome outcome
---@return number keeper_progress
local function play(passer_pos, pressure_side)
    local value = scenario(passer_pos, pressure_side)
    local state = value.state
    local keeper_start = state.players[value.keeper].pos
    local toward_pass = state.ball:sub(keeper_start):normalized()
    local furthest_progress = 0
    for _ = 1, 360 do
        match.step(state, 1 / 60, NO_INPUT)
        local keeper_offset = state.players[value.keeper].pos:sub(keeper_start)
        local progress = keeper_offset.x * toward_pass.x + keeper_offset.y * toward_pass.y
        furthest_progress = math.max(furthest_progress, progress)
        if state.score.away > 0 then
            return "own_goal", furthest_progress
        elseif state.owner == value.keeper then
            return "keeper", furthest_progress
        elseif state.owner and state.players[state.owner].team == "away" then
            return "attacker", furthest_progress
        end
    end
    return "unresolved", furthest_progress
end

t.describe("keeper pressured back-pass reception matrix", function()
    t.it("meets deliberate passes from every angle before the press or goal line", function()
        local received, attacker_wins, own_goals, unresolved = 0, 0, 0, 0
        local least_progress = math.huge
        for _, passer_pos in ipairs(PASSER_POSITIONS) do
            for _, pressure_side in ipairs({ -1, 1 }) do
                local outcome, progress = play(passer_pos, pressure_side)
                least_progress = math.min(least_progress, progress)
                if outcome == "keeper" then
                    received = received + 1
                elseif outcome == "attacker" then
                    attacker_wins = attacker_wins + 1
                elseif outcome == "own_goal" then
                    own_goals = own_goals + 1
                else
                    unresolved = unresolved + 1
                end
            end
        end

        local total = #PASSER_POSITIONS * 2
        t.eq(own_goals, 0, "a designated back-pass must not roll through the keeper")
        t.eq(attacker_wins, 0, "a trailing presser must not beat the keeper to its pass")
        t.eq(unresolved, 0, "every designated back-pass should resolve")
        t.eq(
            received,
            total,
            ("keeper received %d/%d pressured back-passes"):format(received, total)
        )
        t.is_true(least_progress > 0, "the keeper must move toward every incoming back-pass")
    end)
end)
