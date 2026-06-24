-- The playable 5v5 match screen. Gathers input, delegates all simulation to
-- `sim.match`, and renders the result. Drawing lives ONLY here (AGENTS.md §2).

local sim_match = require("sim.match")
local teams = require("data.teams")
local tactics = require("data.tactics")
local pitch = require("game.render.pitch")
local bloom = require("game.render.bloom")
local view_state = require("game.render.view_state")
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
---@field _dash boolean
local Match = {}
Match.__index = Match

---@param opts { formation: string?, tactic: string? }?
---@return MatchScreen
function Match.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Match)
    self.state = sim_match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = FIELD_W, h = FIELD_H },
        home_formation = opts.formation,
        tactic = opts.tactic and tactics[opts.tactic] or nil,
    })
    self.home_color = teams.nebula.color
    self.away_color = teams.orion.color
    self.home_name = teams.nebula.name
    self.away_name = teams.orion.name
    self._shoot, self._pass, self._switch, self._dash = false, false, false, false
    view_state.reset()
    return self
end

---@param evt InputEvent
function Match:event(evt)
    if evt.kind ~= "key" then
        return
    end
    if evt.key == "space" or evt.key == "j" then
        self._shoot = true
    elseif evt.key == "k" then
        self._pass = true
    elseif evt.key == "lshift" or evt.key == "x" then
        self._dash = true
    elseif evt.key == "tab" or evt.key == "q" then
        self._switch = true
    elseif evt.key == "b" then
        bloom.config.enabled = not bloom.config.enabled
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
        dash = self._dash,
    }
    self._shoot, self._pass, self._switch, self._dash = false, false, false, false
    sim_match.step(self.state, dt, input)
    view_state.update(self.state.players, dt)
end

---@param s MatchState
---@param vp { w: number, h: number }
function Match:draw_frame(s, vp)
    -- World: 2.5D perspective pitch + billboard players.
    pitch.draw(s, vp, { home_color = self.home_color, away_color = self.away_color })

    -- HUD (screen space, unprojected).
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
        vp.w,
        "center"
    )
    love.graphics.print(
        "WASD move  -  Space shoot  -  K pass  -  Tab switch  -  Esc quit",
        16,
        vp.h - 28
    )

    if s.finished then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, vp.w, vp.h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("FULL TIME", 0, vp.h / 2 - 12, vp.w, "center")
    end
end

function Match:draw()
    local s = self.state
    local vp = { w = love.graphics.getWidth(), h = love.graphics.getHeight() }
    bloom.draw(function()
        self:draw_frame(s, vp)
    end)
end

return Match
