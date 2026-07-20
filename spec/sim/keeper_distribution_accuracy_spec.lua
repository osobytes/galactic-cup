local Vec2 = require("core.vec2")
local rng = require("core.rng")
local t = require("spec.support.runner")
local match = require("sim.match")
local player_pool = require("data.players")
local teams = require("data.teams")

local GRAVITY = 900

---@param technique integer
---@return table<string, PlayerData>
local function players_by_id(technique)
    local by_id = {}
    for _, player in ipairs(player_pool) do
        local player_technique = player.id == "ozzo" and technique or player.stats.technique
        by_id[player.id] = {
            id = player.id,
            name = player.name,
            planet = player.planet,
            position = player.position,
            species = player.species,
            presentation_species = player.presentation_species,
            stats = {
                pace = player.stats.pace,
                strength = player.stats.strength,
                technique = player_technique,
                stamina = player.stats.stamina,
                mental = player.stats.mental,
            },
            trait = player.trait,
        }
    end
    return by_id
end

---@param o table?
---@return MatchInput
local function input(o)
    o = o or {}
    return {
        move = o.move or Vec2.new(0, 0),
        shoot = o.shoot or false,
        shoot_held = o.shoot_held or false,
        pass = o.pass or false,
        pass_held = o.pass_held or false,
        switch = false,
        dash = false,
        dodge = false,
        lob = false,
        sprint = false,
        jockey = false,
    }
end

---@param technique integer
---@param seed integer?
---@return MatchState
local function hand_scenario(technique, seed)
    local s = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        players_by_id = players_by_id(technique),
        seed = seed or 73,
    })
    s.owner = 1
    s.controlled = 1
    local keeper = s.players[1]
    keeper.pos = Vec2.new(60, 270)
    keeper.facing = Vec2.new(1, 0)
    keeper.hold_timer = 30
    s.ball = Vec2.new(66, 270)
    s.players[2].pos = Vec2.new(260, 180)
    s.players[3].pos = Vec2.new(520, 390)
    s.players[4].pos = Vec2.new(80, 40)
    s.players[5].pos = Vec2.new(80, 500)
    for index, player in ipairs(s.players) do
        if player.team == "away" then
            player.pos = Vec2.new(850, 30 + index * 45)
        end
        player.anchor = player.pos
        player.vel = Vec2.new(0, 0)
    end
    return s
end

---@param s MatchState
---@return integer?
local function receiver(s)
    for index, player in ipairs(s.players) do
        if player.receive_timer > 0 then
            return index
        end
    end
    return nil
end

---@param s MatchState
---@return Vec2
local function lofted_landing(s)
    local flight_time = 2 * s.ball_vz / GRAVITY
    return s.players[1].pos:add(s.ball_vel:scale(flight_time))
end

---@param state integer
---@return integer
local function after_two_rolls(state)
    state = rng.roll(state)
    state = rng.roll(state)
    return state
end

