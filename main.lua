-- Entry point. Two modes:
--   love .          -> run the game (screen stack)
--   love . --test   -> run the headless test suite and exit with status code

---@param a string
---@return boolean
local function has_flag(a)
    for _, v in ipairs(arg or {}) do
        if v == a then
            return true
        end
    end
    return false
end

if has_flag("--test") then
    function love.load()
        local runner = require("spec.support.runner")
        runner.load_and_run("spec")
        os.exit(runner.summary() and 0 or 1)
    end
    return
end

local ScreenStack = require("game.screen_stack")
local Flow = require("game.flow")

---@type ScreenStack
local stack

function love.load()
    stack = ScreenStack.new()
    local viewport = { w = love.graphics.getWidth(), h = love.graphics.getHeight() }
    Flow.start(stack, viewport)
end

---@param dt number
function love.update(dt)
    stack:update(dt)
end

function love.draw()
    stack:draw()
end

---@param key string
function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
        return
    end
    stack:event({ kind = "key", key = key })
end

---@param x number
---@param y number
---@param button number
function love.mousepressed(x, y, button)
    stack:event({ kind = "click", x = x, y = y, button = button })
end
