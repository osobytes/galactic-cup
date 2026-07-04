-- The playable 5v5 match screen. Gathers input, delegates all simulation to
-- `sim.match`, and renders the result. Drawing lives ONLY here (AGENTS.md §2).

local sim_match = require("sim.match")
local teams = require("data.teams")
local tactics = require("data.tactics")
local pitch = require("game.render.pitch")
local bloom = require("game.render.bloom")
local effects = require("game.render.effects")
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
---@field _opts { formation: string?, tactic: string? }
---@field _shoot_held_prev boolean
---@field _pass_held_prev boolean
---@field _lob_latch boolean
---@field _pass boolean
---@field _switch boolean
---@field _dash boolean
---@field _dodge boolean
local Match = {}
Match.__index = Match

---@param opts { formation: string?, tactic: string? }?
---@return MatchScreen
function Match.new(opts)
    local self = setmetatable({}, Match)
    self._opts = opts or {}
    self.home_color = teams.nebula.color
    self.away_color = teams.orion.color
    self.home_name = teams.nebula.name
    self.away_name = teams.orion.name
    self:restart()
    return self
end

-- Start a fresh match with the same pre-match choices (formation/tactic).
-- Used at construction and for the full-time rematch.
function Match:restart()
    self.state = sim_match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = FIELD_W, h = FIELD_H },
        home_formation = self._opts.formation,
        tactic = self._opts.tactic and tactics[self._opts.tactic] or nil,
    })
    self._pass, self._switch, self._dash, self._dodge = false, false, false, false
    self._shoot_held_prev = false
    self._pass_held_prev = false
    self._lob_latch = false
    view_state.reset()
    effects.reset()
end

---@param evt InputEvent
function Match:event(evt)
    if evt.kind ~= "key" then
        return
    end
    -- After full time only the rematch keys act; match inputs stop buffering.
    if self.state.finished then
        if evt.key == "r" or evt.key == "return" then
            self:restart()
        end
        return
    end
    -- Contextual actions: the same key means the natural thing for the moment.
    -- Space = shoot with the ball (polled: hold to charge) / tackle without it.
    -- K = pass with the ball / switch player without it.
    local carrying = self.state.owner == self.state.controlled
    if evt.key == "space" then
        if not carrying then
            self._dash = true
        end
    elseif evt.key == "k" then
        -- Passing is polled while carrying (hold to charge the range, release
        -- to play it); off the ball K switches player on the press.
        if not carrying then
            self._switch = true
        end
    elseif evt.key == "c" then
        self._dodge = true
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
    -- Space only reads as "shoot" while carrying; defending, it's the tackle
    -- edge handled in event(). Winning the ball with Space already down starts
    -- a charge — release fires, a natural first-time finish.
    local carrying = self.state.owner == self.state.controlled
    local held = carrying and love.keyboard.isDown("space")
    local k_held = carrying and love.keyboard.isDown("k")
    -- L is a modifier, and fingers naturally lift it a frame before the action
    -- key on release. LATCH it across the hold so "L + K/Space" always lofts,
    -- even when L comes up first.
    local l_down = love.keyboard.isDown("l")
    local firing = (self._shoot_held_prev and not held) or (self._pass_held_prev and not k_held)
    local lob = l_down or (firing and self._lob_latch) or false
    if held or k_held then
        self._lob_latch = self._lob_latch or l_down
    else
        self._lob_latch = false
    end
    ---@type MatchInput
    local input = {
        move = read_move_axis(),
        shoot = self._shoot_held_prev and not held, -- fire on release
        shoot_held = held,
        pass = self._pass_held_prev and not k_held, -- pass fires on release too
        pass_held = k_held,
        switch = self._switch,
        dash = self._dash,
        dodge = self._dodge,
        lob = lob,
        sprint = love.keyboard.isDown("lshift", "rshift"),
    }
    self._shoot_held_prev = held
    self._pass_held_prev = k_held
    self._pass, self._switch, self._dash, self._dodge = false, false, false, false
    sim_match.step(self.state, dt, input)
    view_state.update(self.state.players, dt)
    effects.update(self.state, dt) -- juice layer: event bursts + ball trail
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
        "Move: WASD/Arrows    Sprint: Shift (hold)    Space: Shoot / Tackle    K: Pass / Switch",
        16,
        vp.h - 44
    )
    love.graphics.print(
        "Hold Space/K to charge power & range    L: Lob/Cross    C: Juke    Space in air: Header    Esc: Quit",
        16,
        vp.h - 26
    )

    -- Sprint meter: only drawn while it's not full, so the HUD stays quiet.
    local me = s.players[s.controlled]
    if me.sprint_meter < 1 then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 16, vp.h - 58, 120, 6)
        love.graphics.setColor(0.4, 0.9, 1, 0.9)
        love.graphics.rectangle("fill", 16, vp.h - 58, 120 * me.sprint_meter, 6)
    end

    if s.finished then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, vp.w, vp.h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("FULL TIME", 0, vp.h / 2 - 24, vp.w, "center")
        love.graphics.printf(
            "R / Enter — rematch      Esc — quit",
            0,
            vp.h / 2 + 4,
            vp.w,
            "center"
        )
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