t.describe("keeper hand-distribution accuracy", function()
    t.it("tightens seeded landing error monotonically without changing outlet or tier", function()
        local previous_error = math.huge
        local first_direction
        for technique = 0, 10 do
            local s = hand_scenario(technique)
            local ideal = s.players[2].pos
            local aim = ideal:sub(s.players[1].pos):normalized()
            s.players[1].pass_charge = 0.2

            match.step(s, 0, input({ pass = true, move = aim }))

            t.eq(receiver(s), 2, "technique must not change the selected outlet")
            t.is_true(s.ball_vz > 0, "technique must not change the lofted throw tier")
            local offset = lofted_landing(s):sub(ideal)
            local error_distance = offset:length()
            t.is_true(
                error_distance <= previous_error + 1e-6,
                "higher technique must not increase matched-seed landing error"
            )
            previous_error = error_distance
            if not first_direction then
                first_direction = offset:normalized()
            else
                t.near(
                    offset:normalized().x * first_direction.x
                        + offset:normalized().y * first_direction.y,
                    1,
                    1e-6,
                    "matched seeds retain one error direction"
                )
            end
            if technique == 10 then
                t.near(error_distance, 4, 1e-6, "elite accuracy retains nonzero error")
            end
        end
    end)

    t.it("draws only when the hand release happens and always draws twice", function()
        local preview = hand_scenario(10)
        local preview_rng = preview.rng
        local preview_distribution_rng = preview.distribution_rng
        match.step(preview, 0, input({ pass_held = true, move = Vec2.new(1, 0) }))
        t.eq(preview.rng, preview_rng, "preview must not consume distribution RNG")
        t.eq(
            preview.distribution_rng,
            preview_distribution_rng,
            "preview must not consume the distribution substream"
        )
        t.is_true(preview.owner ~= nil, "preview does not release the ball")

        local released = hand_scenario(10)
        local before_release = released.rng
        local before_distribution = released.distribution_rng
        released.players[1].pass_charge = 0.2
        match.step(released, 0, input({ pass = true, move = Vec2.new(1, -0.45) }))
        t.eq(released.rng, before_release, "hand release leaves unrelated match RNG unchanged")
        t.eq(
            released.distribution_rng,
            after_two_rolls(before_distribution),
            "accuracy 1 hand release consumes the shared angle and magnitude draws"
        )
    end)

    t.it("keeps a covered throw on its planned safe side", function()
        local s = hand_scenario(0, 19)
        s.players[2].pos = Vec2.new(260, 270)
        s.players[3].pos = Vec2.new(40, 100)
        s.players[4].pos = Vec2.new(40, 440)
        s.players[5].pos = Vec2.new(30, 40)
        s.players[7].pos = Vec2.new(230, 270)
        local planned = Vec2.new(315, 270)
        s.players[1].pass_charge = 0.2

        match.step(s, 0, input({ pass = true, move = Vec2.new(1, 0) }))

        t.eq(receiver(s), 2)
        local executed = lofted_landing(s)
        t.is_true(executed.x >= planned.x, "execution error cannot turn back toward cover")
        t.is_true(
            executed:dist(s.players[7].pos) >= planned:dist(s.players[7].pos),
            "safe-side reflection preserves cover separation"
        )
    end)

    t.it("keeps ground-tier pace fixed while kicked distributions draw nothing", function()
        local low = hand_scenario(0, 91)
        local high = hand_scenario(10, 91)
        low.human_controlled = false
        high.human_controlled = false
        low.players[1].hold_timer = 0
        high.players[1].hold_timer = 0
        local low_rng, high_rng = low.rng, high.rng
        local low_distribution_rng, high_distribution_rng =
            low.distribution_rng, high.distribution_rng

        match.step(low, 0, input())
        match.step(high, 0, input())

        t.eq(receiver(low), receiver(high), "accuracy must not change the safe outlet")
        t.eq(low.ball_vz, 0, "low-technique release retains the ground tier")
        t.eq(high.ball_vz, 0, "high-technique release retains the ground tier")
        t.near(low.ball_vel:length(), high.ball_vel:length(), 1e-6, "ground pace is unchanged")
        t.eq(low.rng, low_rng)
        t.eq(high.rng, high_rng)
        t.eq(low.distribution_rng, after_two_rolls(low_distribution_rng))
        t.eq(high.distribution_rng, after_two_rolls(high_distribution_rng))

        local kicked = hand_scenario(0, 91)
        kicked.players[1].feet_ball = true
        local kicked_rng = kicked.rng
        local kicked_distribution_rng = kicked.distribution_rng
        match.step(kicked, 0, input({ pass = true, move = Vec2.new(1, -0.45) }))
        t.eq(kicked.rng, kicked_rng, "kicked backpass distribution consumes no throw RNG")
        t.eq(
            kicked.distribution_rng,
            kicked_distribution_rng,
            "kicked backpass distribution leaves the throw substream untouched"
        )

        local punted = hand_scenario(0, 91)
        local punted_distribution_rng = punted.distribution_rng
        match.step(punted, 0, input({ shoot = true, move = Vec2.new(1, 0) }))
        for _ = 1, 12 do
            match.step(punted, 1 / 60, input())
        end
        t.is_true(punted.owner == nil, "punt releases after its windup")
        t.eq(
            punted.distribution_rng,
            punted_distribution_rng,
            "punt leaves the hand-throw substream untouched"
        )
    end)
end)
