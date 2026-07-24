-- Pure validation for authored player, presentation, equipment, and fixed-loadout
-- content. Invalid authored data is a programmer error, so this module asserts.

local MAX_ACTION_TICKS = 600
local MAX_INTERRUPTION_TICKS = 30
local MAX_REACH_PX = 240
local MAX_PROJECTILE_SPEED = 2000
local MAX_DISPLACEMENT_PX = 60

local FAMILY_IDS = {
    unarmed = true,
    guard = true,
    light_melee = true,
    ranged = true,
}

local THEME_IDS = {
    medieval_fantasy = true,
    galactic_scifi = true,
    toybox = true,
}

local POSITION_IDS = {
    keeper = true,
    defender = true,
    midfielder = true,
    forward = true,
}

local STAT_FIELDS = {
    pace = true,
    strength = true,
    technique = true,
    stamina = true,
    mental = true,
}

local CHARACTER_FIELDS = {
    id = true,
    name = true,
    theme_id = true,
    rig_id = true,
}

local COSMETIC_FIELDS = {
    id = true,
    presentation_id = true,
    material_variant_id = true,
    head_variant_id = true,
    accessory_id = true,
}

local OUTCOME_FIELDS = {
    interruption_ticks = true,
    displacement_px = true,
    ball_spill = true,
}

local FAMILY_FIELDS = {
    id = true,
    name = true,
    activation = true,
    contact_kind = true,
    windup_ticks = true,
    active_ticks = true,
    held_active = true,
    recovery_ticks = true,
    cooldown_ticks = true,
    reach_px = true,
    projectile_speed_px_per_second = true,
    projectile_lifetime_ticks = true,
    front_arc_degrees = true,
    movement_multiplier = true,
    unguarded_outcome = true,
    guarded_recoil_px = true,
}

local EQUIPMENT_FIELDS = {
    id = true,
    name = true,
    theme_id = true,
    family_id = true,
    attachment = true,
}

local LOADOUT_FIELDS = {
    id = true,
    family_id = true,
    equipment_presentation_id = true,
}

local PLAYER_FIELDS = {
    id = true,
    name = true,
    number = true,
    position = true,
    stats = true,
    presentation_id = true,
    cosmetic_variant_id = true,
    loadout_id = true,
}

local TEAM_FIELDS = {
    id = true,
    name = true,
    color = true,
    formation = true,
    roster = true,
    squad = true,
}

---@class PrototypeContentCatalog
---@field character_presentations table<string, CharacterPresentationData>
---@field cosmetic_variants table<string, CosmeticVariantData>
---@field action_families table<ActionFamilyId, ActionFamilyData>
---@field equipment_presentations table<string, EquipmentPresentationData>
---@field loadouts table<string, FixedLoadoutData>
---@field players PlayerData[]

---@class PrototypeFixturePolicy
---@field allow_repeated_families boolean?

---@class ContentValidation
local content_validation = {}

---@param value any
---@return boolean
local function is_finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

---@param value any
---@return boolean
local function is_integer(value)
    return is_finite(value) and value == math.floor(value)
end

---@param value any
---@param label string
local function assert_nonempty_string(value, label)
    assert(type(value) == "string" and value ~= "", label .. " must be a non-empty string")
end

---@param value any
---@param allowed table<string, boolean>
---@param label string
local function assert_fields(value, allowed, label)
    assert(type(value) == "table", label .. " must be a table")
    for field in pairs(value) do
        assert(
            type(field) == "string" and allowed[field],
            label .. " has unknown field " .. tostring(field)
        )
    end
end

---@param value any
---@param label string
local function assert_dense_array(value, label)
    assert(type(value) == "table", label .. " must be an array")
    local count = #value
    for key in pairs(value) do
        assert(
            type(key) == "number" and is_integer(key) and key >= 1 and key <= count,
            label .. " must be a dense array"
        )
    end
end

---@param value any
---@param label string
---@param maximum integer
local function assert_bounded_ticks(value, label, maximum)
    assert(
        is_integer(value) and value >= 0 and value <= maximum,
        label .. " must be bounded non-negative ticks"
    )
end

---@param registry table
---@param label string
---@param allowed table<string, boolean>
---@return integer count
local function validate_registry_shape(registry, label, allowed)
    assert(type(registry) == "table", label .. " must be a table")
    local count = 0
    for key, record in pairs(registry) do
        assert_nonempty_string(key, label .. " key")
        assert_fields(record, allowed, label .. "." .. key)
        assert(record.id == key, label .. "." .. key .. " id must match its key")
        count = count + 1
    end
    return count
end

