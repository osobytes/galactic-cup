-- The playable match screen. Gathers input, delegates all simulation to
-- `sim.match`, and renders the result. Drawing lives ONLY here (AGENTS.md §2).

local sim_match = require("sim.match")
local players = require("data.players")
local Vec2 = require("core.vec2")

local FIELD_W = 960
local FIELD_H = 540

---@class MatchScreen : Screen
---@field state MatchState
---@field player_name string
---@field _shoot_queued boolean
local Match = {}
Match.__index = Match

---@return MatchScreen
function Match.new()
    local self = setmetatable({}, Match)
    local p = players[1]
    self.state = sim_match.new(p, FIELD_W, FIELD_H)
    self.player_name = p.name
    self._shoot_queued = false
    return self
end

---@param evt InputEvent
function Match:event(evt)
    if evt.kind == "key" and (evt.key == "space" or evt.key == "j") then
        self._shoot_queued = true
    end
end

---@return Vec2
local function read_move_axis()
    local x, y = 0, 0
    if love.keyboard.isDown("left", "a") then
        x = x - 1
    end
    if love.keyboard.isDown("right", "d") then
        x = x + 1
    end
    if love.keyboard.isDown("up", "w") then
        y = y - 1
    end
    if love.keyboard.isDown("down", "s") then
        y = y + 1
    end
    return Vec2.new(x, y)
end

---@param dt number
function Match:update(dt)
    ---@type MatchInput
    local input = { move = read_move_axis(), shoot = self._shoot_queued }
    self._shoot_queued = false
    sim_match.step(self.state, dt, input)
end

function Match:draw()
    local s = self.state

    -- Pitch.
    love.graphics.setColor(0.06, 0.09, 0.16)
    love.graphics.rectangle("fill", 0, 0, s.field.w, s.field.h)
    love.graphics.setColor(0.15, 0.45, 0.6, 0.5)
    love.graphics.rectangle("line", 8, 8, s.field.w - 16, s.field.h - 16)
    love.graphics.line(s.field.w / 2, 8, s.field.w / 2, s.field.h - 8)
    love.graphics.circle("line", s.field.w / 2, s.field.h / 2, 60)

    -- Goal.
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.rectangle("line", s.goal.x, s.goal.y, s.goal.w, s.goal.h)

    -- Player + facing marker.
    love.graphics.setColor(0.3, 0.7, 1.0)
    love.graphics.circle("fill", s.player.x, s.player.y, s.player_radius)
    local nose = s.player:add(s.facing:scale(s.player_radius))
    love.graphics.setColor(1, 1, 1)
    love.graphics.line(s.player.x, s.player.y, nose.x, nose.y)

    -- Ball.
    love.graphics.setColor(1, 0.95, 0.7)
    love.graphics.circle("fill", s.ball.x, s.ball.y, s.ball_radius)

    -- HUD.
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(("%s   Goals: %d"):format(self.player_name, s.score), 16, 16)
    love.graphics.print("WASD/arrows move  -  Space/J shoot  -  Esc quit", 16, s.field.h - 28)
end

return Match
