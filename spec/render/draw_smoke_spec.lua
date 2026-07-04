-- Smoke tests for the impure renderers. We stub love.graphics (disabled in test
-- mode) so the draw code actually executes: this catches nil-field/arithmetic
-- bugs in projection, sorting and layout — everything except the pixels.

local t = require("spec.support.runner")
local pitch = require("game.render.pitch")
local ui_draw = require("game.ui.draw")
local match_sim = require("sim.match")
local teams = require("data.teams")

local function stub_graphics()
    local g = {}
    local noop = function() end
    for _, name in ipairs({
        "setColor",
        "setLineWidth",
        "setBlendMode",
        "rectangle",
        "polygon",
        "line",
        "circle",
        "ellipse",
        "arc",
        "push",
        "pop",
        "translate",
        "rotate",
        "print",
        "printf",
    }) do
        g[name] = noop
    end
    g.getDimensions = function()
        return 1280, 720
    end
    g.getWidth = function()
        return 1280
    end
    g.getHeight = function()
        return 720
    end
    return g
end

---@param fn fun()
---@return boolean ok, string? err
local function with_stub(fn)
    local saved = love.graphics
    love.graphics = stub_graphics()
    local ok, err = pcall(fn)
    love.graphics = saved
    return ok, err
end

t.describe("renderer smoke", function()
    t.it("pitch.draw runs over a real match state", function()
        local ok, err = with_stub(function()
            local s = match_sim.new({
                home = teams.nebula,
                away = teams.orion,
                field = { w = 960, h = 540 },
            })
            s.charge = 0.6 -- exercise the charge-meter path
            pitch.draw(s, { w = 1280, h = 720 }, {
                home_color = teams.nebula.color,
                away_color = teams.orion.color,
            })
        end)
        t.is_true(ok, "pitch.draw error: " .. tostring(err))
    end)

    t.it("ui_draw.layout runs over a mixed layout", function()
        local ok, err = with_stub(function()
            ---@type Layout
            local layout = {
                {
                    id = "t",
                    kind = "title",
                    text = "Title",
                    rect = { x = 0, y = 0, w = 100, h = 20 },
                    data = { align = "center" },
                },
                {
                    id = "b",
                    kind = "button",
                    text = "Go",
                    selected = true,
                    rect = { x = 0, y = 30, w = 80, h = 30 },
                },
                {
                    id = "c",
                    kind = "card",
                    text = "Card",
                    rect = { x = 0, y = 70, w = 200, h = 40 },
                },
            }
            ui_draw.layout(layout)
        end)
        t.is_true(ok, "ui_draw.layout error: " .. tostring(err))
    end)
end)
