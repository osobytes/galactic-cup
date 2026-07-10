-- Squad screen (read-only roster view for now). Pure: new_state/layout/update.

local hit = require("game.ui.hit")
local teams = require("data.teams")
local player_pool = require("data.players")

local M = {}

---@param team TeamData
---@return PlayerData[]
local function roster_of(team)
    local by_id = {}
    for _, p in ipairs(player_pool) do
        by_id[p.id] = p
    end
    local list = {}
    for _, id in ipairs(team.roster) do
        list[#list + 1] = by_id[id]
    end
    return list
end

---@param viewport { w: number, h: number }
---@return table
function M.new_state(viewport)
    return { viewport = viewport, team = teams.nebula, roster = roster_of(teams.nebula) }
end

---@param state table
---@return Layout
function M.layout(state)
    local vp = state.viewport
    ---@type Layout
    local layout = {
        {
            id = "title",
            kind = "title",
            text = state.team.name .. " — Squad",
            rect = { x = 0, y = 40, w = vp.w, h = 30 },
            data = { align = "center" },
        },
    }

    local y = 100
    for i, p in ipairs(state.roster) do
        layout[#layout + 1] = {
            id = "player_" .. i,
            kind = "card",
            text = ("%s   (%s)\nPAC %d   STR %d   TEC %d   STA %d   MEN %d"):format(
                p.name,
                p.position,
                p.stats.pace,
                p.stats.strength,
                p.stats.technique,
                p.stats.stamina,
                p.stats.mental
            ),
            rect = { x = vp.w / 2 - 260, y = y, w = 520, h = 54 },
        }
        y = y + 64
    end

    layout[#layout + 1] = {
        id = "next",
        kind = "button",
        text = "Next",
        rect = { x = vp.w / 2 - 80, y = y + 10, w = 160, h = 44 },
    }
    return layout
end

---@param state table
---@param event InputEvent
---@return table, table?
function M.update(state, event)
    if event.kind == "click" and hit.at(M.layout(state), event.x, event.y) == "next" then
        return state, { go = "formation" }
    end
    return state
end

return M
