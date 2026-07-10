local t = require("spec.support.runner")
local panel = require("game.ui.tuning_panel")
local tuning = require("sim.tuning")
local presets = require("data.tuning_presets")

t.describe("tuning presets data", function()
    t.it("every preset line names a real knob with an in-range value", function()
        for _, p in ipairs(presets) do
            for line in p.blob:gmatch("[^\r\n]+") do
                local key, num = line:match("^([%w_]+)=([%-%d%.eE]+)$")
                local v = key and tonumber(num)
                t.is_true(v ~= nil, p.id .. ": malformed line " .. line)
                local k = tuning.by_key[key]
                t.is_true(k ~= nil, p.id .. ": unknown knob " .. tostring(key))
                t.is_true(v >= k.min and v <= k.max, p.id .. ": " .. key .. " out of range")
            end
        end
    end)

    t.it("the first preset is pure defaults", function()
        t.eq(presets[1].blob, "")
    end)
end)

t.describe("tuning panel F4 preset cycling", function()
    t.it("applies each preset on top of a reset and wraps back to defaults", function()
        tuning.reset()
        panel.open = true
        panel.preset = 1

        panel.key("f4", false) -- -> candidate A
        t.eq(tuning.values.AI_SHOOT_RANGE, 340)
        t.eq(tuning.values.SAVE_SPEED_REF, 700)
        t.is_true(panel.status:find("Candidate A") ~= nil)

        panel.key("f4", false) -- -> candidate B: A's other overrides must clear
        t.eq(tuning.values.AI_SHOOT_RANGE, 300)
        t.is_true(tuning.is_default("SAVE_SPEED_REF"), "presets replace, never stack")

        panel.key("f4", false) -- -> wraps to defaults
        t.is_true(tuning.is_default("AI_SHOOT_RANGE"))

        panel.open = false
    end)
end)
