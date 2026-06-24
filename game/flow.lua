-- Wires the pre-match screen sequence: Squad -> Formation -> Tactic -> Match.
-- Each menu reports an action; this router pushes the next screen and carries
-- the player's choices forward into the match.

local Menu = require("game.screens.menu")
local squad = require("game.screens.squad")
local formation_screen = require("game.screens.formation")
local tactic_screen = require("game.screens.tactic")
local Match = require("game.screens.match")

local Flow = {}

---@param stack ScreenStack
---@param viewport { w: number, h: number }
function Flow.start(stack, viewport)
    local choice = { formation = "2-1-1", tactic = "balanced" }

    ---@param action table
    local function go(action)
        if action.go == "formation" then
            stack:push(Menu.new(formation_screen, viewport, go))
        elseif action.go == "tactic" then
            choice.formation = action.formation
            stack:push(Menu.new(tactic_screen, viewport, go))
        elseif action.go == "match" then
            choice.tactic = action.tactic
            stack:push(Match.new({ formation = choice.formation, tactic = choice.tactic }))
        end
    end

    stack:push(Menu.new(squad, viewport, go))
end

return Flow
