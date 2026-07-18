local contract = require("game.match_contract")
local players = require("data.players")

---@class FakeResultModule
local fake_result = {}

---@param value string
---@return integer
local function hash(value)
    local result = 17
    for i = 1, #value do
        result = (result * 31 + value:byte(i)) % 104729
    end
    return result
end

---@return table<string, PlayerData>
local function players_by_id()
    local result = {}
    for _, player in ipairs(players) do
        result[player.id] = player
    end
    return result
end

---@param request ProductMatchRequest
---@return ProductMatchResult
function fake_result.for_request(request)
    local seed = request.seed or 1
    local value = hash(table.concat({
        request.formation_id,
        request.tactic_id,
        tostring(seed),
        table.concat(request.home_starter_ids, ","),
    }, ":"))
    local home_score = value % 4
    local away_score = math.floor(value / 7) % 4
    local home_possession = 0.42 + (value % 17) / 100
    local player_map = players_by_id()
    local mvp = request.home_starter_ids[2]
    for _, id in ipairs(request.home_starter_ids) do
        if player_map[id] and player_map[id].position ~= "keeper" then
            mvp = id
            break
        end
    end

    return assert(contract.new_result({
        home_team_id = request.home_team_id,
        away_team_id = request.away_team_id,
        home_score = home_score,
        away_score = away_score,
        mvp_player_id = mvp,
        mvp_summary = "Drove the showcase plan from first whistle to full time.",
        home_stats = {
            shots = 6 + value % 7,
            possession = home_possession,
            saves = 1 + value % 4,
            pass_completion = 0.58 + (value % 20) / 100,
        },
        away_stats = {
            shots = 5 + math.floor(value / 3) % 7,
            possession = 1 - home_possession,
            saves = 1 + math.floor(value / 5) % 4,
            pass_completion = 0.52 + (value % 18) / 100,
        },
        seed = seed,
    }))
end

return fake_result
