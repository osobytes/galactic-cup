local focus = require("game.ui.focus")
local players = require("data.players")

---@class ResultScreenContext
---@field result ProductMatchResult

---@class ResultScreenState
---@field viewport { w: number, h: number }
---@field result ProductMatchResult
---@field focus string

---@class ResultScreenModule
local result_screen = {}

---@return table<string, PlayerData>
local function players_by_id()
    local result = {}
    for _, player in ipairs(players) do
        result[player.id] = player
    end
    return result
end

---@param value number?
---@return string
local function percent(value)
    return value and ("%d%%"):format(math.floor(value * 100 + 0.5)) or "—"
end

---@param value integer?
---@return string
local function count(value)
    return value and tostring(value) or "—"
end

---@param viewport { w: number, h: number }
---@param context ResultScreenContext
---@return ResultScreenState
function result_screen.new_state(viewport, context)
    return { viewport = viewport, result = context.result, focus = "rematch" }
end

---@param state ResultScreenState
---@return Layout
function result_screen.layout(state)
    local result = state.result
    local outcome = result.winner == "home" and "NEBULA FC WIN"
        or (result.winner == "away" and "ORION MINERS WIN" or "HONORS EVEN")
    local mvp = result.mvp_player_id and players_by_id()[result.mvp_player_id] or nil
    local mvp_name = mvp and mvp.name or "No MVP awarded"
    local stats = {
        "SHOTS          " .. count(result.home_stats.shots) .. "        " .. count(
            result.away_stats.shots
        ),
        "POSSESSION     " .. percent(result.home_stats.possession) .. "       " .. percent(
            result.away_stats.possession
        ),
        "SAVES          " .. count(result.home_stats.saves) .. "        " .. count(
            result.away_stats.saves
        ),
        "PASS COMPLETE  " .. percent(result.home_stats.pass_completion) .. "       " .. percent(
            result.away_stats.pass_completion
        ),
    }
    local layout = {
        {
            id = "status",
            kind = "eyebrow",
            text = "FULL TIME",
            rect = { x = 0, y = 34, w = state.viewport.w, h = 22 },
            data = { align = "center" },
        },
        {
            id = "outcome",
            kind = "title",
            text = outcome,
            rect = { x = 0, y = 70, w = state.viewport.w, h = 38 },
            data = { align = "center" },
        },
        {
            id = "score",
            kind = "hero_title",
            text = ("%d  —  %d"):format(result.home_score, result.away_score),
            rect = { x = 0, y = 116, w = state.viewport.w, h = 54 },
            data = { align = "center" },
        },
        {
            id = "names",
            kind = "label",
            text = result.home_name .. "                                  " .. result.away_name,
            rect = { x = 180, y = 174, w = 600, h = 22 },
            data = { align = "center", tone = "muted" },
        },
        {
            id = "stats",
            kind = "card",
            text = table.concat(stats, "\n"),
            rect = { x = 180, y = 216, w = 360, h = 158 },
            data = { focusable = false },
        },
        {
            id = "mvp",
            kind = "card",
            text = "MATCH MVP\n"
                .. mvp_name
                .. "\n\n"
                .. (result.mvp_summary or "No summary available."),
            rect = { x = 560, y = 216, w = 220, h = 158 },
            data = { accent = { 1, 0.66, 0.24 }, focusable = false },
        },
    }

    local buttons = {
        { "change_lineup", "LINEUP" },
        { "change_plan", "PLAN" },
        { "main_menu", "MENU" },
        { "rematch", "REMATCH" },
    }
    for i, item in ipairs(buttons) do
        layout[#layout + 1] = {
            id = item[1],
            kind = "button",
            text = item[2],
            focused = state.focus == item[1],
            rect = { x = 72 + (i - 1) * 214, y = 438, w = 174, h = 44 },
        }
    end
    return layout
end

---@param state ResultScreenState
---@param event InputEvent
---@return ResultScreenState, table?
function result_screen.update(state, event)
    local layout = result_screen.layout(state)
    local next = {
        viewport = state.viewport,
        result = state.result,
        focus = focus.navigate(layout, state.focus, event) or state.focus,
    }
    if event.kind == "action" and event.action == "back" then
        return next, { go = "main_menu" }
    end
    local id = focus.activated(layout, next.focus, event)
    if id then
        next.focus = id
        return next, { go = id }
    end
    return next
end

return result_screen
