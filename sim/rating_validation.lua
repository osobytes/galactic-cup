-- Deterministic validation harness for the frozen squad rating. Every unordered
-- squad pair plays both home orientations on common seeds. The home side gets
-- the human-proxy bot in each leg, so each squad receives the same side/proxy
-- treatment. Results remain relative to that proxy, never predictions of humans.

local headless = require("sim.headless")
local rating = require("sim.rating")
local players = require("data.players")

---@class RatedSquad
---@field team TeamData
---@field rating number

---@class RatingPairResult
---@field higher RatedSquad
---@field lower RatedSquad
---@field gap number
---@field games integer
---@field wins integer
---@field draws integer
---@field losses integer
---@field win_rate number?  -- decisive games only; draws reported separately
---@field score_share number  -- win=1, draw=0.5, loss=0

---@class RatingValidationResult
---@field seeds_per_leg integer
---@field squads RatedSquad[]
---@field pairs RatingPairResult[]
---@field wins integer
---@field draws integer
---@field losses integer
---@field win_rate number?
---@field score_share number
---@field above_half_pairs integer
---@field slope number  -- OLS score-share change per rating point

---@class RatingValidation
local validation = {}

-- All fixtures use existing player ids/stat blocks and the same role-aligned
-- 1-1-2 shape. Only lineup strength varies.
---@type TeamData[]
local SQUADS = {
    {
        id = "rating_prospects",
        name = "Prospects",
        color = { 0.4, 0.4, 0.4 },
        formation = "1-1-2",
        roster = { "gax_oru", "veil_nyx", "morv", "krag", "tox_vren" },
    },
    {
        id = "rating_developing",
        name = "Developing",
        color = { 0.4, 0.6, 0.7 },
        formation = "1-1-2",
        roster = { "gax_oru", "brakka", "tib_quell", "krag", "tox_vren" },
    },
    {
        id = "rating_balanced",
        name = "Balanced",
        color = { 0.5, 0.7, 0.5 },
        formation = "1-1-2",
        roster = { "ozzo", "veil_nyx", "sela_dwin", "mika_olu", "tox_vren" },
    },
    {
        id = "rating_contenders",
        name = "Contenders",
        color = { 0.8, 0.7, 0.3 },
        formation = "1-1-2",
        roster = { "ozzo", "brakka", "rok_tann", "zyro_vex", "tox_vren" },
    },
    {
        id = "rating_elite",
        name = "Elite",
        color = { 0.9, 0.4, 0.3 },
        formation = "1-1-2",
        roster = { "ozzo", "drell", "rok_tann", "zyro_vex", "mika_olu" },
    },
}

---@return table<string, PlayerData>
local function players_by_id()
    local by_id = {}
    for _, player in ipairs(players) do
        by_id[player.id] = player
    end
    return by_id
end

---@param result MatchResult
---@param higher_side "home"|"away"
---@param row RatingPairResult
local function record_outcome(result, higher_side, row)
    if result.winner == nil then
        row.draws = row.draws + 1
    elseif result.winner == higher_side then
        row.wins = row.wins + 1
    else
        row.losses = row.losses + 1
    end
end

---@param pairs RatingPairResult[]
---@return number slope
local function score_share_slope(pairs)
    local mean_gap, mean_share = 0, 0
    for _, pair in ipairs(pairs) do
        mean_gap = mean_gap + pair.gap
        mean_share = mean_share + pair.score_share
    end
    mean_gap = mean_gap / #pairs
    mean_share = mean_share / #pairs

    local covariance, variance = 0, 0
    for _, pair in ipairs(pairs) do
        local centered_gap = pair.gap - mean_gap
        covariance = covariance + centered_gap * (pair.score_share - mean_share)
        variance = variance + centered_gap * centered_gap
    end
    return variance > 0 and covariance / variance or 0
end

