local Credits = require("game.screens.credits")
local Title = require("game.screens.title")
local build_info = require("game.build_info")
local hit = require("game.ui.hit")
local t = require("spec.support.runner")

local VIEWPORT = { w = 960, h = 540 }

t.describe("Galactic Cup branding", function()
    t.it("uses the canonical name in metadata and player-facing shell screens", function()
        t.eq(build_info.name, "Galactic Cup")

        local title = assert(hit.find(Title.layout(Title.new_state(VIEWPORT)), "title"))
        t.eq(title.text, "GALACTIC CUP")

        local credits = assert(hit.find(Credits.layout(Credits.new_state(VIEWPORT)), "credits"))
        t.is_true(assert(credits.text):match("GALACTIC CUP") ~= nil)
        t.is_true(credits.text:match("Galactic Cup contributors") ~= nil)
    end)

    t.it("uses the corrected technical save identity", function()
        t.eq(love.filesystem.getIdentity(), "galactic_cup")
    end)
end)
