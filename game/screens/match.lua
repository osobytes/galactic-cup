-- The playable 5v5 match screen. Gathers input, delegates all simulation to
-- `sim.match`, and renders the result. Drawing lives ONLY here (AGENTS.md §2).

local sim_match = require("sim.match")
local fixed_clock = require("sim.fixed_clock")
local arenas = require("data.arenas")
local teams = require("data.teams")
local tactics = require("data.tactics")
local pitch = require("game.render.pitch")
local bloom = require("game.render.bloom")
local effects = require("game.render.effects")
local match_hud_render = require("game.render.match_hud")
local view_state = require("game.render.view_state")
local audio = require("game.audio")
local match_hud = require("game.match_hud")
local onboarding = require("game.match_onboarding")
local tuning_panel = require("game.ui.tuning_panel")
local replay = require("game.render.replay")
local match_input_adapter = require("game.match_input_adapter")
local Vec2 = require("core.vec2")

local FIELD_W = 960
local FIELD_H = 540

---@class MatchScreenOptions
---@field formation string?
---@field tactic string?
---@field home TeamData?
---@field away TeamData?
---@field seed integer?
---@field arena_id string?
---@field show_onboarding boolean?
---@field profile "product"|"playtest"?

---@class MatchScreen : Screen
---@field state MatchState
---@field home_color number[]
---@field away_color number[]
---@field home_name string
---@field away_name string
---@field arena ArenaData
---@field _opts MatchScreenOptions
---@field _profile "product"|"playtest"
---@field _onboarding MatchOnboardingState
---@field _kickoff_banner number
---@field _last_scoring_team "home"|"away"?
---@field _shoot_held_prev boolean
---@field _pass_held_prev boolean
---@field _lob_latch boolean
---@field _pass boolean
---@field _switch boolean
---@field _dash boolean
---@field _dodge boolean
---@field _space_held_prev boolean  -- tracks Space held off the ball for jockey stance
---@field _clock FixedClockState
---@field _input_adapter MatchInputAdapterState
---@field _frame_events MatchEvent[] -- Events produced by every simulation tick in the latest render update.
local Match = {}
Match.__index = Match

---@param opts MatchScreenOptions?
---@return MatchScreen
function Match.new(opts)
    local self = setmetatable({}, Match)
    self._opts = opts or {}
    self._profile = self._opts.profile or "playtest"
    if self._profile == "playtest" and love.window then
        tuning_panel.load() -- playtest tuning persists across runs (F1 panel)
    end
    local home = self._opts.home or teams.nebula
    local away = self._opts.away or teams.orion
    self.home_color = home.color
    self.away_color = away.color
    self.home_name = home.name
    self.away_name = away.name
    self.arena = assert(arenas[self._opts.arena_id or "helios_crown"], "unknown match arena")
    self:restart()
    return self
end

-- Start a fresh match with the same pre-match choices (formation/tactic).
-- Used at construction and for the full-time rematch.
function Match:restart()
    self.state = sim_match.new({
        home = self._opts.home or teams.nebula,
        away = self._opts.away or teams.orion,
        field = { w = FIELD_W, h = FIELD_H },
        home_formation = self._opts.formation,
        tactic = self._opts.tactic and tactics[self._opts.tactic] or nil,
        seed = self._opts.seed,
    })
    self._pass, self._switch, self._dash, self._dodge = false, false, false, false
    self._shoot_held_prev = false
    self._pass_held_prev = false
    self._lob_latch = false
    self._space_held_prev = false
    self._clock = fixed_clock.new()
    self._input_adapter = match_input_adapter.new()
    self._frame_events = {}
    self._last_score = 0
    self._last_home = 0
    self._last_scoring_team = nil
    self._kickoff_banner = 1.15
    self._onboarding = onboarding.new(self._opts.show_onboarding == true)
    self._replay_state = nil
    replay.reset()
    view_state.reset()
    effects.reset()
    audio.load()
    audio.reset()
end

