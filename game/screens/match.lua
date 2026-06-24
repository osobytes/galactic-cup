-- The playable 5v5 match screen. Gathers input, delegates all simulation to
-- `sim.match`, and renders the result. Drawing lives ONLY here (AGENTS.md §2).

local sim_match = require("sim.match")
local teams = require("data.teams")
local Vec2 = require("core.vec2")

local FIELD_W = 960
local FIELD_H = 540

---@class MatchScreen : Screen
---@field state MatchState
---@field home_color number[]
---@field away_color number[]
---@field home_name string
---@field away_name string
---@field _shoot boolean
---@field _pass boolean
---@field _switch boolean
local Match = {}
Match.__index = Match

---@return MatchScreen
function Match.new()
    local self = setmetatable({}, Match)
    self.state = sim_match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = FIELD_W, h = FIELD_H },
    })
    self.home_color = teams.nebula.color
    self.away_color = teams.orion.color
    self.home_name = teams.nebula.name
    self.away_name = teams.orion.name
    self._shoot, self._pass, self._switch = false, false, false
    return self
end

---@param evt InputEvent
function Match:event(evt)
    if evt.kind ~= "key" then
        return
    end
    if evt.key == "space" or evt.key == "j" then
        self._shoot = true
    elseif evt.key == "k" or evt.key == "lshift" then
        self._pass = true
    elseif evt.key == "tab" or evt.key == "q" then
        self._switch = true
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
    local input = {
        move = read_move_axis(),
        shoot = self._shoot,
        pass = self._pass,
        switch = self._switch,
    }
    self._shoot, self._pass, self._switch = false, false, false
    sim_match.step(self.state, dt, input)
end

---@param goal Rect
local function draw_goal(goal)
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.rectangle("line", goal.x, goal.y, goal.w, goal.h)
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

    draw_goal(s.goal_home)
    draw_goal(s.goal_away)

    -- Players.
    for i, p in ipairs(s.players) do
        local color = (p.team == "home") and self.home_color or self.away_color
        if i == s.controlled then
            love.graphics.setColor(1, 1, 1)
            love.graphics.circle("line", p.pos.x, p.pos.y, p.radius + 4)
        end
        love.graphics.setColor(color[1], color[2], color[3], p.is_keeper and 0.6 or 1.0)
        love.graphics.circle("fill", p.pos.x, p.pos.y, p.radius)
        local nose = p.pos:add(p.facing:scale(p.radius))
        love.graphics.setColor(1, 1, 1)
        love.graphics.line(p.pos.x, p.pos.y, nose.x, nose.y)
    end

    -- Ball.
    love.graphics.setColor(1, 0.95, 0.7)
    love.graphics.circle("fill", s.ball.x, s.ball.y, 6)

    -- HUD.
    love.graphics.setColor(1, 1, 1)
    local mins = math.floor(s.time_left / 60)
    local secs = math.floor(s.time_left % 60)
    love.graphics.printf(
        ("%s  %d - %d  %s     %d:%02d"):format(
            self.home_name,
            s.score.home,
            s.score.away,
            self.away_name,
            mins,
            secs
        ),
        0,
        16,
        s.field.w,
        "center"
    )
    love.graphics.print(
        "WASD move  -  Space shoot  -  K pass  -  Tab switch  -  Esc quit",
        16,
        s.field.h - 28
    )

    if s.finished then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, s.field.w, s.field.h)
        love.graphics.setColor(1, 1, 1)
        local result = "FULL TIME"
        love.graphics.printf(result, 0, s.field.h / 2 - 12, s.field.w, "center")
    end
end

return Match
