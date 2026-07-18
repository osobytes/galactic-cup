local App = require("game.app")
local bootstrap = require("game.bootstrap")
local CompatibilityFlow = require("game.compatibility_flow")
local t = require("spec.support.runner")

---@return SettingsStorage
local function memory_settings()
    return {
        read = function()
            return nil
        end,
        write = function()
            return true
        end,
    }
end

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

    t.it("drives the production bootstrap into and out of the real match", function()
        local flow = CompatibilityFlow.new()
        flow.action_delay = 0
        local app = bootstrap.new(960, 540, { settings_storage = memory_settings() })

        for step = 1, 4 do
            flow:update(app, step)
        end

        t.eq(app.adapter.kind, "real")
        t.eq(app:current_route(), "match")
        local screen = assert(app.stack:current())
        ---@cast screen RealMatchScreen
        screen.match.state.finished = true
        app:update(0.9)
        flow:update(app, 5)
        t.eq(app:current_route(), "result")
        t.is_true(flow.finished)
    end)
end)
