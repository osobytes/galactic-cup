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
local player_pool = require("data.players")

local PLAYER_RADIUS = 12
local BALL_RADIUS = 6
local FRICTION = 1.2 -- fraction of ball speed shed per second
local STICK_AHEAD = PLAYER_RADIUS + BALL_RADIUS -- dribble offset
local POSSESS_DIST = 22 -- outfield control radius
local KEEPER_DIST = 28 -- keepers reach a bit further
local POSSESS_MAX_SPEED = 350 -- outfield can only collect a slow-enough ball
local PASS_SPEED = 320
local AI_SHOOT_RANGE = 230 -- AI owner shoots when this close to goal
local GOAL_MOUTH = 110
local RELEASE_CD = 0.3 -- pickup lockout after a shot/pass (seconds)

---@class MatchPlayer
---@field id string
---@field name string
---@field team "home"|"away"
---@field pos Vec2
---@field facing Vec2
---@field anchor Vec2
---@field move_speed number
---@field shot_speed number
---@field is_keeper boolean
---@field radius number

---@alias Rect { x: number, y: number, w: number, h: number }

---@class MatchInput
---@field move Vec2  -- controlled player's desired direction
---@field shoot boolean
---@field pass boolean
---@field switch boolean  -- cycle the controlled player

---@class MatchState
---@field field { w: number, h: number }
---@field goal_home Rect  -- left goal; away scores here
---@field goal_away Rect  -- right goal; home scores here
---@field players MatchPlayer[]  -- home indices 1..5, away 6..10
---@field ball Vec2
---@field ball_vel Vec2
---@field owner integer?  -- index into players, nil if loose
---@field controlled integer  -- index of the human-controlled home player
---@field score { home: integer, away: integer }
---@field time_left number
---@field max_goals integer
---@field finished boolean
---@field pickup_cd number

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
---@return MatchPlayer[]
local function build_team(team, side, field, by_id)
    local formation = formations[team.formation]
    assert(formation, "unknown formation: " .. tostring(team.formation))
    local anchors = placement.anchors(formation, side, field)

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
        local anchor = anchors[i]
        list[i] = {
            id = id,
            name = pd.name,
            team = side,
            pos = Vec2.new(anchor.x, anchor.y),
            facing = Vec2.new(side == "home" and 1 or -1, 0),
            anchor = anchor,
            move_speed = stats.move_speed(pd.stats),
            shot_speed = stats.shot_speed(pd.stats),
            is_keeper = pd.position == "keeper",
            radius = PLAYER_RADIUS,
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

---@param s MatchState
local function place_kickoff(s)
    for _, p in ipairs(s.players) do
        p.pos = Vec2.new(p.anchor.x, p.anchor.y)
        p.facing = Vec2.new(p.team == "home" and 1 or -1, 0)
    end
    -- Give the controlled player the ball at the centre spot.
    local c = s.players[s.controlled]
    c.pos = Vec2.new(s.field.w * 0.45, s.field.h / 2)
    s.ball = c.pos:add(c.facing:scale(STICK_AHEAD))
    s.ball_vel = Vec2.new(0, 0)
    s.owner = s.controlled
    s.pickup_cd = 0
end

---@param opts { home: TeamData, away: TeamData, field: { w: number, h: number }, duration: number?, max_goals: integer?, players_by_id: table<string, PlayerData>? }
---@return MatchState
function match.new(opts)
    local field = opts.field
    local by_id = opts.players_by_id or pool_by_id()

    local home = build_team(opts.home, "home", field, by_id)
    local away = build_team(opts.away, "away", field, by_id)
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
        owner = nil,
        controlled = most_advanced_home(players),
        score = { home = 0, away = 0 },
        time_left = opts.duration or 120,
        max_goals = opts.max_goals or 3,
        finished = false,
        pickup_cd = 0,
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

-- Index of the closest non-keeper of `team` to the ball.
---@param s MatchState
---@param team "home"|"away"
---@return integer?
local function team_chaser(s, team)
    local positions, indices = {}, {}
    for i, p in ipairs(s.players) do
        if p.team == team and not p.is_keeper then
            positions[#positions + 1] = p.pos
            indices[#indices + 1] = i
        end
    end
    local rel = ai.closest(s.ball, positions)
    return rel and indices[rel] or nil
end

---@param s MatchState
---@param cur integer
---@return integer
local function next_home_outfield(s, cur)
    local order = {}
    for i, p in ipairs(s.players) do
        if p.team == "home" and not p.is_keeper then
            order[#order + 1] = i
        end
    end
    for k, idx in ipairs(order) do
        if idx == cur then
            return order[(k % #order) + 1]
        end
    end
    return order[1] or cur
end

---@param s MatchState
---@param owner MatchPlayer
---@param dir Vec2
local function release_shot(s, owner, dir)
    s.owner = nil
    s.ball_vel = dir:normalized():scale(owner.shot_speed)
    s.pickup_cd = RELEASE_CD
end

---@param s MatchState
---@param owner_idx integer
local function try_pass(s, owner_idx)
    local owner = s.players[owner_idx]
    local positions, indices = {}, {}
    for i, p in ipairs(s.players) do
        if p.team == owner.team and i ~= owner_idx then
            positions[#positions + 1] = p.pos
            indices[#indices + 1] = i
        end
    end
    local rel = passing.target(owner.pos, owner.facing, positions)
    if not rel then
        return
    end
    local dir = positions[rel]:sub(owner.pos):normalized()
    s.owner = nil
    s.ball_vel = dir:scale(PASS_SPEED)
    s.pickup_cd = RELEASE_CD
end

---@param s MatchState
local function move_players(s, dt, input)
    local home_chaser = team_chaser(s, "home")
    local away_chaser = team_chaser(s, "away")
    local owner = s.owner and s.players[s.owner] or nil

    for i, p in ipairs(s.players) do
        if i == s.controlled then
            if input.move.x ~= 0 or input.move.y ~= 0 then
                local dir = input.move:normalized()
                p.pos = clamp_to_field(s, p.pos:add(dir:scale(p.move_speed * dt)))
                p.facing = dir
            end
        elseif i == s.owner then
            -- AI owner dribbles toward the opponent goal.
            local goal = (p.team == "home") and s.goal_away or s.goal_home
            local gc = Vec2.new(goal.x + goal.w / 2, goal.y + goal.h / 2)
            local np, dir = ai.steer(p.pos, gc, p.move_speed * dt)
            p.pos = clamp_to_field(s, np)
            if dir.x ~= 0 or dir.y ~= 0 then
                p.facing = dir
            end
        elseif p.is_keeper then
            -- Hold the goal line, track the ball's height within the mouth.
            local goal = (p.team == "home") and s.goal_home or s.goal_away
            local line_x = (p.team == "home") and (goal.x + goal.w + 12) or (goal.x - 12)
            local ty = math.max(goal.y, math.min(goal.y + goal.h, s.ball.y))
            local np, dir = ai.steer(p.pos, Vec2.new(line_x, ty), p.move_speed * dt)
            p.pos = np
            if dir.x ~= 0 or dir.y ~= 0 then
                p.facing = dir
            end
        else
            local opponent_owned = owner and owner.team ~= p.team
            local chase = (i == home_chaser or i == away_chaser)
                and (s.owner == nil or opponent_owned)
            local target = chase and s.ball or p.anchor
            local np, dir = ai.steer(p.pos, target, p.move_speed * dt)
            p.pos = clamp_to_field(s, np)
            if dir.x ~= 0 or dir.y ~= 0 then
                p.facing = dir
            end
        end
    end
end

---@param s MatchState
local function update_ball(s, dt, input)
    if s.owner then
        local owner = s.players[s.owner]
        s.ball = owner.pos:add(owner.facing:scale(STICK_AHEAD))
        s.ball_vel = Vec2.new(0, 0)

        if s.owner == s.controlled then
            if input.shoot then
                release_shot(s, owner, owner.facing)
            elseif input.pass then
                try_pass(s, s.owner)
            end
        else
            local goal = (owner.team == "home") and s.goal_away or s.goal_home
            local gc = Vec2.new(goal.x + goal.w / 2, goal.y + goal.h / 2)
            if owner.pos:dist(gc) < AI_SHOOT_RANGE then
                release_shot(s, owner, gc:sub(owner.pos))
            end
        end
        return
    end

    -- Loose ball: integrate, decay, bounce off touchlines/back walls.
    s.ball = s.ball:add(s.ball_vel:scale(dt))
    s.ball_vel = s.ball_vel:scale(math.max(0, 1 - FRICTION * dt))

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

    -- Collection: nearest eligible player grabs it (keepers ignore the speed cap).
    if s.pickup_cd == 0 then
        local best, best_dist
        local speed = s.ball_vel:length()
        for i, p in ipairs(s.players) do
            local reach = p.is_keeper and KEEPER_DIST or POSSESS_DIST
            local eligible = p.is_keeper or speed < POSSESS_MAX_SPEED
            local d = p.pos:dist(s.ball)
            if eligible and d <= reach and (not best_dist or d < best_dist) then
                best_dist = d
                best = i
            end
        end
        if best then
            s.owner = best
            s.ball_vel = Vec2.new(0, 0)
        end
    end
end

---@param s MatchState
---@return boolean scored
local function check_goal(s)
    if s.ball.x + BALL_RADIUS >= s.goal_away.x and in_mouth(s.ball, s.goal_away) then
        s.score.home = s.score.home + 1
        return true
    elseif
        s.ball.x - BALL_RADIUS <= s.goal_home.x + s.goal_home.w and in_mouth(s.ball, s.goal_home)
    then
        s.score.away = s.score.away + 1
        return true
    end
    return false
end

---@param s MatchState
---@param dt number
---@param input MatchInput
---@return MatchState
function match.step(s, dt, input)
    if s.finished then
        return s
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

    if input.switch then
        s.controlled = next_home_outfield(s, s.controlled)
    end

    move_players(s, dt, input)
    update_ball(s, dt, input)

    if check_goal(s) then
        if s.score.home >= s.max_goals or s.score.away >= s.max_goals then
            s.finished = true
        else
            place_kickoff(s)
        end
    end

    return s
end

return match
