-- Goal replays: a ring buffer of lightweight render snapshots recorded every
-- live frame, played back in slow motion through the normal renderer after a
-- goal (same camera). Game-layer only — the sim knows nothing about replays.
--
-- Snapshots copy exactly what pitch.draw touches. Vec2s are immutable in this
-- codebase so aliasing player fields is safe; the BALL is defensively copied
-- because the sim mutates s.ball / s.ball_vel in place in the bounce code.

local Vec2 = require("core.vec2")
local tuning = require("sim.tuning")

local replay = {}

local MAX_SECONDS = 8 -- ring capacity; playback window length is tunable
local EXTRAPOLATE = 12 -- synthetic tail frames: the sim resets for kickoff on
-- the goal frame, so we extend the final ball flight into the net ourselves

local buf, head, count = {}, 0, 0
local playing = false
local playhead = 1
local emitted = 0
local window = {}

local function cap()
    return MAX_SECONDS * 60
end

function replay.reset()
    buf, head, count = {}, 0, 0
    playing = false
    window = {}
end

function replay.active()
    return playing
end

function replay.stop()
    playing = false
    window = {}
end

-- Record one live frame (call BEFORE the sim step so the goal frame's flight
-- is the last thing in the buffer, not the post-kickoff reset).
---@param s MatchState
function replay.record(s)
    local players = {}
    for i, p in ipairs(s.players) do
        players[i] = {
            id = p.id,
            team = p.team,
            pos = p.pos,
            facing = p.facing,
            radius = p.radius,
            is_keeper = p.is_keeper,
            slide_timer = p.slide_timer,
            dive_timer = p.dive_timer,
            dive_dir = p.dive_dir,
            grab_timer = p.grab_timer,
            throw_timer = p.throw_timer,
            windup_timer = p.windup_timer,
            sprint_meter = 1, -- keeps the HUD meter hidden during playback
            jockey_timer = 0,
        }
    end
    local events = {}
    for i, e in ipairs(s.events) do
        events[i] = e
    end
    head = (head % cap()) + 1
    count = math.min(count + 1, cap())
    buf[head] = {
        field = s.field,
        goal_home = s.goal_home,
        goal_away = s.goal_away,
        score = { home = s.score.home, away = s.score.away },
        time_left = s.time_left,
        controlled = s.controlled,
        owner = s.owner,
        ball = Vec2.new(s.ball.x, s.ball.y),
        ball_vel = Vec2.new(s.ball_vel.x, s.ball_vel.y),
        ball_z = s.ball_z,
        ball_vz = s.ball_vz,
        charge = 0,
        pass_charge = 0,
        pass_target = nil,
        finished = false,
        players = players,
        events = events,
    }
end

-- Begin playback of the last REPLAY_SECONDS of footage (+ net-bulge tail).
---@return boolean started
function replay.start()
    local n = math.min(count, math.floor(tuning.values.REPLAY_SECONDS * 60))
    if n < 30 then
        return false -- not enough footage to be worth showing
    end
    window = {}
    for k = n - 1, 0, -1 do
        local idx = ((head - 1 - k) % cap()) + 1
        window[#window + 1] = buf[idx]
    end
    -- Synthetic tail: fly the ball on (simple ballistics) while everyone holds
    -- their final pose, so the shot visibly finishes in the net.
    local last = window[#window]
    for e = 1, EXTRAPOLATE do
        local t = e / 60
        local snap = {}
        for k, v in pairs(last) do
            snap[k] = v
        end
        snap.ball = last.ball:add(last.ball_vel:scale(t))
        snap.ball_z = math.max(0, last.ball_z + last.ball_vz * t - 0.5 * 900 * t * t)
        snap.events = {}
        window[#window + 1] = snap
    end
    playing = true
    playhead = 1
    emitted = 0
    return true
end

-- Advance the playhead and return an interpolated, drawable MatchState-like
-- table — or nil when the replay has finished. `state.events` carries each
-- recorded frame's events exactly once (for the effects layer), regardless of
-- how slowly the playhead crawls across it. (Typed as MatchState for the
-- renderer's benefit: it carries every field the draw path reads.)
---@param dt number
---@return MatchState? state
function replay.step(dt)
    if not playing then
        return nil
    end
    playhead = playhead + dt * 60 * tuning.values.REPLAY_SLOWMO
    local i = math.floor(playhead)
    if i >= #window then
        playing = false
        window = {}
        return nil
    end
    local a, b = window[i], window[i + 1]
    local t = playhead - i
    local st = {}
    for k, v in pairs(a) do
        st[k] = v
    end
    st.ball = a.ball:add(b.ball:sub(a.ball):scale(t))
    st.ball_z = a.ball_z + (b.ball_z - a.ball_z) * t
    local players = {}
    for j, pa in ipairs(a.players) do
        local pb = b.players[j]
        local cp = {}
        for k, v in pairs(pa) do
            cp[k] = v
        end
        cp.pos = pa.pos:add(pb.pos:sub(pa.pos):scale(t))
        players[j] = cp
    end
    st.players = players
    st.events = (i > emitted) and a.events or {}
    emitted = math.max(emitted, i)
    return st
end

return replay
