local match = require("sim.match")
local players = require("data.players")
local teams = require("data.teams")
local t = require("spec.support.runner")

---@return table<string, PlayerData>
local function players_by_id()
    local by_id = {}
    for _, source in ipairs(players) do
        by_id[source.id] = {
            id = source.id,
            name = source.name,
            number = source.number,
            position = source.position,
            stats = source.stats,
            presentation_id = source.presentation_id,
            cosmetic_variant_id = source.cosmetic_variant_id,
            loadout_id = source.loadout_id,
        }
    end
    return by_id
end

---@param by_id table<string, PlayerData>
---@return MatchState
local function new_match(by_id)
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        players_by_id = by_id,
        seed = 71,
    })
end

---@param state MatchState
---@param id string
---@return MatchPlayer
local function match_player(state, id)
    for _, player in ipairs(state.players) do
        if player.id == id then
            return player
        end
    end
    return assert(nil, "missing match player " .. id)
end

t.describe("prototype content match construction", function()
    t.it("keeps presentation, cosmetic, and equipment swaps mechanically inert", function()
        local baseline_players = players_by_id()
        local swapped_players = players_by_id()
        local swapped = swapped_players.brakka
        swapped.presentation_id = "scifi_nova_quell"
        swapped.cosmetic_variant_id = "nova_cyan"
        swapped.loadout_id = "loadout_foam_champion"

        local baseline = match_player(new_match(baseline_players), "brakka")
        local changed = match_player(new_match(swapped_players), "brakka")
        for _, field in ipairs({
            "move_speed",
            "shot_speed",
            "dribble",
            "strength",
            "first_touch",
            "header_skill",
            "volley_skill",
            "bicycle_skill",
            "reach",
            "handling",
        }) do
            t.eq(changed[field], baseline[field], field .. " changed with presentation data")
        end
        t.eq(rawget(changed, "presentation_id"), nil)
        t.eq(rawget(changed, "loadout_id"), nil)
    end)

    t.it("preserves the Galactic showcase species seam for the existing fixture", function()
        local state = new_match(players_by_id())
        t.eq(#state.players, 10)
        for _, player in ipairs(state.players) do
            t.eq(player.species_id, "neutral")
            t.eq(player.owned_verb, "none")
        end
    end)
end)
