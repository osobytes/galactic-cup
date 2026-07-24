local Vec2 = require("core.vec2")
local t = require("spec.support.runner")
local match = require("sim.match")
local species = require("sim.species")
local stats = require("sim.stats")
local player_pool = require("data.players")
local showcase_pool = require("data.showcase_player_compatibility")
local species_pool = require("data.species")
local teams = require("data.teams")

---@type SpeciesData
local SWIFT = {
    id = "swift_fixture",
    name = "Swift Fixture",
    modifiers = { pace = 1, strength = 0, technique = 0, stamina = 0, mental = 0 },
    verb = "burst",
    skill = nil,
}

---@return table<string, SpeciesData>
local function test_species()
    return { neutral = species_pool.neutral, swift_fixture = SWIFT }
end

---@return table<string, PlayerData>
local function players_by_id()
    local by_id = {}
    for _, player in ipairs(player_pool) do
        by_id[player.id] = {
            id = player.id,
            name = player.name,
            number = player.number,
            position = player.position,
            stats = player.stats,
            presentation_id = player.presentation_id,
            cosmetic_variant_id = player.cosmetic_variant_id,
            loadout_id = player.loadout_id,
        }
    end
    return by_id
end

---@param overrides table<string, string>?
---@return table<string, ShowcasePlayerCompatibilityData>
local function showcase_by_id(overrides)
    local by_id = {}
    for id, player in pairs(showcase_pool) do
        by_id[id] = {
            player_id = id,
            planet = player.planet,
            species = (overrides and overrides[id]) or player.species,
            presentation_species = player.presentation_species,
            trait = player.trait,
        }
    end
    return by_id
end

---@param players MatchPlayer[]
---@param id string
---@return MatchPlayer
local function player_named(players, id)
    ---@type MatchPlayer?
    local found = nil
    for _, player in ipairs(players) do
        if player.id == id then
            found = player
            break
        end
    end
    return assert(found, "missing match player: " .. id)
end

---@param by_id table<string, PlayerData>
---@param showcase table<string, ShowcasePlayerCompatibilityData>
---@return MatchState
local function new_match(by_id, showcase)
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        players_by_id = by_id,
        species_by_id = test_species(),
        showcase_players_by_id = showcase,
        seed = 11,
        duration = 30,
    })
end

---@type MatchInput
local MOVE_RIGHT = {
    move = Vec2.new(1, 0),
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

t.describe("sim.species", function()
    t.it("leaves stats unchanged for the production neutral species", function()
        local authored = { pace = 4, strength = 5, technique = 6, stamina = 7, mental = 8 }
        local effective = species.apply(authored, species_pool.neutral)

        t.eq(effective.pace, authored.pace)
        t.eq(effective.strength, authored.strength)
        t.eq(effective.technique, authored.technique)
        t.eq(effective.stamina, authored.stamina)
        t.eq(effective.mental, authored.mental)
        t.is_true(effective ~= authored, "application does not mutate or alias authored stats")
    end)

    t.it("applies additive modifiers deterministically and clamps every stat to 0..10", function()
        ---@type SpeciesData
        local extreme = {
            id = "extreme_fixture",
            name = "Extreme Fixture",
            modifiers = { pace = 4, strength = -4, technique = 2, stamina = -2, mental = 0 },
            verb = "none",
            skill = nil,
        }
        local authored = { pace = 8, strength = 2, technique = 5, stamina = 1, mental = 6 }
        local first = species.apply(authored, extreme)
        local second = species.apply(authored, extreme)

        t.eq(first.pace, 10)
        t.eq(first.strength, 0)
        t.eq(first.technique, 7)
        t.eq(first.stamina, 0)
        t.eq(first.mental, 6)
        t.eq(second.pace, first.pace)
        t.eq(second.strength, first.strength)
        t.eq(second.technique, first.technique)
        t.eq(second.stamina, first.stamina)
        t.eq(second.mental, first.mental)
    end)

    t.it("applies the modifier exactly once for controlled and match-AI slots", function()
        local neutral_by_id = players_by_id()
        local neutral_match = new_match(neutral_by_id, showcase_by_id())
        local controlled_id = neutral_match.players[neutral_match.controlled].id
        local swift_by_id = players_by_id()
        local swift_showcase = showcase_by_id({
            [controlled_id] = SWIFT.id,
            tox_vren = SWIFT.id,
        })
        local swift_match = new_match(swift_by_id, swift_showcase)
        local neutral_home = player_named(neutral_match.players, controlled_id)
        local swift_home = player_named(swift_match.players, controlled_id)
        local neutral_away = player_named(neutral_match.players, "tox_vren")
        local swift_away = player_named(swift_match.players, "tox_vren")

        t.eq(swift_match.players[swift_match.controlled].id, controlled_id)
        t.eq(
            swift_home.move_speed,
            stats.move_speed(species.apply(swift_by_id[controlled_id].stats, SWIFT))
        )
        t.eq(
            swift_away.move_speed,
            stats.move_speed(species.apply(swift_by_id.tox_vren.stats, SWIFT))
        )
        t.eq(swift_home.move_speed - neutral_home.move_speed, 20, "controlled slot gets one point")
        t.eq(swift_away.move_speed - neutral_away.move_speed, 20, "AI slot gets one point")
        t.eq(swift_home.species_id, SWIFT.id)
        t.eq(swift_home.owned_verb, "burst")
    end)

    t.it("makes a pace modifier visible as distance covered in the same match", function()
        local neutral_match = new_match(players_by_id(), showcase_by_id())
        local controlled_id = neutral_match.players[neutral_match.controlled].id
        local swift_match =
            new_match(players_by_id(), showcase_by_id({ [controlled_id] = SWIFT.id }))
        local neutral_player = player_named(neutral_match.players, controlled_id)
        local swift_player = player_named(swift_match.players, controlled_id)
        local neutral_start = neutral_player.pos.x
        local swift_start = swift_player.pos.x

        for _ = 1, 60 do
            match.step(neutral_match, 1 / 60, MOVE_RIGHT)
            match.step(swift_match, 1 / 60, MOVE_RIGHT)
        end

        local neutral_distance = neutral_player.pos.x - neutral_start
        local swift_distance = swift_player.pos.x - swift_start
        t.is_true(swift_distance > neutral_distance, "the faster player covers more ground")
    end)

    t.it("keeps every owned-verb hook neutral until signature skills bind it", function()
        t.eq(species.jump_reach("jump"), 0)
        t.eq(species.collision_reach("collision"), 0)
        t.eq(species.burst_speed("burst"), 1)
        t.eq(species.dribble_protection("dribble"), 0)
        t.eq(species.block_reach("block"), 0)
        t.eq(species.link_pass_speed("link"), 1)

        t.eq(species.jump_reach("none"), 0)
        t.eq(species.collision_reach("none"), 0)
        t.eq(species.burst_speed("none"), 1)
        t.eq(species.dribble_protection("none"), 0)
        t.eq(species.block_reach("none"), 0)
        t.eq(species.link_pass_speed("none"), 1)
    end)
end)