---@param seeds_per_leg integer
---@return RatingValidationResult
function validation.run(seeds_per_leg)
    assert(
        seeds_per_leg >= 1 and seeds_per_leg == math.floor(seeds_per_leg),
        "seed count must be a positive integer"
    )

    local by_id = players_by_id()
    local squads = {}
    for _, team in ipairs(SQUADS) do
        squads[#squads + 1] = { team = team, rating = rating.squad(team.roster, by_id) }
    end
    table.sort(squads, function(a, b)
        return a.rating < b.rating
    end)

    local pairs = {}
    local all_wins, all_draws, all_losses = 0, 0, 0
    for lower_index = 1, #squads - 1 do
        for higher_index = lower_index + 1, #squads do
            local lower = squads[lower_index]
            local higher = squads[higher_index]
            ---@type RatingPairResult
            local row = {
                higher = higher,
                lower = lower,
                gap = higher.rating - lower.rating,
                games = seeds_per_leg * 2,
                wins = 0,
                draws = 0,
                losses = 0,
                win_rate = nil,
                score_share = 0,
            }
            for seed = 1, seeds_per_leg do
                local higher_home = headless.run_match({
                    seed = seed,
                    home = higher.team,
                    away = lower.team,
                    players_by_id = by_id,
                    bot = "home",
                })
                record_outcome(higher_home, "home", row)

                local lower_home = headless.run_match({
                    seed = seed,
                    home = lower.team,
                    away = higher.team,
                    players_by_id = by_id,
                    bot = "home",
                })
                record_outcome(lower_home, "away", row)
            end

            local decisions = row.wins + row.losses
            row.win_rate = decisions > 0 and row.wins / decisions or nil
            row.score_share = (row.wins + row.draws * 0.5) / row.games
            all_wins = all_wins + row.wins
            all_draws = all_draws + row.draws
            all_losses = all_losses + row.losses
            pairs[#pairs + 1] = row
        end
    end
    table.sort(pairs, function(a, b)
        if a.gap == b.gap then
            return a.higher.team.id < b.higher.team.id
        end
        return a.gap < b.gap
    end)

    local decisions = all_wins + all_losses
    local games = all_wins + all_draws + all_losses
    local above_half_pairs = 0
    for _, pair in ipairs(pairs) do
        if pair.score_share > 0.5 then
            above_half_pairs = above_half_pairs + 1
        end
    end
    return {
        seeds_per_leg = seeds_per_leg,
        squads = squads,
        pairs = pairs,
        wins = all_wins,
        draws = all_draws,
        losses = all_losses,
        win_rate = decisions > 0 and all_wins / decisions or nil,
        score_share = (all_wins + all_draws * 0.5) / games,
        above_half_pairs = above_half_pairs,
        slope = score_share_slope(pairs),
    }
end

---@param result RatingValidationResult
---@return string
function validation.report(result)
    local out = {
        ("squad-rating validation: %d existing-data squads, %d shared seeds, two legs per pair"):format(
            #result.squads,
            result.seeds_per_leg
        ),
        "relative bot-proxy result: each squad gets home + human-proxy once per shared seed",
        "ratings (frozen position-weighted sum, 0..50):",
    }
    for _, squad in ipairs(result.squads) do
        out[#out + 1] = ("  %-12s %6.2f"):format(squad.team.name, squad.rating)
    end

    out[#out + 1] = ""
    out[#out + 1] = ("%-12s %-12s %6s %9s %10s %11s"):format(
        "higher",
        "lower",
        "gap",
        "W-D-L",
        "decisive",
        "score share"
    )
    for _, pair in ipairs(result.pairs) do
        local decisive = pair.win_rate and ("%6.1f%%"):format(pair.win_rate * 100) or "   n/a"
        out[#out + 1] = ("%-12s %-12s %6.2f %2d-%2d-%2d %10s %10.1f%%"):format(
            pair.higher.team.name,
            pair.lower.team.name,
            pair.gap,
            pair.wins,
            pair.draws,
            pair.losses,
            decisive,
            pair.score_share * 100
        )
    end

    local decisive = result.win_rate and ("%.1f%%"):format(result.win_rate * 100) or "n/a"
    out[#out + 1] = ""
    out[#out + 1] = ("aggregate higher-rated: %d-%d-%d, decisive win %s, score share %.1f%%"):format(
        result.wins,
        result.draws,
        result.losses,
        decisive,
        result.score_share * 100
    )
    out[#out + 1] = ("pairs above 50%% score share: %d/%d"):format(
        result.above_half_pairs,
        #result.pairs
    )
    out[#out + 1] = ("curve steepness (OLS score share): %+.2f percentage points per rating point"):format(
        result.slope * 100
    )
    return table.concat(out, "\n")
end

return validation
