local FakeMatch = require("game.screens.fake_match")
local Menu = require("game.screens.menu")
local RealMatch = require("game.screens.real_match")

---@class MatchAdapterCallbacks
---@field on_finished fun(result: ProductMatchResult)
---@field on_cancelled fun()

---@class MatchAdapter
---@field new fun(request: ProductMatchRequest, callbacks: MatchAdapterCallbacks, viewport: { w: number, h: number }): Screen
---@field kind "fake"|"real"

---@class MatchAdapterModule
local match_adapter = {}

---@return MatchAdapter
function match_adapter.fake()
    return {
        kind = "fake",
        new = function(request, callbacks, viewport)
            return Menu.new(FakeMatch, viewport, function(action)
                if action.go == "complete" then
                    callbacks.on_finished(action.result)
                elseif action.go == "cancel" then
                    callbacks.on_cancelled()
                end
            end, { request = request })
        end,
    }
end

---@return MatchAdapter
function match_adapter.real()
    return {
        kind = "real",
        new = function(request, callbacks)
            return RealMatch.new(request, callbacks)
        end,
    }
end

return match_adapter
