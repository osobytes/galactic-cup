local content_validation = require("sim.content_validation")
local teams = require("data.teams")
local t = require("spec.support.runner")

---@param value any
---@return any
local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[deep_copy(key)] = deep_copy(child)
    end
    return result
end

---@return PrototypeContentCatalog
local function catalog()
    return {
        character_presentations = deep_copy(require("data.character_presentations")),
        cosmetic_variants = deep_copy(require("data.cosmetic_variants")),
        action_families = deep_copy(require("data.action_families")),
        equipment_presentations = deep_copy(require("data.equipment_presentations")),
        loadouts = deep_copy(require("data.loadouts")),
        players = deep_copy(require("data.players")),
    }
end

---@param values PlayerData[]
---@param id string
---@return PlayerData
local function player(values, id)
    for _, value in ipairs(values) do
        if value.id == id then
            return value
        end
    end
    return assert(nil, "missing player " .. id)
end

---@param fixture PrototypeContentCatalog
---@param home TeamData?
---@param away TeamData?
---@param policy PrototypeFixturePolicy?
---@return boolean
local function fixture_is_valid(fixture, home, away, policy)
    return pcall(
        content_validation.validate_fixture,
        fixture,
        home or deep_copy(teams.nebula),
        away or deep_copy(teams.orion),
        policy
    )
end

t.describe("prototype content validation", function()
    t.it("accepts the authored catalog and one-of-each default fixture", function()
        local fixture = catalog()
        t.is_true(content_validation.validate_catalog(fixture))
        t.is_true(fixture_is_valid(fixture))
    end)

    t.it("rejects unknown ids and family/presentation mismatches", function()
        local unknown_presentation = catalog()
        player(unknown_presentation.players, "zyro_vex").presentation_id = "missing"
        t.is_true(not pcall(content_validation.validate_catalog, unknown_presentation))

        local unknown_loadout = catalog()
        player(unknown_loadout.players, "zyro_vex").loadout_id = "missing"
        t.is_true(not pcall(content_validation.validate_catalog, unknown_loadout))

        local mismatch = catalog()
        mismatch.loadouts.loadout_vector_blade.family_id = "ranged"
        t.is_true(not pcall(content_validation.validate_catalog, mismatch))
    end)

    t.it("rejects duplicate player ids and prohibited team numbers", function()
        local duplicate_id = catalog()
        duplicate_id.players[2].id = duplicate_id.players[1].id
        t.is_true(not pcall(content_validation.validate_catalog, duplicate_id))

        local duplicate_number = catalog()
        player(duplicate_number.players, "brakka").number =
            player(duplicate_number.players, "veil_nyx").number
        t.is_true(not fixture_is_valid(duplicate_number))
    end)

    t.it("rejects illegal keeper and outfielder loadouts", function()
        local armed_keeper = catalog()
        player(armed_keeper.players, "ozzo").loadout_id = "loadout_spring_gloves"
        t.is_true(not pcall(content_validation.validate_catalog, armed_keeper))

        local empty_outfielder = catalog()
        player(empty_outfielder.players, "zyro_vex").loadout_id = nil
        t.is_true(not pcall(content_validation.validate_catalog, empty_outfielder))
    end)

    t.it("rejects wrong team size, unknown roster ids, and repeated default families", function()
        local short_home = deep_copy(teams.nebula)
        short_home.roster[5] = nil
        t.is_true(not fixture_is_valid(catalog(), short_home))

        local unknown_home = deep_copy(teams.nebula)
        unknown_home.roster[5] = "missing"
        t.is_true(not fixture_is_valid(catalog(), unknown_home))

        local repeated = catalog()
        player(repeated.players, "veil_nyx").loadout_id = "loadout_emberguard_shield"
        t.is_true(not fixture_is_valid(repeated))
        t.is_true(fixture_is_valid(repeated, nil, nil, { allow_repeated_families = true }))
    end)

    t.it("rejects out-of-bounds family data and presentation-owned mechanics", function()
        local long_interrupt = catalog()
        long_interrupt.action_families.light_melee.unguarded_outcome.interruption_ticks = 31
        t.is_true(not pcall(content_validation.validate_catalog, long_interrupt))

        local invalid_arc = catalog()
        invalid_arc.action_families.ranged.front_arc_degrees = 181
        t.is_true(not pcall(content_validation.validate_catalog, invalid_arc))

        local hidden_stat = catalog()
        rawset(hidden_stat.character_presentations.scifi_axi, "pace", 1)
        t.is_true(not pcall(content_validation.validate_catalog, hidden_stat))
    end)
end)
