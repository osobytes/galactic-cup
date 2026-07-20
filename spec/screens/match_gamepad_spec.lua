local Match = require("game.screens.match")
local t = require("spec.support.runner")

t.describe("match screen gamepad input", function()
    t.it("polls the left stick and contextual action button", function()
        local saved_keyboard = love.keyboard
        local saved_joystick = love.joystick
        love.keyboard = {
            isDown = function()
                return false
            end,
        }
        local joystick = {
            getGamepadAxis = function(_, axis)
                return axis == "leftx" and 1 or 0
            end,
            isGamepadDown = function(_, button)
                return button == "a"
            end,
        }
        love.joystick = {
            getJoysticks = function()
                return { joystick }
            end,
        }

        local ok, err = pcall(function()
            local match = Match.new()
            local player = match.state.players[match.state.controlled]
            match:update(1 / 60)
            t.is_true(player.run_vel.x > 0, "left stick drives the controlled player")
            t.is_true(player.charge > 0, "A holds the contextual shot charge")
        end)
        love.keyboard = saved_keyboard
        love.joystick = saved_joystick
        assert(ok, tostring(err))
    end)

    t.it("accepts abstract gamepad actions for off-ball switching", function()
        local match = Match.new()
        match.state.owner = nil
        match:event({ kind = "action", action = "pass_switch", pressed = true })
        t.eq(match._switch, true)
    end)
end)
