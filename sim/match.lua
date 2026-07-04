-- Pure 5v5 match simulation. No love, no drawing, no input gathering.
--
-- Home attacks right (scores in the right goal); away attacks left. One home
-- player is `controlled` by the human; everyone else is AI. Possession is a
-- single `owner` index (nil = loose ball). All state lives in MatchState and
-- `step` advances it deterministically.

local Vec2 = require("core.vec2")
local stats = require("sim.stats")
local placement = require("sim.placement")
local ai = require("sim.ai")
local passing = require("sim.passing")
local formations = require("data.formations")
local tactics = require("data.tactics")
local player_pool = require("data.players")

local PLAYER_RADIUS = 12
local BALL_RADIUS = 6
local FRICTION = 1.2 -- fraction of ball speed shed per second
local STICK_AHEAD = PLAYER_RADIUS + BALL_RADIUS -- dribble offset
local POSSESS_DIST = 22 -- outfield control radius
local KEEPER_DIST = 18 -- keeper catch radius (small enough that corners stay open)
local KEEPER_GUARD = 28 -- how far off-centre a keeper slides (< half the mouth)
local KEEPER_BOX_DEPTH = 160 -- how far off its line the keeper will come to claim
local KEEPER_BOX_PAD = 30 -- vertical margin beyond the posts for the claim zone
local KEEPER_CLAIM_DIST = 40 -- grab radius when actively claiming a ball in the box (priority)
local KEEPER_LEAD = 0.01 -- anticipation lead when claiming a moving ball
local POSSESS_MAX_SPEED = 350 -- outfield can only collect a slow-enough ball
local PASS_SPEED = 320 -- minimum pass pace; long passes are driven harder (see pass_speed_for)
local PASS_ARRIVE_PACE = 70 -- ball speed left when a pass reaches its receiver
local PASS_SPEED_MAX = 620 -- cap so long passes are driven, never rockets
local AI_SHOOT_RANGE = 240 -- AI owner shoots when this close to goal
local GOAL_MOUTH = 110
local RELEASE_CD = 0.3 -- pickup lockout after a shot/pass (seconds)

local STEAL_DIST = 26 -- challenge range to the BALL to dislodge it
local STEAL_ATTEMPT = 40 -- AI commits a poke when the ball is this close (may whiff)
local KICKOFF_CLEAR = 120 -- opponents keep this centre-circle distance at kickoff
local TACKLE_POP_SPEED = 150 -- speed the ball pops out on a tackle
local AI_STEAL_CD = 1.2 -- min seconds between AI tackle attempts (carriers get a beat on the ball)
local KEEPER_SMOTHER = 26 -- keeper takes the ball off a carrier's feet at this range (in its box)

-- Body blocking: a fast loose ball ricochets off an outfield body it hits instead
-- of ghosting through — defenders between the shooter and the goal matter. Slow
-- balls (below POSSESS_MAX_SPEED) are handled by collection; high balls fly over.
local BLOCK_HEIGHT = 20 -- ball at/below this height hits a body (lobs clear ~24 at the blocker)
local BLOCK_DAMP = 0.5 -- fraction of speed kept by the ricochet

-- AI on-ball decision making: an AI carrier passes out of pressure instead of
-- dribbling blindly into a challenge.
local AI_PASS_PRESSURE = 70 -- an opponent this close = pressured, look for a pass
local AI_PASS_MIN_OPEN = 40 -- an outlet must have this much space to be worth it
local AI_PASS_MIN_DIST = 40 -- don't pass to someone standing on your toes
local AI_PASS_MAX_DIST = 420 -- or to someone the other side of the pitch

