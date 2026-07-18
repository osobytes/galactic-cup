local compatibility_metrics = require("game.compatibility_metrics")
local t = require("spec.support.runner")

t.describe("compatibility metrics", function()
    t.it("excludes warm-up work and measures the next update after input", function()
        local metrics = compatibility_metrics.new(0)

        metrics:begin_update(0)
        metrics:finish_update(0.001)
        metrics:begin_update(10)
        metrics:finish_update(10.001)

        t.eq(metrics.sample_number, 1)
        t.eq(#metrics.update_samples, 1)
        t.eq(#metrics.frame_samples, 0)

        metrics:input(10.1, "key_return")
        metrics:begin_update(10.1)
        metrics:finish_update(10.103)
        metrics:begin_draw(10.103)
        metrics:finish_draw(10.105)

        t.eq(#metrics.input_samples, 1)
        t.near(metrics.input_samples[1], 3, 1e-9)
        t.eq(#metrics.draw_samples, 1)
    end)

    t.it("records browser-observable settings state", function()
        local metrics = compatibility_metrics.new(0)
        local value = {
            master_volume = 1,
            sfx_volume = 0.8,
            crowd_volume = 0.55,
            muted = true,
            fullscreen = false,
            screen_shake = true,
            bloom = true,
        }

        metrics:settings(0.5, value)

        t.eq(metrics.sample_number, 0)
    end)

    t.it("starts a new bounded sample after sixty seconds", function()
        local metrics = compatibility_metrics.new(0)
        metrics:begin_update(10)
        metrics:finish_update(10.001)
        metrics:begin_update(70.1)
        metrics:finish_update(70.101)

        t.eq(metrics.sample_number, 2)
        t.eq(#metrics.update_samples, 1)
        t.eq(#metrics.frame_samples, 0)
    end)
end)
