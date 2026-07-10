-- Frozen, position-aware squad strength estimate. This is deliberately a small
-- content-independent ordering function, not a prediction formula for match results.

---@class RatingWeights
---@field pace number
---@field strength number
---@field technique number
---@field stamina number
---@field mental number

-- Frozen before table_signal/upset_rate per season_metrics red-team #11. Do not tune
-- these weights against validation output or change them alongside content/metric bands;
-- any future edit resets the downstream baselines.
---@type table<Position, RatingWeights>
local WEIGHTS = {
    keeper = { pace = 0.20, strength = 0.10, technique = 0.25, stamina = 0.10, mental = 0.35 },
    defender = {
        pace = 0.15,
        strength = 0.30,
        technique = 0.15,
        stamina = 0.20,
        mental = 0.20,
    },
    midfielder = {
        pace = 0.20,
        strength = 0.15,
        technique = 0.30,
        stamina = 0.20,
        mental = 0.15,
    },
    forward = {
        pace = 0.30,
        strength = 0.25,
        technique = 0.30,
        stamina = 0.10,
        mental = 0.05,
    },
}

---@class Rating
local rating = {}

-- Each starter contributes a 0..10 weighted score chosen by their authored
-- position. A legal five-player roster therefore rates from 0..50.
---@param roster string[]
---@param players_by_id table<string, PlayerData>
---@return number squad_rating
function rating.squad(roster, players_by_id)
    assert(#roster == 5, "squad rating needs exactly five starters")

    local total = 0
    local keeper_count = 0
    local seen = {}
    for _, id in ipairs(roster) do
        assert(not seen[id], "squad rating cannot count a starter twice: " .. tostring(id))
        seen[id] = true

        local player = assert(players_by_id[id], "unknown player in squad rating: " .. tostring(id))
        local weights = assert(
            WEIGHTS[player.position],
            "unknown player position: " .. tostring(player.position)
        )
        local stats = player.stats
        total = total
            + stats.pace * weights.pace
            + stats.strength * weights.strength
            + stats.technique * weights.technique
            + stats.stamina * weights.stamina
            + stats.mental * weights.mental
        if player.position == "keeper" then
            keeper_count = keeper_count + 1
        end
    end

    assert(keeper_count == 1, "squad rating needs exactly one keeper")
    return total
end

return rating