-- AI shooting: shot power scales with space (the deterministic stand-in for the
-- human's charge). An unpressured striker sets himself and beats the keeper; a
-- closed-down one can only snap off a saveable shot — so defending means
-- closing shooters down, and conceding space concedes goals.
local AI_CHARGE_MIN_SPACE = 25 -- no power bonus with a defender this close
local AI_CHARGE_SPACE_RANGE = 120 -- space beyond that for the full charge bonus
local AI_PASS_RISK_PENALTY = 80 -- scoring malus when a chaser could cut the ground ball

-- Player tackle: the same button does a standing poke when slow, or a committed
-- slide when moving (slide speed scales off current velocity). Slides reach
-- further but lock you in and have a long recovery.
local SLIDE_DURATION = 0.4 -- how long the slide lunge lasts
local SLIDE_MULT = 1.5 -- initial slide speed = current speed × this
local SLIDE_BASE_MIN = 200 -- ...but never slower than this (slide has punch)
local SLIDE_FRICTION = 2.5 -- slide speed decay per second
local SLIDE_REACH = 36 -- slide tackle ball-win range (extended leg)
local SLIDE_CD = 0.9 -- recovery before tackling again after a slide
local STAND_TIMER = 0.14 -- standing-poke active window
local STAND_REACH = 28 -- standing tackle ball-win range
local STAND_CD = 0.4 -- recovery after a standing tackle
local STUN_SLOW = 0.4 -- movement multiplier while stunned
local STUN_TIME = 0.5 -- seconds a player is knocked off balance by a slide hit

-- Ball Z-axis (height). The ball keeps a 2D ground position (ball/ball_vel) plus a
-- scalar height; height gates collection/goals so lobs fly over heads.
local GRAVITY = 900 -- downward accel on ball_vz (px/s^2)
local BOUNCE = 0.55 -- vertical restitution on landing (horizontal speed kept)
local AIR_FRICTION = 0.3 -- horizontal decay/s while airborne (vs ground FRICTION)
local GROUND_GRAB_HEIGHT = 14 -- ball collectable/tacklable only at/below this height
local KEEPER_AIR_GRAB = 60 -- a keeper can claim up to this height inside its box
local CROSSBAR = 70 -- ball at/above this height at the line = over the bar, no goal
local KEEPER_RESPECT_DIST = 70 -- opponents must keep this clear of a keeper in possession
local LAND_SETTLE_VZ = 60 -- below this |vz| on landing, the ball settles (stops bouncing)
local LOB_CLEAR_H = 24 -- a lob must clear roughly head height over a blocker
-- Cap a lob's horizontal speed so it isn't a flat rocket — and so a lobbed pass
-- lands below POSSESS_MAX_SPEED after air drag: the receiver waiting on the spot
-- must be able to collect it instead of watching it bounce through to a chaser.
local MAX_LOB_VH = 400
local CHIP_LINE_Z = 65 -- a chip shot is this high crossing the line (over keeper, under bar)

-- Goalkeeper saves + distribution. Reach/handling are per-keeper (see sim.stats);
-- these are the shared thresholds. Saves are deterministic (no RNG).
-- Save quality = how close the ball is (within reach) + handling − pace. A high
-- quality save is gathered cleanly; a mid one is parried loose; a low one is beaten.
-- Tuned so an uncharged shot placed at a corner is parried (not conceded) by a
-- decent keeper, while a fully charged corner shot still beats it clean, and a
-- charged shot straight at the keeper is parried rather than swallowed.
local SAVE_SPEED_REF = 1300 -- shot speed that fully cancels save quality
local CATCH_QUALITY = 0.45 -- at/above this the keeper gathers the ball cleanly
local PARRY_QUALITY = 0.1 -- below catch but >= this: deflected loose; below: beaten
local HANDLING_WEIGHT = 0.5 -- how much keeper handling lifts save quality
local PARRY_CD = 0.18 -- pickup lockout after a parry (stops instant re-grab/re-dive)
local PARRY_SPEED_MULT = 0.6 -- fraction of incoming speed kept on a deflection
local MIN_PARRY_CLEAR = 260 -- a parry is always punched at least this fast (clear of traffic)
-- A parry is tipped UP as well as out: the deflection sails over the shooter's
-- head instead of being served back to their feet (where it would ricochet off
-- their body straight back at the goal — a guaranteed rebound tap-in).
local PARRY_POP_VZ = 240
local KEEPER_HOLD = 0.9 -- seconds a keeper surveys/holds before distributing
local KEEPER_DIVE_DURATION = 0.32 -- dive lunge / animation window
local KEEPER_SAFE_DIST = 60 -- a distribution outlet must be this clear of opponents
-- A floated throw needs the receiver a real step off its marker: body collision
-- keeps players ~24px apart and the AI steal range is 26, so a receiver marked
-- tighter than this would be dispossessed the moment the throw lands.
local THROW_MIN_OPEN = 30
local DROPKICK_DIST = 420 -- how far upfield a drop-kick clearance lands
local DROPKICK_CLEAR_H = 46 -- drop-kick loft: sails over every head on the way
local SAVE_PAD = 18 -- on-target tolerance beyond the posts when projecting a shot
local SAVE_ZONE = 130 -- the keeper commits a dive once the shot is this close to its line
local KEEPER_GRAB_POSE = 0.25 -- seconds of the gather/reach pose after a grab
local KEEPER_THROW_POSE = 0.25 -- seconds of the release/throw pose after distributing
local RECEIVE_TIME = 1.3 -- seconds the intended receiver runs onto a keeper's distribution

local CHARGE_RATE = 1.5 -- charge per second while holding shoot (caps at 1)
local CHARGE_POWER = 0.9 -- full charge adds this fraction to shot speed
local CURVE_MAX = 520 -- lateral acceleration of a full-charge curved shot
local SPIN_DECAY = 1.4 -- how fast curve bleeds off
local DODGE_DURATION = 0.16 -- length of a juke (seconds)
local DODGE_CD = 0.6 -- juke cooldown (seconds)
local DODGE_SPEED_MULT = 2.4 -- sideways speed during a juke

-- Sprint (controlled player): a hold-to-run burst from a stamina tank. The tank
-- size is stamina-derived (see sim.stats); it refills while not sprinting.
local SPRINT_MULT = 1.35 -- speed multiplier while sprinting
local SPRINT_REFILL = 0.4 -- meter refilled per second when not sprinting
local SPRINT_ENGAGE = 0.25 -- min meter to start a sprint (hysteresis: no flicker at empty)

---@class MatchPlayer
---@field id string
---@field name string
---@field team "home"|"away"
---@field pos Vec2
---@field vel Vec2  -- realized velocity (px/s) from last tick's movement; AI prediction source
---@field facing Vec2
---@field anchor Vec2
---@field move_speed number
---@field shot_speed number
---@field is_keeper boolean
---@field radius number
---@field dash_cd number  -- AI tackle cooldown (seconds until it can challenge again)
---@field dodge_cd number  -- seconds until a juke is ready again
---@field dodge_timer number  -- seconds of juke (sidestep + tackle immunity) remaining
---@field dodge_dir Vec2  -- sidestep direction for the active juke
---@field reach number  -- keeper dive/save radius in px (0 for outfield)
---@field handling number  -- keeper clean-catch factor 0..1 (0 for outfield)
---@field dive_timer number  -- seconds of keeper dive lunge remaining
---@field dive_dir Vec2  -- unit direction of the active dive
---@field hold_timer number  -- seconds a keeper holds the ball before distributing
---@field slide_timer number  -- seconds of an active slide tackle remaining
---@field slide_dir Vec2  -- locked travel direction of the slide
---@field slide_vel number  -- current slide speed (px/s), decays over the slide
---@field tackle_timer number  -- seconds of a standing-tackle poke window remaining
---@field tackle_cd number  -- recovery before another tackle/slide can start
---@field stun_timer number  -- seconds knocked off balance (slowed, can't tackle)
---@field grab_timer number  -- keeper gather/reach pose remaining (visual)
---@field throw_timer number  -- keeper release/throw pose remaining (visual)
---@field receive_timer number  -- seconds this player is running onto an incoming pass
---@field sprint_meter number  -- 0..1 stamina tank for sprinting
---@field sprint_dur number  -- seconds a full tank lasts (stamina-derived)
---@field sprinting boolean  -- currently sprint-boosted (hysteresis state)

---@alias Rect { x: number, y: number, w: number, h: number }

---@class MatchInput
---@field move Vec2  -- controlled player's desired direction
---@field shoot boolean  -- fire the shot (released this frame)
---@field shoot_held boolean  -- shoot key currently down (builds charge)
---@field pass boolean
---@field switch boolean  -- hand control to the outfielder nearest the ball
---@field dash boolean  -- tackle attempt (slide when moving fast, poke when slow)
---@field dodge boolean  -- sidestep juke with brief tackle immunity
---@field lob boolean  -- loft modifier: chip a shot / lob a pass over a defender
---@field sprint boolean  -- hold to sprint (drains the sprint meter)

-- One-frame notifications of discrete actions, for the renderer's juice layer
-- (flashes, trails). Produced by the sim, cleared at the top of every step, so
-- a frame's events are whatever happened during that frame. Positions are world
-- space; `player` is the actor's id (nil for ball-only events).
---@class MatchEvent
---@field kind "shot"|"pass"|"touch"|"tackle"|"catch"|"parry"|"claim"|"block"
---@field x number
---@field y number
---@field player string?

---@class MatchState
---@field field { w: number, h: number }
---@field goal_home Rect  -- left goal; away scores here
---@field goal_away Rect  -- right goal; home scores here
---@field players MatchPlayer[]  -- home indices 1..5, away 6..10
---@field ball Vec2  -- ground position (x, y); height is ball_z
---@field ball_vel Vec2  -- horizontal velocity (ground plane)
---@field ball_z number  -- height above the pitch (0 = on the ground)
---@field ball_vz number  -- vertical velocity (+ = rising)
---@field owner integer?  -- index into players, nil if loose
---@field controlled integer  -- index of the human-controlled home player
---@field score { home: integer, away: integer }
---@field time_left number
---@field max_goals integer
---@field finished boolean
---@field pickup_cd number
---@field press { home: integer, away: integer }  -- chasers per team (tactic-driven)
---@field marking { home: MarkingConfig, away: MarkingConfig }  -- off-ball scheme per team
---@field marks { home: table<integer, integer>, away: table<integer, integer> }  -- prev marking assignment (hysteresis)
---@field charge number  -- controlled carrier's shot charge, 0..1
---@field ball_spin number  -- lateral curve applied to the loose ball
---@field events MatchEvent[]  -- discrete actions this frame (see MatchEvent)

local match = {}

---@return table<string, PlayerData>
local function pool_by_id()
    local by_id = {}
    for _, p in ipairs(player_pool) do
        by_id[p.id] = p
    end
    return by_id
end

---@param team TeamData
---@param side "home"|"away"
---@param field { w: number, h: number }
---@param by_id table<string, PlayerData>
---@param formation_id string?  -- override team.formation
---@param line_shift number  -- tactic depth bias (fraction of pitch, toward attack)
---@return MatchPlayer[]
local function build_team(team, side, field, by_id, formation_id, line_shift)
    local formation = formations[formation_id or team.formation]
    assert(formation, "unknown formation: " .. tostring(formation_id or team.formation))
    local anchors = placement.anchors(formation, side, field)
    local shift = (side == "home" and 1 or -1) * line_shift * field.w

    -- Keeper first, then outfield in roster order (matches formation order).
    local keeper_id, outfield = nil, {}
    for _, id in ipairs(team.roster) do
        local pd = by_id[id]
        assert(pd, "unknown player: " .. tostring(id))
        if pd.position == "keeper" and not keeper_id then
            keeper_id = id
        else
            outfield[#outfield + 1] = id
        end
    end
    assert(keeper_id, team.id .. " roster needs a keeper")

    local ordered = { keeper_id }
    for _, id in ipairs(outfield) do
        ordered[#ordered + 1] = id
    end

    local list = {}
    for i, id in ipairs(ordered) do
        local pd = by_id[id]
        local base = anchors[i]
        -- Outfield anchors shift with the tactic; the keeper (i == 1) stays home.
        local ax = base.x
        if i > 1 then
            ax = math.max(PLAYER_RADIUS, math.min(field.w - PLAYER_RADIUS, base.x + shift))
        end
        local anchor = Vec2.new(ax, base.y)
        list[i] = {
            id = id,
            name = pd.name,
            team = side,
            pos = Vec2.new(anchor.x, anchor.y),
            vel = Vec2.new(0, 0),
            facing = Vec2.new(side == "home" and 1 or -1, 0),
            anchor = anchor,
            move_speed = stats.move_speed(pd.stats),
            shot_speed = stats.shot_speed(pd.stats),
            is_keeper = pd.position == "keeper",
            radius = PLAYER_RADIUS,
            dash_cd = 0,
            dodge_cd = 0,
            dodge_timer = 0,
            dodge_dir = Vec2.new(0, 0),
            reach = (pd.position == "keeper") and stats.keeper_reach(pd.stats) or 0,
            handling = (pd.position == "keeper") and stats.keeper_handling(pd.stats) or 0,
            dive_timer = 0,
            dive_dir = Vec2.new(0, 0),
            hold_timer = 0,
            slide_timer = 0,
            slide_dir = Vec2.new(0, 0),
            slide_vel = 0,
            tackle_timer = 0,
            tackle_cd = 0,
            stun_timer = 0,
            grab_timer = 0,
            throw_timer = 0,
            receive_timer = 0,
            sprint_meter = 1,
            sprint_dur = stats.sprint_duration(pd.stats),
            sprinting = false,
        }
    end
    return list
end

-- Index of the most advanced home outfield player (the default controlled one).
---@param players MatchPlayer[]
---@return integer
local function most_advanced_home(players)
    local best, best_x
    for i, p in ipairs(players) do
        if p.team == "home" and not p.is_keeper then
            if not best_x or p.pos.x > best_x then
                best_x = p.pos.x
                best = i
            end
        end
    end
    return best or 1
end

-- Reset for a kickoff. `kicking` is the team restarting play (after conceding,
-- per the laws of the game); the opening kickoff is the home side's.
---@param s MatchState
---@param kicking "home"|"away"?
local function place_kickoff(s, kicking)
    kicking = kicking or "home"
    for _, p in ipairs(s.players) do
        p.pos = Vec2.new(p.anchor.x, p.anchor.y)
        p.vel = Vec2.new(0, 0)
        p.facing = Vec2.new(p.team == "home" and 1 or -1, 0)
        p.dive_timer = 0
        p.dive_dir = Vec2.new(0, 0)
        p.hold_timer = 0
        p.slide_timer = 0
        p.slide_dir = Vec2.new(0, 0)
        p.slide_vel = 0
        p.tackle_timer = 0
        p.tackle_cd = 0
        p.stun_timer = 0
        p.grab_timer = 0
        p.throw_timer = 0
        p.receive_timer = 0
        p.sprint_meter = 1
        p.sprinting = false
    end
    -- Give the kicking team the ball at the centre spot.
    local kicker
    if kicking == "home" then
        s.controlled = most_advanced_home(s.players)
        kicker = s.controlled
    else
        -- The most advanced away outfielder (away attacks -x) takes the kickoff;
        -- the human gets their most advanced player to defend with.
        local best_x
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                if not best_x or p.pos.x < best_x then
                    best_x = p.pos.x
                    kicker = i
                end
            end
        end
        s.controlled = most_advanced_home(s.players)
    end
    local c = s.players[kicker]
    c.facing = Vec2.new(kicking == "home" and 1 or -1, 0)
    c.pos = Vec2.new(s.field.w * (kicking == "home" and 0.45 or 0.55), s.field.h / 2)
    s.ball = c.pos:add(c.facing:scale(STICK_AHEAD))
    s.ball_vel = Vec2.new(0, 0)
    s.ball_z = 0
    s.ball_vz = 0
    s.owner = kicker
    s.pickup_cd = 0
    s.charge = 0
    s.ball_spin = 0
    -- Centre-circle rule: the non-kicking team keeps its distance from the
    -- ball at the restart — push any intruder straight back out.
    for _, p in ipairs(s.players) do
        if p.team ~= kicking and not p.is_keeper then
            local off = p.pos:sub(s.ball)
            local d = off:length()
            if d < KICKOFF_CLEAR then
                local dir = (d > 0) and off:normalized()
                    or Vec2.new(p.team == "home" and -1 or 1, 0)
                local np = s.ball:add(dir:scale(KICKOFF_CLEAR))
                p.pos = Vec2.new(
                    math.max(PLAYER_RADIUS, math.min(s.field.w - PLAYER_RADIUS, np.x)),
                    math.max(PLAYER_RADIUS, math.min(s.field.h - PLAYER_RADIUS, np.y))
                )
            end
        end
    end
end

-- Hybrid default so tactics authored before the marking block still work.
local DEFAULT_MARKING =
    { scheme = "hybrid", man_marks = 1, standoff = 24, compactness = 0.5, support = 0.5 }

---@param tactic TacticData
---@return MarkingConfig
local function marking_of(tactic)
    return tactic.marking or DEFAULT_MARKING
end

---@param opts { home: TeamData, away: TeamData, field: { w: number, h: number }, home_formation: string?, tactic: TacticData?, away_tactic: TacticData?, duration: number?, max_goals: integer?, players_by_id: table<string, PlayerData>? }
---@return MatchState
function match.new(opts)
    local field = opts.field
    local by_id = opts.players_by_id or pool_by_id()
    local home_tactic = opts.tactic or tactics.balanced
    local away_tactic = opts.away_tactic or tactics.balanced

    local home =
        build_team(opts.home, "home", field, by_id, opts.home_formation, home_tactic.line_shift)
    local away = build_team(opts.away, "away", field, by_id, nil, away_tactic.line_shift)
    local players = {}
    for _, p in ipairs(home) do
        players[#players + 1] = p
    end
    for _, p in ipairs(away) do
        players[#players + 1] = p
    end

    local mouth_y = field.h / 2 - GOAL_MOUTH / 2
    ---@type MatchState
    local s = {
        field = field,
        goal_home = { x = 0, y = mouth_y, w = 10, h = GOAL_MOUTH },
        goal_away = { x = field.w - 10, y = mouth_y, w = 10, h = GOAL_MOUTH },
        players = players,
        ball = Vec2.new(0, 0),
        ball_vel = Vec2.new(0, 0),
        ball_z = 0,
        ball_vz = 0,
        owner = nil,
        controlled = most_advanced_home(players),
        score = { home = 0, away = 0 },
        time_left = opts.duration or 120,
        max_goals = opts.max_goals or 3,
        finished = false,
        pickup_cd = 0,
        press = { home = home_tactic.press, away = away_tactic.press },
        marking = { home = marking_of(home_tactic), away = marking_of(away_tactic) },
        marks = { home = {}, away = {} },
        charge = 0,
        ball_spin = 0,
        events = {},
    }
    place_kickoff(s)
    return s
end

---@param s MatchState
---@param pos Vec2
---@return Vec2
local function clamp_to_field(s, pos)
    local r = PLAYER_RADIUS
    local x = math.max(r, math.min(s.field.w - r, pos.x))
    local y = math.max(r, math.min(s.field.h - r, pos.y))
    return Vec2.new(x, y)
end

---@param ball Vec2
---@param goal Rect
---@return boolean
local function in_mouth(ball, goal)
    return ball.y >= goal.y and ball.y <= goal.y + goal.h
end

-- Set (index -> true) of the `count` non-keepers of `team` nearest the ball.
---@param s MatchState
---@param team "home"|"away"
---@param count integer
---@return table<integer, boolean>
local function nearest_n(s, team, count)
    local cand = {}
    for i, p in ipairs(s.players) do
        if p.team == team and not p.is_keeper then
            cand[#cand + 1] = { idx = i, d = p.pos:dist(s.ball) }
        end
    end
    table.sort(cand, function(a, b)
        return a.d < b.d
    end)
    local set = {}
    for k = 1, math.min(count, #cand) do
        set[cand[k].idx] = true
    end
    return set
end

-- Manual switch: hand control to the home outfielder nearest the ball (other
-- than the current one) — the player you actually want when defending.
---@param s MatchState
---@param cur integer
---@return integer
local function next_home_outfield(s, cur)
    local best, best_d
    for i, p in ipairs(s.players) do
        if p.team == "home" and not p.is_keeper and i ~= cur then
            local d = p.pos:dist(s.ball)
            if not best_d or d < best_d then
                best_d, best = d, i
            end
        end
    end
    return best or cur
end

-- Launch a lob from `from` to `to` clearing height `h` over a blocker at lane
-- fraction `f`. Returns the horizontal velocity and the vertical launch speed so
-- the ball lands on `to`. Closed-form, deterministic.
---@param from Vec2
---@param to Vec2
---@param f number  -- blocker position along the lane, 0..1
---@param h number  -- height to clear at the blocker
---@return Vec2 vel
---@return number vz
local function lob_launch(from, to, f, h)
    local dir = to:sub(from)
    local d = dir:length()
    if d < 1 then
        return Vec2.new(0, 0), math.sqrt(2 * h * GRAVITY)
    end
    f = math.max(0.15, math.min(0.85, f))
    local tf = math.max(math.sqrt(2 * h / (GRAVITY * f * (1 - f))), d / MAX_LOB_VH)
    tf = math.min(tf, 1.0) -- keep lobs from becoming moon-balls
    return dir:normalized():scale(d / tf), 0.5 * GRAVITY * tf
end

---@param s MatchState
---@param owner MatchPlayer
---@param dir Vec2
---@param speed number?  -- defaults to the shooter's base shot speed
---@param vz number?  -- vertical launch (a chip); defaults to 0 (driven, on the ground)
local function release_shot(s, owner, dir, speed, vz)
    s.events[#s.events + 1] = { kind = "shot", x = s.ball.x, y = s.ball.y, player = owner.id }
    s.owner = nil
    s.ball_vel = dir:normalized():scale(speed or owner.shot_speed)
    s.ball_z = 0
    s.ball_vz = vz or 0
    s.pickup_cd = RELEASE_CD
end

-- Pace a ground pass so it actually arrives: friction sheds FRICTION of the
-- ball's speed per second, so a pass launched at v covers roughly v/FRICTION
-- before dying. Aim to reach the receiver with a touch of pace left.
---@param d number  -- distance to the receiver
---@return number speed
local function pass_speed_for(d)
    return math.min(PASS_SPEED_MAX, math.max(PASS_SPEED, PASS_ARRIVE_PACE + FRICTION * d))
end

-- Opposing outfielders as interception threats against a pass by `team`.
-- Keepers are excluded: they hold their box instead of chasing lanes.
---@param s MatchState
---@param team "home"|"away"
---@return Threat[]
local function pass_threats(s, team)
    local threats = {}
    for _, p in ipairs(s.players) do
        if p.team ~= team and not p.is_keeper then
            threats[#threats + 1] = { pos = p.pos, speed = p.move_speed }
        end
    end
    return threats
end

-- Earliest lane fraction where a chaser would cut out a driven ground pass
-- from->to (paced by pass_speed_for), or nil when the pass outruns everyone.
---@param from Vec2
---@param to Vec2
---@param threats Threat[]
---@return number? fraction
local function pass_risk(from, to, threats)
    local speed = pass_speed_for(from:dist(to))
    return ai.pass_intercept(from, to, speed, FRICTION, threats, POSSESS_DIST, POSSESS_MAX_SPEED)
end

-- Release a pass from `owner_idx` to teammate `target_idx`: fires the event,
-- paces the ball by distance (or lobs it over `blocker_f`), and sets the
-- receiver running onto it so passes are met instead of left to roll dead.
---@param s MatchState
---@param owner_idx integer
---@param target_idx integer
---@param blocker_f number?  -- lob over this lane fraction; nil = driven ground pass
local function release_pass(s, owner_idx, target_idx, blocker_f)
    local owner = s.players[owner_idx]
    local target = s.players[target_idx]
    target.receive_timer = RECEIVE_TIME
    s.events[#s.events + 1] = { kind = "pass", x = s.ball.x, y = s.ball.y, player = owner.id }
    s.owner = nil
    s.ball_z = 0
    s.ball_spin = 0
    s.pickup_cd = RELEASE_CD
    if blocker_f then
        s.ball_vel, s.ball_vz = lob_launch(owner.pos, target.pos, blocker_f, LOB_CLEAR_H)
    else
        local d = owner.pos:dist(target.pos)
        s.ball_vel = target.pos:sub(owner.pos):normalized():scale(pass_speed_for(d))
        s.ball_vz = 0
    end
end

---@param s MatchState
---@param owner_idx integer
---@param lofted boolean?  -- lob the pass over a defender on the lane
local function try_pass(s, owner_idx, lofted)
    local owner = s.players[owner_idx]
    -- Candidates are outfield teammates only: passing to the keeper's hands would
    -- break the back-pass rule, so the keeper is never a pass target.
    local cand, positions, opp_positions = {}, {}, {}
    for i, p in ipairs(s.players) do
        if p.team == owner.team and i ~= owner_idx and not p.is_keeper then
            cand[#cand + 1] = i
            positions[#positions + 1] = p.pos
        elseif p.team ~= owner.team then
            opp_positions[#opp_positions + 1] = p.pos
        end
    end
    -- Prefer a cone target whose driven ball can't be cut out mid-flight. A
    -- lofted pass sails over any would-be interceptor, so it skips the filter.
    local rel, pick_cand, pick_pos
    if not lofted then
        local threats = pass_threats(s, owner.team)
        local safe_cand, safe_pos = {}, {}
        for k, idx in ipairs(cand) do
            if not pass_risk(owner.pos, positions[k], threats) then
                safe_cand[#safe_cand + 1] = idx
                safe_pos[#safe_pos + 1] = positions[k]
            end
        end
        rel = passing.target(owner.pos, owner.facing, safe_pos)
        if rel then
            pick_cand, pick_pos = safe_cand, safe_pos
        end
    end
    if not rel then
        -- No safe cone target: take the plain cone pick, then the nearest
        -- teammate, so the button always does something (risk included).
        rel = passing.target(owner.pos, owner.facing, positions) or ai.closest(owner.pos, positions)
        if not rel then
            return
        end
        pick_cand, pick_pos = cand, positions
    end
    local target = pick_pos[rel]
    local f = lofted and (ai.lane_blocker(owner.pos, target, opp_positions, POSSESS_DIST) or 0.5)
        or nil
    release_pass(s, owner_idx, pick_cand[rel], f)
end

-- AI carrier under pressure: pick the most open, most progressive teammate with
-- a workable lane and play it to them (lobbed if the lane is blocked). Returns
-- true if a pass was released. Deterministic; ties resolve to the lowest index.
---@param s MatchState
---@param owner_idx integer
---@return boolean passed
local function ai_try_pass(s, owner_idx)
    local owner = s.players[owner_idx]
    local fwd = (owner.team == "home") and 1 or -1
    local opp_positions = {}
    for _, p in ipairs(s.players) do
        if p.team ~= owner.team then
            opp_positions[#opp_positions + 1] = p.pos
        end
    end
    local threats = pass_threats(s, owner.team)
    local best, best_score, best_f
    for i, p in ipairs(s.players) do
        if p.team == owner.team and i ~= owner_idx and not p.is_keeper then
            local d = owner.pos:dist(p.pos)
            local open = math.huge
            for _, qp in ipairs(opp_positions) do
                open = math.min(open, qp:dist(p.pos))
            end
            if d >= AI_PASS_MIN_DIST and d <= AI_PASS_MAX_DIST and open >= AI_PASS_MIN_OPEN then
                -- Openness, upfield progress, and a mild preference for short. A
                -- statically clear lane a chaser could still cut is penalized; a
                -- blocked lane gets lobbed anyway, so it carries no extra malus.
                local blocked = ai.lane_blocker(owner.pos, p.pos, opp_positions, POSSESS_DIST)
                local risk = not blocked and pass_risk(owner.pos, p.pos, threats) or nil
                local score = open
                    + (p.pos.x - owner.pos.x) * fwd * 0.6
                    - d * 0.25
                    - (risk and AI_PASS_RISK_PENALTY or 0)
                if not best_score or score > best_score then
                    -- Lob over a static blocker — or over the point where a
                    -- chaser would step onto a ground ball.
                    best_score, best, best_f = score, i, blocked or risk
                end
            end
        end
    end
    if not best then
        return false
    end
    release_pass(s, owner_idx, best, best_f)
    return true
end

---@param s MatchState
---@param team "home"|"away"
---@return Rect
local function attack_goal(s, team)
    return team == "home" and s.goal_away or s.goal_home
end

---@param s MatchState
---@param team "home"|"away"
---@return MatchPlayer?
local function team_keeper(s, team)
    for _, p in ipairs(s.players) do
        if p.team == team and p.is_keeper then
            return p
        end
    end
    return nil
end

-- World point in the opponent goal to aim at. `vbias` in [-1, 1] picks vertical
-- placement (0 = centre, +/-1 = the posts).
---@param s MatchState
---@param shooter MatchPlayer
---@param vbias number
---@return Vec2
local function shot_target(s, shooter, vbias)
    local g = attack_goal(s, shooter.team)
    local gx = (shooter.team == "home") and (g.x + g.w) or g.x
    local cy = g.y + g.h / 2
    local half = g.h / 2 - 8
    return Vec2.new(gx, cy + math.max(-1, math.min(1, vbias)) * half)
end

-- True when the ball is inside the keeper's claim zone (its penalty area):
-- close to its own goal line and within the mouth ± a margin. The keeper comes
-- off its line to gather loose balls here and to close down a carrier.
---@param s MatchState
---@param keeper MatchPlayer
---@return boolean
local function in_claim_zone(s, keeper)
    local g = (keeper.team == "home") and s.goal_home or s.goal_away
    local depth = (keeper.team == "home") and s.ball.x or (s.field.w - s.ball.x)
    return depth <= KEEPER_BOX_DEPTH
        and s.ball.y >= g.y - KEEPER_BOX_PAD
        and s.ball.y <= g.y + g.h + KEEPER_BOX_PAD
end

-- Where a keeper holds a gathered ball: at its hands, but clamped safely inside
-- the line so the hold itself can never read as a goal in check_goal (which
-- counts ball + radius).
---@param s MatchState
---@param keeper MatchPlayer
---@return Vec2
local function keeper_hold_pos(s, keeper)
    local hold_x = keeper.pos.x
    if keeper.team == "home" then
        hold_x = math.max(hold_x, s.goal_home.x + s.goal_home.w + BALL_RADIUS + 1)
    else
        hold_x = math.min(hold_x, s.goal_away.x - BALL_RADIUS - 1)
    end
    return Vec2.new(hold_x, keeper.pos.y)
end

-- Knock the ball loose when a challenger reaches THE BALL — not the carrier's
-- body. The ball sticks a step ahead of the carrier's feet, so a carrier who
-- turns their body between the challenger and the ball SHIELDS it: challenges
-- from behind come up short. The human challenges with a standing poke or a
-- slide (longer reach); an AI defender COMMITS to a poke as soon as the ball
-- looks reachable and pays its cooldown even on a whiff, so a carrier who keeps
-- moving makes defenders miss. A stunned defender can't tackle. The ball pops
-- toward the challenger so a clean tackle tends to win possession; a slide also
-- knocks the carrier down.
---@param s MatchState
local function attempt_steals(s)
    if not s.owner then
        return
    end
    local owner = s.players[s.owner]
    if owner.is_keeper then
        return -- a keeper has the ball in hand: it can't be tackled off them
    end
    if owner.dodge_timer > 0 then
        return -- juke i-frames: the carrier can't be tackled mid-dodge
    end
    if s.ball_z > GROUND_GRAB_HEIGHT then
        return -- ball is in the air, not at the carrier's feet (owned ball is grounded)
    end
    -- Keeper smother: a carrier who brings the ball into the keeper's box gets it
    -- picked straight off their feet (into the keeper's hands, not knocked loose).
    -- This is the 1v1 close-down; without it a carrier could walk the ball in.
    for i, p in ipairs(s.players) do
        if
            p.is_keeper
            and p.team ~= owner.team
            and p.stun_timer <= 0
            and in_claim_zone(s, p)
            and p.pos:dist(s.ball) <= KEEPER_SMOTHER
        then
            s.events[#s.events + 1] = { kind = "claim", x = s.ball.x, y = s.ball.y, player = p.id }
            s.owner = i
            s.ball_vel = Vec2.new(0, 0)
            s.ball_spin = 0
            p.grab_timer = KEEPER_GRAB_POSE
            p.hold_timer = KEEPER_HOLD
            return
        end
    end
    for i, p in ipairs(s.players) do
        if p.team ~= owner.team and not p.is_keeper and p.stun_timer <= 0 then
            local human = i == s.controlled
            local d = p.pos:dist(s.ball) -- reach for the ball: shielding matters
            local sliding = false
            local active, reach = false, STEAL_DIST
            if human then
                if p.slide_timer > 0 then
                    active, reach, sliding = true, SLIDE_REACH, true
                elseif p.tackle_timer > 0 then
                    active, reach = true, STAND_REACH
                end
            elseif p.dash_cd <= 0 and d <= STEAL_ATTEMPT then
                -- The AI pokes as soon as the ball looks reachable — and goes on
                -- cooldown whether or not it connects (a whiff is the carrier's
                -- window to escape).
                active = true
                p.dash_cd = AI_STEAL_CD
                p.tackle_timer = STAND_TIMER -- poke pose for the renderer
            end
            if active and d <= reach then
                local dir = p.pos:sub(owner.pos)
                if dir.x == 0 and dir.y == 0 then
                    dir = p.facing
                end
                s.events[#s.events + 1] =
                    { kind = "tackle", x = owner.pos.x, y = owner.pos.y, player = p.id }
                s.owner = nil
                s.ball_vel = dir:normalized():scale(TACKLE_POP_SPEED)
                s.pickup_cd = 0.12
                if sliding then
                    owner.stun_timer = math.max(owner.stun_timer, STUN_TIME) -- slide knocks them down
                end
                return
            end
        end
    end
end

-- Off-ball movement tuning (see docs/plan). All deterministic.
local PURSUE_LEAD = 0.004 -- prediction horizon per px of distance (s/px)
local MARK_GOALSIDE = 16 -- px a marker stands goal-side of its man
local COVER_FRAC = 0.3 -- cover sits this fraction from carrier toward own goal
local BLOCK_SHIFT = 0.45 -- how far the block slides toward the ball (× compactness)
local ATTACK_PUSH = 90 -- px an off-ball attacker pushes upfield (× support)
local SUPPORT_FAN = 70 -- candidate spread around an attacker's base
local SEP_RADIUS = 64 -- teammates within this repel each other
local SEP_PUSH = 16 -- px weight applied to the separation offset
local MARK_STICK = 20 -- hysteresis: keep a mark unless another is this much closer

---@param s MatchState
---@param team "home"|"away"
---@return Vec2
local function own_goal_center(s, team)
    local g = (team == "home") and s.goal_home or s.goal_away
    return Vec2.new(g.x + g.w / 2, g.y + g.h / 2)
end

-- Slide an anchor toward the ball without losing shape (block shift).
---@param anchor Vec2
---@param ball Vec2
---@param compactness number
---@return Vec2
local function block_shift(anchor, ball, compactness)
    return anchor:add(ball:sub(anchor):scale(BLOCK_SHIFT * compactness))
end

-- A marker stands just goal-side of its man, leading the man's motion.
---@param defpos Vec2
---@param opp_pos Vec2
---@param opp_vel Vec2
---@param goal Vec2
---@return Vec2
local function marker_target(defpos, opp_pos, opp_vel, goal)
    local aim = ai.pursue(defpos, opp_pos, opp_vel, PURSUE_LEAD)
    return aim:add(goal:sub(aim):normalized():scale(MARK_GOALSIDE))
end

-- Compute off-ball steering targets for every AI player NOT handled by the
-- controlled / owner / keeper branches. Pure function of the top-of-tick
-- snapshot `pos`. Returns player_index -> target Vec2, and refreshes s.marks for
-- man-marking hysteresis. Roles: one presser + one cover + scheme-driven rest
-- when defending; support-spot runs when attacking; press-set chase when loose.
---@param s MatchState
---@param pos Vec2[]
---@return table<integer, Vec2>
local function offball_targets(s, pos)
    local targets = {}
    local owner_team = s.owner and s.players[s.owner].team or nil

    for _, team in ipairs({ "home", "away" }) do
        local cfg = s.marking[team]
        local goal = own_goal_center(s, team)
        local atk = (team == "home") and 1 or -1

        -- This team's off-ball outfielders (exclude keeper, ball-owner, human).
        local mine = {}
        for i, p in ipairs(s.players) do
            if p.team == team and not p.is_keeper and i ~= s.owner and i ~= s.controlled then
                mine[#mine + 1] = i
            end
        end
        -- Opponents: all (for openness/lanes) and outfield-only (for marking).
        local opp_all_pos, opp_out, opp_out_pos = {}, {}, {}
        for i, p in ipairs(s.players) do
            if p.team ~= team then
                opp_all_pos[#opp_all_pos + 1] = pos[i]
                if not p.is_keeper then
                    opp_out[#opp_out + 1] = i
                    opp_out_pos[#opp_out_pos + 1] = pos[i]
                end
            end
        end

        -- Teammate positions for separation (spread out, don't stack).
        local function sep(idx, target)
            local others = {}
            for _, j in ipairs(mine) do
                if j ~= idx then
                    others[#others + 1] = pos[j]
                end
            end
            return target:add(ai.separation(target, others, SEP_RADIUS):scale(SEP_PUSH))
        end

        if owner_team and owner_team ~= team then
            -- DEFENDING: rank defenders by distance to the carrier.
            local carrier = s.players[s.owner]
            local cpos = pos[s.owner]
            local order = {}
            for _, idx in ipairs(mine) do
                order[#order + 1] = idx
            end
            table.sort(order, function(a, b)
                local da, db = pos[a]:dist(cpos), pos[b]:dist(cpos)
                if da ~= db then
                    return da < db
                end
                return a < b
            end)

            local presser, cover = order[1], order[2]
            if presser then
                local aim = ai.pursue(pos[presser], cpos, carrier.vel, PURSUE_LEAD)
                targets[presser] = aim:add(goal:sub(aim):normalized():scale(cfg.standoff))
            end
            if cover then
                targets[cover] = ai.interpose(cpos, goal, COVER_FRAC)
            end

            -- The rest: which defenders should man-mark, which hold zone.
            local rest = {}
            for k = 3, #order do
                rest[#rest + 1] = order[k]
            end

            -- Pick the opponents to be man-marked (player indices into opp_out).
            local mark_locals = {}
            if cfg.scheme == "man" then
                for li = 1, #opp_out do
                    mark_locals[#mark_locals + 1] = li
                end
            elseif cfg.scheme == "hybrid" then
                local rank = {}
                for li = 1, #opp_out do
                    rank[#rank + 1] = li
                end
                table.sort(rank, function(a, b)
                    local da, db = opp_out_pos[a]:dist(goal), opp_out_pos[b]:dist(goal)
                    if da ~= db then
                        return da < db -- closest to our goal = most dangerous
                    end
                    return opp_out[a] < opp_out[b]
                end)
                for n = 1, math.min(cfg.man_marks, #rank) do
                    mark_locals[#mark_locals + 1] = rank[n]
                end
            end

            local newmarks = {}
            if #mark_locals > 0 and #rest > 0 then
                local restpos, markpos = {}, {}
                for _, idx in ipairs(rest) do
                    restpos[#restpos + 1] = pos[idx]
                end
                for _, li in ipairs(mark_locals) do
                    markpos[#markpos + 1] = opp_out_pos[li]
                end
                -- Build prev assignment in local indices for hysteresis.
                local prev_local = {}
                for di, pidx in ipairs(rest) do
                    local prev_opp = s.marks[team][pidx]
                    if prev_opp then
                        for mi, li in ipairs(mark_locals) do
                            if opp_out[li] == prev_opp then
                                prev_local[di] = mi
                            end
                        end
                    end
                end
                local map = ai.assign_marks(restpos, markpos, prev_local, MARK_STICK)
                for di, mi in pairs(map) do
                    local def_idx = rest[di]
                    local opp_idx = opp_out[mark_locals[mi]]
                    newmarks[def_idx] = opp_idx
                    targets[def_idx] =
                        marker_target(pos[def_idx], pos[opp_idx], s.players[opp_idx].vel, goal)
                end
            end
            s.marks[team] = newmarks

            -- Any defender without a mark holds a ball-shifted zone.
            for _, idx in ipairs(rest) do
                if not targets[idx] then
                    targets[idx] = block_shift(s.players[idx].anchor, s.ball, cfg.compactness)
                end
            end
            for _, idx in ipairs(rest) do
                targets[idx] = sep(idx, targets[idx])
            end
        elseif owner_team == team then
            -- ATTACKING off the ball. When OUR KEEPER has it we're in build-up: hold
            -- stable, spread outlet positions (don't roam) so the keeper's throw
            -- reaches a teammate who's actually there. Otherwise make support runs.
            local build_up = s.players[s.owner].is_keeper
            local cpos = pos[s.owner]
            for _, idx in ipairs(mine) do
                if build_up then
                    targets[idx] = sep(idx, block_shift(s.players[idx].anchor, s.ball, 0.15))
                else
                    local a = s.players[idx].anchor
                    local base = Vec2.new(a.x + atk * ATTACK_PUSH * cfg.support, a.y)
                    local cands = {
                        base,
                        Vec2.new(base.x, base.y - SUPPORT_FAN),
                        Vec2.new(base.x, base.y + SUPPORT_FAN),
                        Vec2.new(base.x + atk * SUPPORT_FAN, base.y),
                        Vec2.new(base.x - atk * SUPPORT_FAN, base.y),
                    }
                    targets[idx] = sep(idx, ai.support_spot(cpos, cands, opp_all_pos, atk, s.field))
                end
            end
            s.marks[team] = {}
        else
            -- LOOSE ball: the press-set chases it with a pursuit lead, cutting
            -- off a rolling ball instead of trailing it. Passers already price
            -- this in: pass safety is interception-aware (ai.pass_intercept),
            -- not just a static lane check. Everyone else holds shape.
            local chasers = nearest_n(s, team, s.press[team])
            for _, idx in ipairs(mine) do
                if chasers[idx] then
                    targets[idx] = ai.pursue(pos[idx], s.ball, s.ball_vel, PURSUE_LEAD)
                else
                    targets[idx] = block_shift(s.players[idx].anchor, s.ball, cfg.compactness)
                end
            end
            s.marks[team] = {}
        end
    end

    -- A designated receiver runs onto the incoming ball (overrides its other role)
    -- so a keeper's distribution is actually met and gathered, not left in space.
    for i, p in ipairs(s.players) do
        if p.receive_timer > 0 and targets[i] then
            targets[i] = Vec2.new(s.ball.x, s.ball.y)
        end
    end

    -- Hard retreat: you can't challenge a keeper holding the ball, so the opposing
    -- team must give it space — push any target inside the respect ring back out.
    if s.owner and s.players[s.owner].is_keeper then
        local kpos = s.players[s.owner].pos
        local kteam = s.players[s.owner].team
        for i, tgt in pairs(targets) do
            if s.players[i].team ~= kteam then
                local off = tgt:sub(kpos)
                local d = off:length()
                if d < KEEPER_RESPECT_DIST then
                    local dir = (d > 0) and off:normalized() or Vec2.new(1, 0)
                    targets[i] = kpos:add(dir:scale(KEEPER_RESPECT_DIST))
                end
            end
        end
    end

    return targets
end

-- Resolve player-vs-player overlaps so bodies block instead of passing through.
-- Each pair pushed apart by its penetration; a sliding player barges through
-- (takes less of the push) and knocks the other off balance (stun). O(n^2)=45
-- pairs, deterministic.
---@param s MatchState
local function resolve_collisions(s)
    local pl = s.players
    for a = 1, #pl do
        for b = a + 1, #pl do
            local pa, pb = pl[a], pl[b]
            local delta = pa.pos:sub(pb.pos)
            local d = delta:length()
            local mind = pa.radius + pb.radius
            if d < mind then
                local dir = (d > 0) and delta:normalized() or Vec2.new(1, 0)
                local pen = mind - d
                local fa, fb = 0.5, 0.5 -- share the push evenly by default
                if pa.slide_timer > 0 and pb.slide_timer <= 0 then
                    fa, fb = 0.15, 0.85
                    if pb.stun_timer <= 0 then
                        pb.stun_timer = STUN_TIME
                    end
                elseif pb.slide_timer > 0 and pa.slide_timer <= 0 then
                    fa, fb = 0.85, 0.15
                    if pa.stun_timer <= 0 then
                        pa.stun_timer = STUN_TIME
                    end
                end
                pa.pos = clamp_to_field(s, pa.pos:add(dir:scale(pen * fa)))
                pb.pos = clamp_to_field(s, pb.pos:sub(dir:scale(pen * fb)))
            end
        end
    end
end

---@param s MatchState
local function move_players(s, dt, input)
    local owner = s.owner and s.players[s.owner] or nil

    -- Snapshot positions so role targets read one consistent world state and we
    -- can derive each player's realized velocity after everyone has moved. Vec2 is
    -- immutable, so aliasing p.pos here is safe.
    local prev = {}
    for i, p in ipairs(s.players) do
        prev[i] = p.pos
    end
    local targets = offball_targets(s, prev)

    for i, p in ipairs(s.players) do
        if i == s.controlled then
            -- Tackle button: a committed slide while SPRINTING, else a standing
            -- poke — one legible rule (sprint + tackle = the big slide). Slide
            -- speed scales off current velocity (p.vel) so it feels relative.
            if
                input.dash
                and p.slide_timer <= 0
                and p.tackle_timer <= 0
                and p.tackle_cd <= 0
                and p.stun_timer <= 0
            then
                local sp = p.vel:length()
                if p.sprinting then
                    local d = (input.move.x ~= 0 or input.move.y ~= 0) and input.move:normalized()
                        or p.facing
                    p.slide_timer = SLIDE_DURATION
                    p.slide_dir = d
                    p.slide_vel = math.max(SLIDE_BASE_MIN, sp * SLIDE_MULT)
                    p.facing = d
                    p.tackle_cd = SLIDE_CD
                else
                    p.tackle_timer = STAND_TIMER
                    p.tackle_cd = STAND_CD
                end
            end
            -- Trigger a juke (not while sliding): a quick sidestep with tackle immunity.
            if input.dodge and p.dodge_cd <= 0 and p.slide_timer <= 0 then
                local perp = Vec2.new(-p.facing.y, p.facing.x)
                if input.move.x * perp.x + input.move.y * perp.y < 0 then
                    perp = perp:scale(-1)
                end
                p.dodge_timer = DODGE_DURATION
                p.dodge_cd = DODGE_CD
                p.dodge_dir = perp
            end

            if p.slide_timer > 0 then
                -- Committed slide: locked direction, decaying speed, can't steer.
                p.pos = clamp_to_field(s, p.pos:add(p.slide_dir:scale(p.slide_vel * dt)))
                p.slide_vel = p.slide_vel * math.max(0, 1 - SLIDE_FRICTION * dt)
            elseif p.dodge_timer > 0 then
                -- Juke overrides steering: slide sideways fast.
                p.pos = clamp_to_field(
                    s,
                    p.pos:add(p.dodge_dir:scale(p.move_speed * DODGE_SPEED_MULT * dt))
                )
            else
                local dir = input.move
                local moving = dir.x ~= 0 or dir.y ~= 0
                -- Sprint: needs a quarter tank to (re)engage, but once running it
                -- burns to empty — so a drained meter doesn't flicker the boost
                -- on and off at the refill rate.
                local want = input.sprint and moving and p.stun_timer <= 0
                local can = p.sprint_meter > (p.sprinting and 0 or SPRINT_ENGAGE)
                p.sprinting = (want and can) or false
                if p.sprinting then
                    p.sprint_meter = math.max(0, p.sprint_meter - dt / p.sprint_dur)
                else
                    p.sprint_meter = math.min(1, p.sprint_meter + SPRINT_REFILL * dt)
                end
                if moving then
                    local nd = dir:normalized()
                    local mv = p.move_speed * (p.stun_timer > 0 and STUN_SLOW or 1)
                    if p.sprinting then
                        mv = mv * SPRINT_MULT
                    end
                    p.pos = clamp_to_field(s, p.pos:add(nd:scale(mv * dt)))
                    p.facing = nd
                end
            end
        elseif i == s.owner then
            -- AI owner dribbles toward the opponent goal.
            if not p.is_keeper then
                local goal = (p.team == "home") and s.goal_away or s.goal_home
                local gc = Vec2.new(goal.x + goal.w / 2, goal.y + goal.h / 2)
                local mv = p.move_speed * (p.stun_timer > 0 and STUN_SLOW or 1)
                local np, dir = ai.steer(p.pos, gc, mv * dt)
                p.pos = clamp_to_field(s, np)
                if dir.x ~= 0 or dir.y ~= 0 then
                    p.facing = dir
                end
            else
                -- A keeper holding the ball faces upfield; if an opponent is camped
                -- right in front of it, step laterally to open a throwing angle.
                p.facing = Vec2.new((p.team == "home") and 1 or -1, 0)
                local camper
                for _, q in ipairs(s.players) do
                    if q.team ~= p.team and q.pos:dist(p.pos) < KEEPER_RESPECT_DIST then
                        camper = q
                        break
                    end
                end
                if camper then
                    -- Sidestep away from the camper's side to open a throwing angle.
                    local side = (camper.pos.y >= p.pos.y) and -1 or 1
                    p.pos = clamp_to_field(s, p.pos:add(Vec2.new(0, side * p.move_speed * dt)))
                end
            end
        elseif p.is_keeper then
            local opp_owns = owner ~= nil and owner.team ~= p.team
            if p.dive_timer > 0 then
                -- Diving: lunge hard toward the ball to extend the save.
                p.pos = clamp_to_field(s, p.pos:add(p.dive_dir:scale(p.move_speed * 1.6 * dt)))
                p.facing = p.dive_dir
            elseif (s.owner == nil or opp_owns) and in_claim_zone(s, p) then
                -- Come off the line to claim a loose ball in the box — or to close
                -- down a carrier who brings it in (the 1v1 rush) — anticipating
                -- its path (pursuit) so the keeper meets it rather than trailing.
                local aim = ai.pursue(p.pos, s.ball, s.ball_vel, KEEPER_LEAD)
                local np, dir = ai.steer(p.pos, aim, p.move_speed * dt)
                p.pos = clamp_to_field(s, np)
                if dir.x ~= 0 or dir.y ~= 0 then
                    p.facing = dir
                end
            else
                -- Hold the goal line, tracking the ball but only across a centre band
                -- (KEEPER_GUARD) so well-placed corner shots stay scorable.
                local goal = (p.team == "home") and s.goal_home or s.goal_away
                local line_x = (p.team == "home") and (goal.x + goal.w + 12) or (goal.x - 12)
                local cy = goal.y + goal.h / 2
                local ty = math.max(cy - KEEPER_GUARD, math.min(cy + KEEPER_GUARD, s.ball.y))
                local np, dir = ai.steer(p.pos, Vec2.new(line_x, ty), p.move_speed * dt)
                p.pos = np
                if dir.x ~= 0 or dir.y ~= 0 then
                    p.facing = dir
                end
            end
        else
            -- Off-ball AI: role-assigned target (press/cover/mark/support/zone).
            local target = targets[i] or p.anchor
            local mv = p.move_speed * (p.stun_timer > 0 and STUN_SLOW or 1)
            local np, dir = ai.steer(p.pos, target, mv * dt)
            p.pos = clamp_to_field(s, np)
            if dir.x ~= 0 or dir.y ~= 0 then
                p.facing = dir
            end
        end
    end

    -- Push apart any overlapping bodies before deriving velocity, so a shove
    -- registers as motion and players never occupy the same point.
    resolve_collisions(s)

    -- Realized velocity (px/s) from this tick's movement; AI prediction source.
    if dt > 0 then
        for i, p in ipairs(s.players) do
            p.vel = p.pos:sub(prev[i]):scale(1 / dt)
        end
    end
end

-- Keeper distribution, in three tiers (all from the hands, deterministic,
-- ties by ascending index):
--   1. SAFE outlet (clear of opponents): a short throw — bowled along the ground
--      when the lane is clear, floated over the blocker when it isn't.
--   2. No safe outlet but someone is at least a step off their marker: a floated
--      throw that sails over the opponents to that most-open teammate.
--   3. Everyone swarmed: drop the ball and drop-kick it long upfield — a high
--      clearance over every head, not a flat drilled ball at the opponent goal.
---@param s MatchState
---@param keeper_idx integer
local function keeper_distribute(s, keeper_idx)
    local keeper = s.players[keeper_idx]
    local fwd = (keeper.team == "home") and 1 or -1 -- +x is upfield for home
    local opp = {}
    for _, q in ipairs(s.players) do
        if q.team ~= keeper.team then
            opp[#opp + 1] = q.pos
        end
    end

    local threats = pass_threats(s, keeper.team)
    local best, best_score, best_f
    local open_best, open_best_d
    for i, p in ipairs(s.players) do
        if p.team == keeper.team and not p.is_keeper then
            local opp_d = math.huge
            for _, qp in ipairs(opp) do
                opp_d = math.min(opp_d, qp:dist(p.pos))
            end
            if opp_d >= KEEPER_SAFE_DIST then
                -- A ground lane only counts as clear when nobody stands on it AND
                -- no chaser can cut the rolling ball out mid-flight; a cuttable
                -- lane is floated over the interception point instead.
                local f = ai.lane_blocker(keeper.pos, p.pos, opp, POSSESS_DIST)
                    or pass_risk(keeper.pos, p.pos, threats)
                -- Prefer a clear ground lane, then a short safe range, then openness
                -- and a little upfield progress. The clear-lane bonus dominates so a
                -- reliable ground pass always beats a risky lob.
                local score = (f and 0 or 1000)
                    - keeper.pos:dist(p.pos)
                    + opp_d * 0.5
                    + (p.pos.x - keeper.pos.x) * fwd * 0.2
                if not best_score or score > best_score then
                    best_score, best, best_f = score, i, f
                end
            end
            -- Tier-2 fallback candidate: the most-open teammate overall.
            if opp_d >= THROW_MIN_OPEN and (not open_best_d or opp_d > open_best_d) then
                open_best_d, open_best = opp_d, i
            end
        end
    end

    keeper.throw_timer = KEEPER_THROW_POSE -- release/throw pose (visual)
    if best then
        release_pass(s, keeper_idx, best, best_f)
    elseif open_best then
        -- Float it over the traffic to the least-marked teammate: the ball spends
        -- its flight above head height, so camped opponents can't pick it off.
        local f = ai.lane_blocker(keeper.pos, s.players[open_best].pos, opp, POSSESS_DIST) or 0.5
        release_pass(s, keeper_idx, open_best, f)
    else
        -- Everyone swarmed: drop-kick a high clearance upfield (lands around
        -- DROPKICK_DIST away, toward the middle of the pitch).
        local tx = math.max(40, math.min(s.field.w - 40, keeper.pos.x + fwd * DROPKICK_DIST))
        local target = Vec2.new(tx, s.field.h / 2)
        s.events[#s.events + 1] = { kind = "shot", x = s.ball.x, y = s.ball.y, player = keeper.id }
        s.owner = nil
        s.ball_z = 0
        s.ball_spin = 0
        s.pickup_cd = RELEASE_CD
        s.ball_vel, s.ball_vz = lob_launch(keeper.pos, target, 0.5, DROPKICK_CLEAR_H)
    end
end

-- The keeper of the threatened goal dives at an on-target shot: catches it
-- cleanly if it's comfortable, parries it loose if it's hard/wide, or is beaten.
-- Pure/deterministic; outcome is a function of reach, handling, pace and angle.
---@param s MatchState
---@return "catch"|"parry"|nil
local function attempt_save(s)
    local speed = s.ball_vel:length()
    if speed < 1 or s.ball_vel.x == 0 then
        return nil -- a dead or purely-vertical ball is not an on-target shot
    end
    for ki, keeper in ipairs(s.players) do
        if keeper.is_keeper and keeper.dive_timer <= 0 then
            local goal = (keeper.team == "home") and s.goal_home or s.goal_away
            local toward = (keeper.team == "home") and (s.ball_vel.x < 0) or (s.ball_vel.x > 0)
            -- Time for the ball to reach the keeper's line. Must be ahead of the ball
            -- (keeper between ball and goal) and close enough that the keeper commits.
            local t = (keeper.pos.x - s.ball.x) / s.ball_vel.x
            if toward and t >= 0 and math.abs(keeper.pos.x - s.ball.x) <= SAVE_ZONE then
                local y_cross = s.ball.y + s.ball_vel.y * t -- where it crosses the keeper's line
                local plane_x = (keeper.team == "home") and (goal.x + goal.w) or goal.x
                local tg = (plane_x - s.ball.x) / s.ball_vel.x
                local y_goal = s.ball.y + s.ball_vel.y * tg -- where it crosses the goal plane
                -- Height of the shot when it reaches the keeper's line. A ball over
                -- the keeper's aerial reach (a chip) sails past it; over the bar isn't
                -- a shot to save at all.
                local z_cross = s.ball_z + s.ball_vz * t - 0.5 * GRAVITY * t * t
                local on_target = y_goal >= goal.y - SAVE_PAD
                    and y_goal <= goal.y + goal.h + SAVE_PAD
                    and z_cross < CROSSBAR
                    and z_cross <= KEEPER_AIR_GRAB
                -- How far the keeper has to dive along its line to reach the shot.
                local dive_dist = math.abs(keeper.pos.y - y_cross)
                if on_target and dive_dist <= keeper.reach then
                    keeper.dive_timer = KEEPER_DIVE_DURATION
                    keeper.dive_dir = s.ball:sub(keeper.pos):normalized()
                    local hold_pos = keeper_hold_pos(s, keeper)

                    -- Closeness of the dive + handling, minus pace. A shot straight at
                    -- the keeper (dive_dist ~ 0) is gathered even when hard; only wide
                    -- or blistering shots drop to a parry or beat the keeper.
                    local quality = (1 - dive_dist / keeper.reach)
                        + keeper.handling * HANDLING_WEIGHT
                        - speed / SAVE_SPEED_REF

                    -- The save happens at the keeper's hands: snap the ball to the
                    -- keeper so a save in the sliver in front of the line can't still
                    -- register as a goal in check_goal (which counts ball + radius).
                    if quality >= CATCH_QUALITY then
                        s.events[#s.events + 1] =
                            { kind = "catch", x = s.ball.x, y = s.ball.y, player = keeper.id }
                        s.ball = hold_pos
                        s.owner = ki
                        s.ball_vel = Vec2.new(0, 0)
                        s.ball_spin = 0
                        keeper.grab_timer = KEEPER_GRAB_POSE
                        keeper.hold_timer = KEEPER_HOLD
                        return "catch"
                    end

                    if quality >= PARRY_QUALITY then
                        s.events[#s.events + 1] =
                            { kind = "parry", x = s.ball.x, y = s.ball.y, player = keeper.id }
                        s.ball = hold_pos
                        local gc = Vec2.new(goal.x + goal.w / 2, goal.y + goal.h / 2)
                        local dir = s.ball:sub(gc):normalized()
                        if dir.x == 0 and dir.y == 0 then
                            dir = keeper.facing
                        end
                        -- Punch it genuinely clear — out AND up, so the deflection
                        -- sails over the shooter rather than into their body.
                        s.ball_vel = dir:scale(math.max(MIN_PARRY_CLEAR, speed * PARRY_SPEED_MULT))
                        s.ball_vz = PARRY_POP_VZ
                        s.ball_spin = 0
                        s.pickup_cd = PARRY_CD
                        return "parry"
                    end
                    -- Beaten: the dive is committed but the ball gets through.
                    return nil
                end
            end
        end
    end
    return nil
end

---@param s MatchState
local function update_ball(s, dt, input)
    -- Only the controlled carrier accumulates charge; drop it otherwise.
    if not (s.owner and s.owner == s.controlled) then
        s.charge = 0
    end

    if s.owner then
        local owner = s.players[s.owner]
        -- A keeper holds the ball in its hands (at its body, clamped clear of its
        -- own line); outfielders dribble it ahead at their feet.
        if owner.is_keeper then
            s.ball = keeper_hold_pos(s, owner)
        else
            s.ball = owner.pos:add(owner.facing:scale(STICK_AHEAD))
        end
        s.ball_vel = Vec2.new(0, 0)
        s.ball_z = 0 -- an owned ball is grounded (at feet / in hands)
        s.ball_vz = 0

        if owner.is_keeper then
            -- Survey, then distribute to a safe outlet (build from the back) instead
            -- of hoofing it upfield every frame.
            if owner.hold_timer <= 0 then
                keeper_distribute(s, s.owner)
            end
        elseif s.owner == s.controlled then
            if input.shoot then
                -- Aim at the goal; vertical of `facing` picks the corner. Charge
                -- (held shoot) scales power; lateral input bends the shot.
                local vbias = math.max(-1, math.min(1, owner.facing.y * 1.4))
                local speed = owner.shot_speed * (1 + s.charge * CHARGE_POWER)
                local target = shot_target(s, owner, vbias)
                local vz = 0
                if input.lob then
                    -- Chip: same aim, but lofted so it crosses the line over the
                    -- keeper's reach yet under the bar. Pick vz from time-to-line.
                    local tline = math.max(0.05, owner.pos:dist(target) / speed)
                    vz = (CHIP_LINE_Z + 0.5 * GRAVITY * tline * tline) / tline
                end
                release_shot(s, owner, target:sub(owner.pos), speed, vz)
                local side = (input.move.x > 0 and 1) or (input.move.x < 0 and -1) or 0
                s.ball_spin = (vz == 0) and side * s.charge * CURVE_MAX or 0
                s.charge = 0
            elseif input.shoot_held then
                s.charge = math.min(1, s.charge + CHARGE_RATE * dt)
            elseif input.pass then
                try_pass(s, s.owner, input.lob)
            else
                s.charge = 0
            end
        else
            local g = attack_goal(s, owner.team)
            local gc = Vec2.new((owner.team == "home") and (g.x + g.w) or g.x, g.y + g.h / 2)
            if owner.pos:dist(gc) < AI_SHOOT_RANGE then
                -- Shoot to the corner away from the defending keeper, with power
                -- scaled by the space the striker has been given (see constants).
                local keeper = team_keeper(s, owner.team == "home" and "away" or "home")
                local vbias = 0.85
                if keeper then
                    vbias = (keeper.pos.y < gc.y) and 0.85 or -0.85
                end
                local space = math.huge
                for _, q in ipairs(s.players) do
                    if q.team ~= owner.team and not q.is_keeper then
                        space = math.min(space, q.pos:dist(owner.pos))
                    end
                end
                -- Closed down with no power available: look for the square ball
                -- to a better-placed teammate first; only shoot if nobody's on.
                local passed = false
                if space < AI_CHARGE_MIN_SPACE then
                    passed = ai_try_pass(s, s.owner)
                end
                if not passed then
                    local frac = math.max(
                        0,
                        math.min(1, (space - AI_CHARGE_MIN_SPACE) / AI_CHARGE_SPACE_RANGE)
                    )
                    local speed = owner.shot_speed * (1 + frac * CHARGE_POWER)
                    release_shot(s, owner, shot_target(s, owner, vbias):sub(owner.pos), speed)
                end
            else
                -- Out of range: pass out of pressure rather than dribble into a
                -- challenge. If nobody is open, keep carrying.
                local pressure = math.huge
                for _, q in ipairs(s.players) do
                    if q.team ~= owner.team and not q.is_keeper then
                        pressure = math.min(pressure, q.pos:dist(owner.pos))
                    end
                end
                if pressure <= AI_PASS_PRESSURE then
                    ai_try_pass(s, s.owner)
                end
            end
        end
        return
    end

    -- Loose ball: integrate, decay, curve, bounce off touchlines/back walls.
    s.ball = s.ball:add(s.ball_vel:scale(dt))
    -- Full grass friction only near the ground; a lofted ball glides (light drag).
    local airborne = s.ball_z > GROUND_GRAB_HEIGHT
    local hfric = airborne and AIR_FRICTION or FRICTION
    s.ball_vel = s.ball_vel:scale(math.max(0, 1 - hfric * dt))
    -- Spin only bends a ball rolling on the grass.
    if not airborne and s.ball_spin ~= 0 and s.ball_vel:length() > 1 then
        local v = s.ball_vel
        local perp = Vec2.new(-v.y, v.x):normalized()
        s.ball_vel = s.ball_vel:add(perp:scale(s.ball_spin * dt))
        s.ball_spin = s.ball_spin * math.max(0, 1 - SPIN_DECAY * dt)
    end

    -- Vertical: integrate under gravity, land and rebound (keeping horizontal pace).
    s.ball_z = s.ball_z + s.ball_vz * dt
    s.ball_vz = s.ball_vz - GRAVITY * dt
    if s.ball_z <= 0 then
        s.ball_z = 0
        if s.ball_vz < 0 then
            if -s.ball_vz <= LAND_SETTLE_VZ then
                s.ball_vz = 0 -- settle: stop micro-bouncing
            else
                s.ball_vz = -s.ball_vz * BOUNCE -- rebound up; ball_vel unchanged
            end
        end
    end

    if s.ball.y < BALL_RADIUS then
        s.ball.y = BALL_RADIUS
        s.ball_vel.y = -s.ball_vel.y
    elseif s.ball.y > s.field.h - BALL_RADIUS then
        s.ball.y = s.field.h - BALL_RADIUS
        s.ball_vel.y = -s.ball_vel.y
    end
    if s.ball.x < BALL_RADIUS and not in_mouth(s.ball, s.goal_home) then
        s.ball.x = BALL_RADIUS
        s.ball_vel.x = -s.ball_vel.x
    elseif s.ball.x > s.field.w - BALL_RADIUS and not in_mouth(s.ball, s.goal_away) then
        s.ball.x = s.field.w - BALL_RADIUS
        s.ball_vel.x = -s.ball_vel.x
    end

    -- Body blocking: a fast, low ball that runs into an outfield body ricochets
    -- off it. Only a ball moving TOWARD the body blocks, so a shooter never
    -- blocks their own release. Keepers are excluded — they interact with the
    -- ball through saves and claims, never as a passive wall.
    do
        local speed = s.ball_vel:length()
        if speed >= POSSESS_MAX_SPEED and s.ball_z <= BLOCK_HEIGHT then
            for _, p in ipairs(s.players) do
                if not p.is_keeper then
                    local off = s.ball:sub(p.pos)
                    local d = off:length()
                    local contact = p.radius + BALL_RADIUS
                    if d < contact then
                        local n = (d > 0) and off:normalized() or Vec2.new(1, 0)
                        local vn = s.ball_vel.x * n.x + s.ball_vel.y * n.y
                        if vn < 0 then
                            s.events[#s.events + 1] =
                                { kind = "block", x = s.ball.x, y = s.ball.y, player = p.id }
                            -- Reflect off the body normal, damped, and push the
                            -- ball clear so it can't re-block next frame.
                            s.ball_vel = s.ball_vel:sub(n:scale(2 * vn)):scale(BLOCK_DAMP)
                            s.ball = p.pos:add(n:scale(contact))
                            s.ball_spin = 0
                            break
                        end
                    end
                end
            end
        end
    end

    -- Keeper dive: contest an on-target shot before anyone can generically collect.
    -- NOT gated on pickup_cd: that cooldown is the SHOOTER's re-collection lockout,
    -- and a close-range shot reaches the line well inside it — the keeper must
    -- still be allowed to react. A clean catch ends the frame here; a parry sets
    -- pickup_cd so the deflection isn't re-grabbed instantly (the parried ball
    -- travels away from goal, so it can't trigger an immediate re-save); being
    -- beaten falls through to a possible goal.
    if attempt_save(s) == "catch" then
        return
    end

    -- Collection. A keeper has PRIORITY in its own box: it claims any loose ball it
    -- can reach there (with its hands), beating outfielders even if they are a touch
    -- closer. Otherwise the nearest eligible player grabs it.
    if s.pickup_cd == 0 then
        local speed = s.ball_vel:length()
        local best, best_dist

        for i, p in ipairs(s.players) do
            if
                p.is_keeper
                and in_claim_zone(s, p)
                and s.ball_z <= KEEPER_AIR_GRAB
                and p.pos:dist(s.ball) <= KEEPER_CLAIM_DIST
            then
                best = i
                break
            end
        end

        if not best then
            for i, p in ipairs(s.players) do
                local reach = p.is_keeper and KEEPER_DIST or POSSESS_DIST
                -- A ball above head height flies over everyone — not collectable.
                local eligible = (p.is_keeper or speed < POSSESS_MAX_SPEED)
                    and s.ball_z <= GROUND_GRAB_HEIGHT
                local d = p.pos:dist(s.ball)
                if eligible and d <= reach and (not best_dist or d < best_dist) then
                    best_dist = d
                    best = i
                end
            end
        end

        if best then
            local bp = s.players[best]
            if bp.is_keeper then
                -- A keeper gather: claim event + gather pose, then it surveys/holds.
                -- Snap the ball into its hands so a claim right on the line can't
                -- still register as a goal this frame.
                s.events[#s.events + 1] =
                    { kind = "claim", x = s.ball.x, y = s.ball.y, player = bp.id }
                s.ball = keeper_hold_pos(s, bp)
                bp.grab_timer = KEEPER_GRAB_POSE
                bp.hold_timer = KEEPER_HOLD
            elseif speed > 1 then
                -- A moving ball trapped by an outfielder reads as a "touch".
                s.events[#s.events + 1] =
                    { kind = "touch", x = s.ball.x, y = s.ball.y, player = bp.id }
            end
            s.owner = best
            s.ball_vel = Vec2.new(0, 0)
            s.ball_spin = 0
            -- Auto-switch: the human takes over whichever home outfielder wins the
            -- ball (like FIFA / Mario Strikers). Keepers stay AI.
            if bp.team == "home" and not bp.is_keeper then
                s.controlled = best
            end
        end
    end
end

---@param s MatchState
---@return "home"|"away"? scorer
local function check_goal(s)
    if s.ball_z >= CROSSBAR then
        return nil -- over the bar
    end
    if s.ball.x + BALL_RADIUS >= s.goal_away.x and in_mouth(s.ball, s.goal_away) then
        s.score.home = s.score.home + 1
        return "home"
    elseif
        s.ball.x - BALL_RADIUS <= s.goal_home.x + s.goal_home.w and in_mouth(s.ball, s.goal_home)
    then
        s.score.away = s.score.away + 1
        return "away"
    end
    return nil
end

---@param s MatchState
---@param dt number
---@param input MatchInput
---@return MatchState
function match.step(s, dt, input)
    if s.finished then
        return s
    end

    -- Discrete events are per-frame: clear last frame's before producing this one's.
    for i = #s.events, 1, -1 do
        s.events[i] = nil
    end

    s.time_left = s.time_left - dt
    if s.time_left <= 0 then
        s.time_left = 0
        s.finished = true
        return s
    end

    if s.pickup_cd > 0 then
        s.pickup_cd = math.max(0, s.pickup_cd - dt)
    end
    for _, p in ipairs(s.players) do
        if p.dash_cd > 0 then
            p.dash_cd = math.max(0, p.dash_cd - dt)
        end
        if p.dodge_cd > 0 then
            p.dodge_cd = math.max(0, p.dodge_cd - dt)
        end
        if p.dodge_timer > 0 then
            p.dodge_timer = math.max(0, p.dodge_timer - dt)
        end
        if p.dive_timer > 0 then
            p.dive_timer = math.max(0, p.dive_timer - dt)
        end
        if p.hold_timer > 0 then
            p.hold_timer = math.max(0, p.hold_timer - dt)
        end
        if p.slide_timer > 0 then
            p.slide_timer = math.max(0, p.slide_timer - dt)
        end
        if p.tackle_timer > 0 then
            p.tackle_timer = math.max(0, p.tackle_timer - dt)
        end
        if p.tackle_cd > 0 then
            p.tackle_cd = math.max(0, p.tackle_cd - dt)
        end
        if p.stun_timer > 0 then
            p.stun_timer = math.max(0, p.stun_timer - dt)
        end
        if p.grab_timer > 0 then
            p.grab_timer = math.max(0, p.grab_timer - dt)
        end
        if p.throw_timer > 0 then
            p.throw_timer = math.max(0, p.throw_timer - dt)
        end
        if p.receive_timer > 0 then
            p.receive_timer = math.max(0, p.receive_timer - dt)
        end
    end

    if input.switch then
        s.controlled = next_home_outfield(s, s.controlled)
    end

    move_players(s, dt, input)
    attempt_steals(s)
    update_ball(s, dt, input)

    local scorer = check_goal(s)
    if scorer then
        if s.score.home >= s.max_goals or s.score.away >= s.max_goals then
            s.finished = true
        else
            -- The team that conceded restarts play.
            place_kickoff(s, scorer == "home" and "away" or "home")
        end
    end

    return s
end

-- Test seam: expose the pure off-ball target computation for assertions.
match._offball_targets = offball_targets
match._resolve_collisions = resolve_collisions

return match