---@param evt InputEvent
function Match:event(evt)
    if evt.kind == "action" then
        if self.state.finished then
            if self._profile == "playtest" and evt.action == "confirm" then
                self:restart()
            end
            return
        end
        if replay.active() then
            if evt.action == "confirm" or evt.action == "pass_switch" then
                replay.stop()
                effects.reset()
            end
            return
        end
        local carrying = self.state.owner == self.state.controlled
        if evt.action == "pass_switch" and not carrying then
            self._switch = true
        elseif evt.action == "juke" then
            self._dodge = true
        end
        return
    end
    if evt.kind ~= "key" then
        return
    end
    -- After full time only the rematch keys act; match inputs stop buffering.
    if self.state.finished then
        if self._profile == "playtest" and (evt.key == "r" or evt.key == "return") then
            self:restart()
        end
        return
    end
    -- Tuning panel (playtest): F1 toggles; while open it owns the keyboard
    -- and the match is paused (see update).
    if self._profile == "playtest" and evt.key == "f1" then
        tuning_panel.toggle()
        return
    end
    if self._profile == "playtest" and tuning_panel.open then
        tuning_panel.key(evt.key, love.keyboard.isDown("lshift", "rshift"))
        return
    end
    -- During a replay the only action is skipping it.
    if replay.active() then
        if evt.key == "space" or evt.key == "return" or evt.key == "k" then
            replay.stop()
            effects.reset() -- drop replay particles before live play returns
        end
        return
    end
    -- Contextual actions: the same key means the natural thing for the moment.
    -- Space = shoot with the ball (polled: hold to charge) / jockey off the ball
    --   (hold to contain; release fires the poke — mirroring shoot's hold/release).
    -- K = pass with the ball / switch player without it.
    local carrying = self.state.owner == self.state.controlled
    if evt.key == "k" then
        -- Passing is polled while carrying (hold to charge the range, release
        -- to play it); off the ball K switches player on the press.
        if not carrying then
            self._switch = true
        end
    elseif evt.key == "c" then
        self._dodge = true
    elseif self._profile == "playtest" and evt.key == "b" then
        bloom.config.enabled = not bloom.config.enabled
    elseif evt.key == "m" then
        audio.toggle_mute()
    end
end

---@return love.Joystick?
local function active_gamepad()
    if not love.joystick or not love.joystick.getJoysticks then
        return nil
    end
    local joysticks = love.joystick.getJoysticks()
    return joysticks[1]
end

---@param button love.GamepadButton
---@return boolean
local function gamepad_down(button)
    local joystick = active_gamepad()
    return joystick ~= nil and joystick:isGamepadDown(button)
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
    local joystick = active_gamepad()
    if joystick then
        local gx = joystick:getGamepadAxis("leftx")
        local gy = joystick:getGamepadAxis("lefty")
        if math.abs(gx) >= 0.2 then
            x = x + gx
        end
        if math.abs(gy) >= 0.2 then
            y = y + gy
        end
        if joystick:isGamepadDown("dpleft") then
            x = x - 1
        end
        if joystick:isGamepadDown("dpright") then
            x = x + 1
        end
        if joystick:isGamepadDown("dpup") then
            y = y - 1
        end
        if joystick:isGamepadDown("dpdown") then
            y = y + 1
        end
    end
    return Vec2.new(x, y)
end

---@param dt number
function Match:update(dt)
    if self._profile == "playtest" and tuning_panel.open then
        return -- paused for tuning: tweak, close, resume
    end
    -- Slow-motion goal replay: the sim freezes while the buffer plays back
    -- through the normal renderer (same camera).
    if replay.active() then
        self._replay_state = replay.step(dt)
        if self._replay_state then
            view_state.update(self._replay_state.players, dt)
            effects.update(self._replay_state, dt)
        else
            effects.reset() -- replay over: clean slate for the live kickoff
        end
        audio.tick(dt)
        return
    end
    if self.state.finished then
        audio.tick(dt)
        return
    end
    self._kickoff_banner = math.max(0, self._kickoff_banner - dt)
    -- Space reads as "shoot" while carrying (hold to charge, release to fire);
    -- off the ball it is "jockey" while held and fires the poke on release
    -- — mirroring the on-ball hold/release pattern so muscle memory transfers.
    local carrying = self.state.owner == self.state.controlled
    local shoot_down = love.keyboard.isDown("space") or gamepad_down("a")
    local held = carrying and shoot_down
    local space_down_offball = (not carrying) and shoot_down
    local k_held = carrying and (love.keyboard.isDown("k") or gamepad_down("x"))
    -- Jockey release: Space was held last frame off the ball and is now up.
    if self._space_held_prev and not space_down_offball and not carrying then
        self._dash = true
    end
    -- L is a modifier, and fingers naturally lift it a frame before the action
    -- key on release. LATCH it across the hold so "L + K/Space" always lofts,
    -- even when L comes up first.
    local l_down = love.keyboard.isDown("l") or gamepad_down("y")
    local firing = (self._shoot_held_prev and not held) or (self._pass_held_prev and not k_held)
    local lob = l_down or (firing and self._lob_latch) or false
    if held or k_held then
        self._lob_latch = self._lob_latch or l_down
    else
        self._lob_latch = false
    end
    local move = read_move_axis()
    ---@type MatchInput
    local frame_input = {
        move = move,
        shoot = self._shoot_held_prev and not held, -- fire on release
        shoot_held = held,
        pass = self._pass_held_prev and not k_held, -- pass fires on release too
        pass_held = k_held,
        switch = self._switch,
        dash = self._dash,
        dodge = self._dodge,
        lob = lob,
        sprint = love.keyboard.isDown("lshift", "rshift") or gamepad_down("leftshoulder"),
        jockey = space_down_offball, -- hold Space off the ball: slow shadow stance
        aerial_strike = space_down_offball,
        aerial_acrobatic = space_down_offball and l_down,
    }
    self._shoot_held_prev = held
    self._pass_held_prev = k_held
    self._space_held_prev = space_down_offball
    self._pass, self._switch, self._dash, self._dodge = false, false, false, false

    -- Render input is sampled every update, then the adapter holds one-shot
    -- edges until a canonical simulation tick consumes them. A fast display
    -- therefore cannot drop an action merely because this render update makes
    -- zero simulation progress.
    self._input_adapter = match_input_adapter.sample(self._input_adapter, frame_input)
    self._frame_events = {}
    fixed_clock.advance(self._clock, dt, function(_)
        local next, tick_input = match_input_adapter.next_tick(self._input_adapter)
        self._input_adapter = next
        return tick_input
    end, function(_, tick_input)
        replay.record(self.state) -- Pre-step, so the goal flight remains in the buffer.
        local score_before = self.state.score.home + self.state.score.away
        sim_match.step(self.state, fixed_clock.TICK_SECONDS, tick_input)
        for _, event in ipairs(self.state.events) do
            self._frame_events[#self._frame_events + 1] = event
        end
        effects.consume(self.state)
        audio.consume(self.state)
        -- Preserve the existing goal beat: stop this catch-up batch as soon as
        -- a live goal is scored, then the render update starts its replay.
        local scored = self.state.score.home + self.state.score.away > score_before
        return not self.state.finished and not scored
    end)

    -- Presentation is never a second simulation authority. It follows normal
    -- render dt even on frames that consume zero or several simulation ticks.
    view_state.update(self.state.players, dt)
    effects.tick(dt)
    audio.tick(dt)
    local controlled = self.state.players[self.state.controlled]
    local owner = self.state.owner and self.state.players[self.state.owner] or nil
    self._onboarding = onboarding.update(self._onboarding, {
        carrying = self.state.owner == self.state.controlled,
        defending = owner ~= nil and owner.team == "away",
        keeper_holding = self.state.owner == self.state.controlled
            and controlled.is_keeper
            and not controlled.feet_ball,
        moved = move:length() > 0.2 or frame_input.sprint,
        shot = frame_input.shoot or frame_input.shoot_held,
        passed = frame_input.pass or frame_input.pass_held,
        defended = frame_input.jockey or frame_input.dash or frame_input.switch,
    }, dt)

    -- A goal just went in (score edge, match still live): celebrate, then roll
    -- the replay. Which side scored picks the celebrating team.
    local sh, sa = self.state.score.home, self.state.score.away
    if sh + sa > self._last_score and not self.state.finished then
        local scoring_team = sh > self._last_home and "home" or "away"
        self._last_scoring_team = scoring_team
        if replay.start(scoring_team) then
            effects.reset() -- the scene jumps back in time; drop live particles
        end
    end
    self._last_home, self._last_score = sh, sh + sa
end

---@param s MatchState
---@param vp { w: number, h: number }
function Match:draw_frame(s, vp)
    -- World: 2.5D perspective pitch + billboard players.
    pitch.draw(s, vp, {
        home_color = self.home_color,
        away_color = self.away_color,
        arena = self.arena,
        arena_pulse = math.min(1, self._kickoff_banner),
    })

    ---@type BroadcastPhase?
    local phase = nil
    if self.state.finished then
        phase = "full_time"
    elseif replay.celebrating() then
        phase = "goal"
    elseif replay.active() then
        phase = "replay"
    elseif self._kickoff_banner > 0 then
        phase = "kickoff"
    end
    local tactic = self._opts.tactic and tactics[self._opts.tactic] or nil
    local model = match_hud.model(self.state, {
        home_name = self.home_name,
        away_name = self.away_name,
        arena_name = self.arena.name,
        arena_location = self.arena.location,
        tactic_name = tactic and tactic.name or "Balanced",
        formation_name = self._opts.formation or (self._opts.home or teams.nebula).formation,
        prompt = onboarding.prompt(self._onboarding),
        phase = phase,
        scoring_team = self._last_scoring_team,
    })
    match_hud_render.draw(model, vp)

    if self._profile == "playtest" then
        tuning_panel.draw(vp)
    end
end

function Match:draw()
    local s = self.state
    if replay.active() and self._replay_state then
        s = self._replay_state --[[@as MatchState]]
    end
    local vp = { w = love.graphics.getWidth(), h = love.graphics.getHeight() }
    bloom.draw(function()
        self:draw_frame(s, vp)
    end)
end

return Match
