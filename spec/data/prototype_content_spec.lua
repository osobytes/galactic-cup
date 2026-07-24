local action_families = require("data.action_families")
local character_presentations = require("data.character_presentations")
local cosmetic_variants = require("data.cosmetic_variants")
local equipment_presentations = require("data.equipment_presentations")
local loadouts = require("data.loadouts")
local players = require("data.players")
local teams = require("data.teams")
local t = require("spec.support.runner")

---@param values table
---@return integer
local function count(values)
    local total = 0
    for _ in pairs(values) do
        total = total + 1
    end
    return total
end

---@return table<string, PlayerData>
local function players_by_id()
    local result = {}
    for _, player in ipairs(players) do
        result[player.id] = player
    end
    return result
end

t.describe("GOLISEO prototype content", function()
    t.it("authors the accepted six-character, six-item, four-family budget", function()
        t.eq(count(character_presentations), 6)
        t.eq(count(equipment_presentations), 6)
        t.eq(count(action_families), 4)
        t.eq(count(loadouts), 6)
        t.is_true(count(cosmetic_variants) >= 6)
    end)

    t.it("pins the accepted initial family records", function()
        local unarmed = action_families.unarmed
        t.eq(unarmed.windup_ticks, 6)
        t.eq(unarmed.active_ticks, 4)
        t.eq(unarmed.recovery_ticks, 12)
        t.eq(unarmed.cooldown_ticks, 24)
        t.eq(unarmed.reach_px, 30)
        t.eq(unarmed.front_arc_degrees, 100)
        t.eq(unarmed.movement_multiplier, 0.8)

        local guard = action_families.guard
        t.eq(guard.windup_ticks, 6)
        t.eq(guard.active_ticks, nil)
        t.eq(guard.recovery_ticks, 9)
        t.eq(guard.cooldown_ticks, 0)
        t.eq(guard.front_arc_degrees, 120)
        t.eq(guard.movement_multiplier, 0.55)

        local melee = action_families.light_melee
        t.eq(melee.windup_ticks, 12)
        t.eq(melee.active_ticks, 5)
        t.eq(melee.recovery_ticks, 21)
        t.eq(melee.cooldown_ticks, 42)
        t.eq(melee.reach_px, 42)
        t.eq(melee.front_arc_degrees, 75)
        t.eq(melee.movement_multiplier, 0.5)

        local ranged = action_families.ranged
        t.eq(ranged.windup_ticks, 18)
        t.eq(ranged.active_ticks, 1)
        t.eq(ranged.recovery_ticks, 27)
        t.eq(ranged.cooldown_ticks, 60)
        t.eq(ranged.projectile_speed_px_per_second, 300)
        t.eq(ranged.projectile_lifetime_ticks, 60)
        t.eq(ranged.front_arc_degrees, 20)
        t.eq(ranged.movement_multiplier, 0.4)
    end)

    t.it("resolves all three themed swords to one mechanical table by identity", function()
        local tournament =
            action_families[equipment_presentations.medieval_tournament_sword.family_id]
        local vector = action_families[equipment_presentations.scifi_energy_blade.family_id]
        local foam = action_families[equipment_presentations.toy_foam_sword.family_id]
        t.is_true(tournament == action_families.light_melee)
        t.is_true(vector == tournament)
        t.is_true(foam == tournament)
    end)

    t.it("uses ten stable starters and no more than six reusable presentations", function()
        local by_id = players_by_id()
        local seen_players = {}
        local seen_presentations = {}
        for _, team in ipairs({ teams.nebula, teams.orion }) do
            for _, player_id in ipairs(team.roster) do
                t.is_true(not seen_players[player_id], "fixture repeats " .. player_id)
                seen_players[player_id] = true
                local player = assert(by_id[player_id])
                seen_presentations[player.presentation_id] = true
            end
        end
        t.eq(count(seen_players), 10)
        t.eq(count(seen_presentations), 6)
    end)
end)