---@param outcome CombatOutcomeData
---@param label string
local function validate_outcome(outcome, label)
    assert_fields(outcome, OUTCOME_FIELDS, label)
    assert_bounded_ticks(
        outcome.interruption_ticks,
        label .. ".interruption_ticks",
        MAX_INTERRUPTION_TICKS
    )
    assert(
        is_finite(outcome.displacement_px)
            and outcome.displacement_px >= 0
            and outcome.displacement_px <= MAX_DISPLACEMENT_PX,
        label .. ".displacement_px is outside the prototype bounds"
    )
    assert(type(outcome.ball_spill) == "boolean", label .. ".ball_spill must be boolean")
end

---@param family ActionFamilyData
---@param label string
local function validate_family(family, label)
    assert(FAMILY_IDS[family.id], label .. " has unknown family id")
    assert_nonempty_string(family.name, label .. ".name")
    assert_bounded_ticks(family.windup_ticks, label .. ".windup_ticks", MAX_ACTION_TICKS)
    assert_bounded_ticks(family.recovery_ticks, label .. ".recovery_ticks", MAX_ACTION_TICKS)
    assert_bounded_ticks(family.cooldown_ticks, label .. ".cooldown_ticks", MAX_ACTION_TICKS)
    assert(
        is_finite(family.front_arc_degrees)
            and family.front_arc_degrees > 0
            and family.front_arc_degrees <= 180,
        label .. ".front_arc_degrees must be in (0, 180]"
    )
    assert(
        is_finite(family.movement_multiplier)
            and family.movement_multiplier > 0
            and family.movement_multiplier <= 1,
        label .. ".movement_multiplier must be in (0, 1]"
    )
    assert(type(family.held_active) == "boolean", label .. ".held_active must be boolean")
    assert(
        is_finite(family.guarded_recoil_px)
            and family.guarded_recoil_px >= 0
            and family.guarded_recoil_px <= 6,
        label .. ".guarded_recoil_px must be in [0, 6]"
    )

    if family.id == "guard" then
        assert(family.activation == "held", label .. " must use held activation")
        assert(family.contact_kind == "guard", label .. " must use guard contact")
        assert(family.held_active, label .. " must remain active while held")
        assert(family.active_ticks == nil, label .. " cannot have timed active ticks")
        assert(family.cooldown_ticks == 0, label .. " has no cooldown")
        assert(family.reach_px == nil, label .. " guards self rather than using reach")
        assert(family.unguarded_outcome == nil, label .. " cannot author an attack outcome")
        assert(
            family.projectile_speed_px_per_second == nil and family.projectile_lifetime_ticks == nil,
            label .. " cannot author projectile fields"
        )
    else
        assert(not family.held_active, label .. " cannot remain active while held")
        assert_bounded_ticks(
            assert(family.active_ticks),
            label .. ".active_ticks",
            MAX_ACTION_TICKS
        )
        assert(family.active_ticks > 0, label .. ".active_ticks must be positive")
        validate_outcome(assert(family.unguarded_outcome), label .. ".unguarded_outcome")
        assert(family.unguarded_outcome.ball_spill, label .. " must spill an owned ball")

        if family.id == "ranged" then
            assert(family.activation == "held_release", label .. " must fire on release")
            assert(family.contact_kind == "projectile", label .. " must use projectile contact")
            assert(
                family.reach_px == nil,
                label .. " uses projectile travel instead of melee reach"
            )
            assert(
                is_finite(family.projectile_speed_px_per_second)
                    and family.projectile_speed_px_per_second > 0
                    and family.projectile_speed_px_per_second <= MAX_PROJECTILE_SPEED,
                label .. ".projectile_speed_px_per_second is outside the prototype bounds"
            )
            assert_bounded_ticks(
                family.projectile_lifetime_ticks,
                label .. ".projectile_lifetime_ticks",
                MAX_ACTION_TICKS
            )
            assert(
                family.projectile_lifetime_ticks > 0,
                label .. ".projectile_lifetime_ticks must be positive"
            )
        else
            assert(family.activation == "press", label .. " must commit on press")
            assert(family.contact_kind == "melee", label .. " must use melee contact")
            assert(
                is_finite(family.reach_px)
                    and family.reach_px > 0
                    and family.reach_px <= MAX_REACH_PX,
                label .. ".reach_px is outside the prototype bounds"
            )
            assert(
                family.projectile_speed_px_per_second == nil
                    and family.projectile_lifetime_ticks == nil,
                label .. " cannot author projectile fields"
            )
        end
    end
end

---@param catalog PrototypeContentCatalog
---@return table<string, PlayerData>
local function players_by_id(catalog)
    local by_id = {}
    assert_dense_array(catalog.players, "players")
    for index, player in ipairs(catalog.players) do
        local label = "players." .. index
        assert_fields(player, PLAYER_FIELDS, label)
        assert_nonempty_string(player.id, label .. ".id")
        assert(not by_id[player.id], "duplicate player id: " .. player.id)
        by_id[player.id] = player
    end
    return by_id
