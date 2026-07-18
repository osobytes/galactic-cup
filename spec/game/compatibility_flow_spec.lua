local App = require("game.app")
local CompatibilityFlow = require("game.compatibility_flow")
local t = require("spec.support.runner")

t.describe("compatibility flow", function()
    t.it("drives the complete fake product flow through the normal input seam", function()
        local inputs = {}
        local flow = CompatibilityFlow.new(function(kind)
            inputs[#inputs + 1] = kind
        end)
        flow.action_delay = 0
        local app = App.new()

        for step = 1, 8 do
            flow:update(app, step)
        end

        t.eq(app:current_route(), "result")
        t.is_true(flow.finished)
        local expected = {
            "compat_click_play",
            "compat_click_next",
            "compat_click_next",
            "compat_click_kickoff",
            "compat_click_complete",
        }
        t.eq(#inputs, #expected)
        for i, value in ipairs(expected) do
            t.eq(inputs[i], value)
        end
    end)
end)
