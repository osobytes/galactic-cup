local t = require("spec.support.runner")
local player_renderer = require("game.render.player_renderer")
local Vec2 = require("core.vec2")

local function stub_graphics()
    local graphics = {}
    local function noop() end
    for _, name in ipairs({
        "setColor",
        "setLineWidth",
        "line",
        "circle",
        "ellipse",
        "arc",
        "polygon",
        "rectangle",
        "push",
        "pop",
        "translate",
        "rotate",
    }) do
        graphics[name] = noop
    end
    return graphics
end

t.describe("aerial player poses", function()
    t.it("draws every reception and strike silhouette headlessly", function()
        local saved = love.graphics
        love.graphics = stub_graphics()
        local ok, err = pcall(function()
            for _, shape in ipairs({ "round", "broad", "angular", "cluster" }) do
                for _, style in ipairs({
                    "leg_control",
                    "chest_control",
                    "volley",
                    "header",
                    "bicycle",
                }) do
                    player_renderer.draw(200, 300, 12, { 0.2, 0.8, 1 }, nil, {
                        facing = Vec2.new(1, 0),
                        is_keeper = false,
                        controlled = true,
                        aerial = 0.8,
                        aerial_style = style,
                        aerial_outcome = "clean",
                        aerial_jump = 0.7,
                        species_shape = shape,
                        species_color = { 1, 0.7, 0.2 },
                        team = "home",
                    })
                end
                player_renderer.draw(200, 300, 12, { 0.2, 0.8, 1 }, nil, {
                    facing = Vec2.new(-1, 0),
                    is_keeper = true,
                    controlled = true,
                    dive = 0.8,
                    dive_dir = Vec2.new(-1, 0),
                    species_shape = shape,
                    species_color = { 1, 0.7, 0.2 },
                    team = "away",
                })
            end
        end)
        love.graphics = saved
        t.is_true(ok, "aerial pose draw error: " .. tostring(err))
    end)
end)