end

---@param player PlayerData
---@param catalog PrototypeContentCatalog
---@param label string
local function validate_player(player, catalog, label)
    assert_nonempty_string(player.name, label .. ".name")
    assert(
        is_integer(player.number) and player.number >= 1 and player.number <= 99,
        label .. ".number must be an integer in [1, 99]"
    )
    assert(POSITION_IDS[player.position], label .. " has unknown position")
    assert_fields(player.stats, STAT_FIELDS, label .. ".stats")
    local stat_count = 0
    for stat, value in pairs(player.stats) do
        stat_count = stat_count + 1
        assert(
            is_integer(value) and value >= 0 and value <= 10,
            label .. ".stats." .. stat .. " must be an integer in [0, 10]"
        )
    end
    assert(stat_count == 5, label .. " must author exactly five stats")

    assert(
        catalog.character_presentations[player.presentation_id],
        label .. " has unknown presentation id"
    )
    if player.cosmetic_variant_id then
        local cosmetic = assert(
            catalog.cosmetic_variants[player.cosmetic_variant_id],
            label .. " has unknown cosmetic variant id"
        )
        assert(
            cosmetic.presentation_id == player.presentation_id,
            label .. " cosmetic variant belongs to another presentation"
        )
    end
    if player.position == "keeper" then
        assert(player.loadout_id == nil, label .. " keeper cannot have a combat loadout")
    else
        assert_nonempty_string(player.loadout_id, label .. ".loadout_id")
        assert(catalog.loadouts[player.loadout_id], label .. " has unknown loadout id")
    end
end

---@param catalog PrototypeContentCatalog
---@return boolean valid
function content_validation.validate_catalog(catalog)
    assert(type(catalog) == "table", "content catalog is required")

    local character_count = validate_registry_shape(
        catalog.character_presentations,
        "character_presentations",
        CHARACTER_FIELDS
    )
    assert(character_count == 6, "prototype needs exactly six character presentations")
    for key, presentation in pairs(catalog.character_presentations) do
        local label = "character_presentations." .. key
        assert_nonempty_string(presentation.name, label .. ".name")
        assert(THEME_IDS[presentation.theme_id], label .. " has unknown theme id")
        assert(presentation.rig_id == "rig_medium", label .. " must use rig_medium")
    end

    local cosmetic_count =
        validate_registry_shape(catalog.cosmetic_variants, "cosmetic_variants", COSMETIC_FIELDS)
    assert(cosmetic_count >= 6, "prototype needs reusable cosmetic variants")
    for key, cosmetic in pairs(catalog.cosmetic_variants) do
        local label = "cosmetic_variants." .. key
        assert(
            catalog.character_presentations[cosmetic.presentation_id],
            label .. " has unknown presentation id"
        )
        assert_nonempty_string(cosmetic.material_variant_id, label .. ".material_variant_id")
        if cosmetic.head_variant_id then
            assert_nonempty_string(cosmetic.head_variant_id, label .. ".head_variant_id")
        end
        if cosmetic.accessory_id then
            assert_nonempty_string(cosmetic.accessory_id, label .. ".accessory_id")
        end
    end

    local family_count =
        validate_registry_shape(catalog.action_families, "action_families", FAMILY_FIELDS)
    assert(family_count == 4, "prototype needs exactly four action families")
    for id in pairs(FAMILY_IDS) do
        validate_family(
            assert(catalog.action_families[id], "missing action family: " .. id),
            "action_families." .. id
        )
    end

    local equipment_count = validate_registry_shape(
        catalog.equipment_presentations,
        "equipment_presentations",
        EQUIPMENT_FIELDS
    )
    assert(equipment_count == 6, "prototype needs exactly six equipment presentations")
    for key, equipment in pairs(catalog.equipment_presentations) do
        local label = "equipment_presentations." .. key
        assert_nonempty_string(equipment.name, label .. ".name")
        assert(THEME_IDS[equipment.theme_id], label .. " has unknown theme id")
        assert(catalog.action_families[equipment.family_id], label .. " has unknown family id")
        assert(
            equipment.attachment == "left_hand"
                or equipment.attachment == "right_hand"
                or equipment.attachment == "both_hands",
            label .. " has unknown attachment"
        )
    end

    local loadout_count = validate_registry_shape(catalog.loadouts, "loadouts", LOADOUT_FIELDS)
    assert(loadout_count == 6, "prototype needs exactly six fixed loadouts")
    for key, loadout in pairs(catalog.loadouts) do
        local label = "loadouts." .. key
        assert(catalog.action_families[loadout.family_id], label .. " has unknown family id")
        local equipment = assert(
            catalog.equipment_presentations[loadout.equipment_presentation_id],
            label .. " has unknown equipment presentation id"
        )
        assert(
            equipment.family_id == loadout.family_id,
            label .. " family does not match its equipment presentation"
        )
    end

    local light_melee = catalog.action_families.light_melee
    for _, id in ipairs({
        "medieval_tournament_sword",
        "scifi_energy_blade",
        "toy_foam_sword",
    }) do
        local equipment =
            assert(catalog.equipment_presentations[id], "missing light-melee presentation: " .. id)
        assert(
            catalog.action_families[equipment.family_id] == light_melee,
            id .. " must resolve to the shared light_melee record"
        )
    end

    local by_id = players_by_id(catalog)
    for id, player in pairs(by_id) do
        validate_player(player, catalog, "players." .. id)
    end
    return true
