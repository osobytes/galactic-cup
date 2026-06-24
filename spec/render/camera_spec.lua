local t = require("spec.support.runner")
local camera = require("game.render.camera")

local field = { w = 960, h = 540 }
local vp = { w = 1280, h = 720 }

t.describe("camera.project", function()
    t.it("places nearer points lower on screen than far points", function()
        local _, far_y = camera.project(480, 0, field, vp)
        local _, near_y = camera.project(480, 540, field, vp)
        t.is_true(near_y > far_y)
    end)

    t.it("scales nearer points up relative to far points", function()
        local _, _, far_scale = camera.project(480, 0, field, vp)
        local _, _, near_scale = camera.project(480, 540, field, vp)
        t.is_true(near_scale > far_scale)
    end)

    t.it("keeps the pitch centre line on the screen centre at any depth", function()
        local far_x = camera.project(480, 0, field, vp)
        local near_x = camera.project(480, 540, field, vp)
        t.near(far_x, vp.w / 2, 1e-6)
        t.near(near_x, vp.w / 2, 1e-6)
    end)

    t.it("spreads the near edge wider than the far edge (trapezoid)", function()
        local far_right = camera.project(960, 0, field, vp)
        local near_right = camera.project(960, 540, field, vp)
        t.is_true(near_right > far_right)
    end)
end)
