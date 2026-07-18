local fake_result = require("game.fake_result")
local focus = require("game.ui.focus")

---@class FakeMatchScreenContext
---@field request ProductMatchRequest

---@class FakeMatchScreenState
---@field viewport { w: number, h: number }
---@field request ProductMatchRequest
---@field result ProductMatchResult
---@field focus string

---@class FakeMatchScreenModule
local fake_match = {}

---@param viewport { w: number, h: number }
---@param context FakeMatchScreenContext
---@return FakeMatchScreenState
function fake_match.new_state(viewport, context)
    return {
        viewport = viewport,
        request = context.request,
        result = fake_result.for_request(context.request),
        focus = "complete",
    }
end

---@param state FakeMatchScreenState
---@return Layout
function fake_match.layout(state)
    return {
        {
            id = "eyebrow",
            kind = "eyebrow",
            text = "PRODUCT FLOW LABORATORY",
            rect = { x = 0, y = 88, w = state.viewport.w, h = 22 },
            data = { align = "center", focusable = false },
        },
        {
            id = "title",
            kind = "hero_title",
            text = "MATCH TRANSMISSION READY",
            rect = { x = 0, y = 124, w = state.viewport.w, h = 44 },
            data = { align = "center", focusable = false },
        },
        {
            id = "request",
            kind = "card",
            text = table.concat({
                "NEBULA FC  vs  ORION MINERS",
                "FORMATION  " .. state.request.formation_id,
                "TACTIC  " .. state.request.tactic_id:gsub("_", " "):upper(),
                "ARENA  HELIOS CROWN",
                "",
                "The real match adapter is intentionally disconnected until M9.",
            }, "\n"),
            rect = { x = 230, y = 202, w = 500, h = 190 },
            data = { align = "center", focusable = false },
        },
        {
            id = "cancel",
            kind = "button",
            text = "CANCEL",
            focused = state.focus == "cancel",
            rect = { x = 264, y = 438, w = 190, h = 44 },
        },
        {
            id = "complete",
            kind = "button",
            text = "COMPLETE FIXTURE",
            focused = state.focus == "complete",
            rect = { x = 506, y = 438, w = 190, h = 44 },
        },
    }
end

---@param state FakeMatchScreenState
---@param event InputEvent
---@return FakeMatchScreenState, table?
function fake_match.update(state, event)
    local layout = fake_match.layout(state)
    local next = {
        viewport = state.viewport,
        request = state.request,
        result = state.result,
        focus = focus.navigate(layout, state.focus, event) or state.focus,
    }
    if event.kind == "action" and event.action == "back" then
        return next, { go = "cancel" }
    end
    local id = focus.activated(layout, next.focus, event)
    if id then
        next.focus = id
    end
    if id == "complete" then
        return next, { go = "complete", result = next.result }
    elseif id == "cancel" then
        return next, { go = "cancel" }
    end
    return next
end

return fake_match