end

---@param team TeamData
---@param players table<string, PlayerData>
---@param catalog PrototypeContentCatalog
---@param fixture_players table<string, boolean>
---@param allow_repeated_families boolean
local function validate_team(team, players, catalog, fixture_players, allow_repeated_families)
    local label = "team." .. tostring(team.id)
    assert_fields(team, TEAM_FIELDS, label)
    assert_nonempty_string(team.id, label .. ".id")
    assert_nonempty_string(team.name, label .. ".name")
    assert_nonempty_string(team.formation, label .. ".formation")
    assert_dense_array(team.roster, label .. ".roster")
    assert(#team.roster == 5, label .. " roster must contain exactly five players")

    local team_players = {}
    local numbers = {}
    local keeper_count = 0
    local family_counts = {}
    for _, player_id in ipairs(team.roster) do
        assert_nonempty_string(player_id, label .. " roster id")
        assert(
            not team_players[player_id],
            label .. " roster contains duplicate player " .. player_id
        )
        assert(
            not fixture_players[player_id],
            "fixture contains player on both teams: " .. player_id
        )
        team_players[player_id] = true
        fixture_players[player_id] = true

        local player = assert(players[player_id], label .. " has unknown player " .. player_id)
        assert(
            not numbers[player.number],
            label .. " duplicates shirt number " .. tostring(player.number)
        )
        numbers[player.number] = true
        if player.position == "keeper" then
            keeper_count = keeper_count + 1
        else
            local loadout = assert(catalog.loadouts[player.loadout_id])
            family_counts[loadout.family_id] = (family_counts[loadout.family_id] or 0) + 1
        end
    end
    assert(keeper_count == 1, label .. " roster must contain exactly one keeper")
    if not allow_repeated_families then
        for family_id in pairs(FAMILY_IDS) do
            assert(
                family_counts[family_id] == 1,
                label .. " must contain exactly one " .. family_id .. " outfielder"
            )
        end
    end

    if team.squad then
        assert_dense_array(team.squad, label .. ".squad")
        local squad_players = {}
        local squad_numbers = {}
        for _, player_id in ipairs(team.squad) do
            local squad_player = assert(
                players[player_id],
                label .. " squad has unknown player " .. tostring(player_id)
            )
            assert(not squad_players[player_id], label .. " squad contains duplicate player")
            assert(
                not squad_numbers[squad_player.number],
                label .. " squad duplicates shirt number " .. tostring(squad_player.number)
            )
            squad_players[player_id] = true
            squad_numbers[squad_player.number] = true
        end
        for player_id in pairs(team_players) do
            assert(squad_players[player_id], label .. " starter is missing from the squad")
        end
    end
end

---@param catalog PrototypeContentCatalog
---@param home TeamData
---@param away TeamData
---@param policy PrototypeFixturePolicy?
---@return boolean valid
function content_validation.validate_fixture(catalog, home, away, policy)
    content_validation.validate_catalog(catalog)
    assert(home ~= away, "fixture teams must be distinct records")
    local players = players_by_id(catalog)
    local fixture_players = {}
    local allow_repeated_families = policy and policy.allow_repeated_families == true or false
    validate_team(home, players, catalog, fixture_players, allow_repeated_families)
    validate_team(away, players, catalog, fixture_players, allow_repeated_families)

    local fixture_count = 0
    local presentation_ids = {}
    for player_id in pairs(fixture_players) do
        fixture_count = fixture_count + 1
        presentation_ids[players[player_id].presentation_id] = true
    end
    assert(fixture_count == 10, "prototype fixture must contain ten distinct players")
    local presentation_count = 0
    for _ in pairs(presentation_ids) do
        presentation_count = presentation_count + 1
    end
    assert(presentation_count <= 6, "prototype fixture exceeds six character presentations")
    return true
end

return content_validation
