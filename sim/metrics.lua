-- Fun-proxy metrics: fold a running match into the per-match numbers that
-- docs/design/fun_metrics.md bands and scores. Pure observer — reads
-- MatchState after each step, never mutates it. The collector is driven by
-- the headless runner (sim/headless.lua) but works against any stepped match.

local TUNE = require("sim.tuning").values

local metrics = {}

---@param s MatchState
---@param player_index integer
---@return "controlled"|"ai"
local function dribble_role_for_index(s, player_index)
    if s.slot_mode then
        local slot_index = s.slot_for_player[player_index]
        local sources = s.slot_input_state and s.slot_input_state.sources or nil
        return slot_index and sources and sources[slot_index].kind == "frame" and "controlled"
            or "ai"
    end
    return s.human_controlled and player_index == s.controlled and "controlled" or "ai"
end

-- Seconds a team must hold the ball before its possession is "settled" —
-- the unit turnovers are counted in (see observe).
metrics.SETTLE_HOLD = 0.7

---@class DribbleMetricCollector
---@field carry_s number
---@field close_s number
---@field sprint_s number
---@field juke_s number
---@field touches integer
---@field heavy_losses integer
---@field jukes integer

---@class MetricsCollector
---@field t number  -- seconds observed so far
---@field goals { t: number, team: "home"|"away" }[]
---@field prev_home integer
---@field prev_away integer
---@field shots integer  -- outfield strikes at goal (shot/header/volley/bicycle)
---@field saves integer  -- keeper catches + parries
---@field passes integer
---@field passes_completed integer
---@field pending_pass "home"|"away"|nil  -- pass in flight, resolved at next ownership
---@field turnovers integer
---@field settled_team "home"|"away"|nil  -- last team with SETTLED possession
---@field hold_team "home"|"away"|nil  -- team of the current ownership streak
---@field hold_t number  -- seconds the streak team has held the ball
---@field own_time { home: number, away: number }
---@field last_chance_t number  -- last shot or goal, for drought tracking
---@field longest_drought number
---@field team_of table<string, "home"|"away">  -- player id -> team
---@field keeper table<string, boolean>  -- player id -> is_keeper
---@field index_of table<string, integer>  -- player id -> MatchState index
---@field prev_owner_id string?
---@field prev_owner_role "controlled"|"ai"|nil
---@field dribble { controlled: DribbleMetricCollector, ai: DribbleMetricCollector }

-- Per-match results. Rate metrics are nil when their denominator never
-- happened (e.g. save_rate with zero on-target shots) and are skipped by the
-- fun score rather than defaulted.
---@class MatchMetrics
---@field duration number
---@field goals_home integer
---@field goals_away integer
---@field goals_total integer
---@field margin integer
---@field lead_changes integer
---@field decided_late number  -- when the winner was settled, as a fraction of the match (draw = 1)
---@field shots integer
---@field shots_per_goal number?
---@field save_rate number?
---@field passes integer
---@field pass_completion number?
---@field turnovers_per_min number
---@field possession_balance number?  -- home share of owned time
---@field longest_drought_s number
---@field controlled_dribble_carry_s number
---@field controlled_dribble_close_share number?
---@field controlled_dribble_sprint_share number?
---@field controlled_dribble_juke_share number?
---@field controlled_dribble_touches_per_min number
---@field controlled_dribble_heavy_losses_per_min number
---@field controlled_jukes integer
---@field ai_dribble_carry_s number
---@field ai_dribble_close_share number?
---@field ai_dribble_sprint_share number?
---@field ai_dribble_juke_share number?
---@field ai_dribble_touches_per_min number
---@field ai_dribble_heavy_losses_per_min number
---@field ai_jukes integer
---@field fun number?  -- composite score, stamped on by the headless runner

-- Trapezoid desirability bands {zero_lo, good_lo, good_hi, zero_hi}: worth 1
-- inside [good_lo, good_hi], falling linearly to 0 at the outer edges.
-- Provisional targets — see docs/design/fun_metrics.md for the rationale.
---@type table<string, { [1]: number, [2]: number, [3]: number, [4]: number }>
metrics.bands = {
    goals_total = { 0, 2, 5, 8 },
    -- zero_hi sits at "catastrophic", not "bad": search needs gradient out here
    -- (the baseline lives around 18 — see the doc's baseline signature).
    shots_per_goal = { 1, 2.5, 6, 25 },
    save_rate = { 0.15, 0.45, 0.75, 0.95 },
    pass_completion = { 0.25, 0.55, 0.85, 1.001 },
    -- SETTLED possession changes (see SETTLE_HOLD) — raw ownership flicker
    -- runs ~40x higher and means nothing.
    turnovers_per_min = { 0.3, 1, 5, 10 },
    possession_balance = { 0.1, 0.35, 0.65, 0.9 },
    longest_drought_s = { -1, 0, 35, 80 },
    decided_late = { 0.05, 0.4, 1, math.huge },
}

---@param s MatchState
---@return MetricsCollector
function metrics.new(s)
    local team_of, keeper, index_of = {}, {}, {}
    for i, p in ipairs(s.players) do
        team_of[p.id] = p.team
        keeper[p.id] = p.is_keeper or false
        index_of[p.id] = i
    end
    local prev_owner = s.owner and s.players[s.owner] or nil
    local prev_role = nil
    if prev_owner and not prev_owner.is_keeper then
        prev_role = dribble_role_for_index(s, s.owner)
    end
    local function dribble_bucket()
        return {
            carry_s = 0,
            close_s = 0,
            sprint_s = 0,
            juke_s = 0,
            touches = 0,
            heavy_losses = 0,
            jukes = 0,
        }
    end
    return {
        t = 0,
        goals = {},
        prev_home = s.score.home,
        prev_away = s.score.away,
        shots = 0,
        saves = 0,
        passes = 0,
        passes_completed = 0,
        pending_pass = nil,
        turnovers = 0,
        settled_team = nil,
        hold_team = nil,
        hold_t = 0,
        own_time = { home = 0, away = 0 },
        last_chance_t = 0,
        longest_drought = 0,
        team_of = team_of,
        keeper = keeper,
        index_of = index_of,
        prev_owner_id = prev_owner and prev_owner.id or nil,
        prev_owner_role = prev_role,
        dribble = { controlled = dribble_bucket(), ai = dribble_bucket() },
    }
end

---@param s MatchState
---@param player_id string
---@return "controlled"|"ai"
local function dribble_role(s, player_id)
    local index = nil
    for i, p in ipairs(s.players) do
        if p.id == player_id then
            index = i
            break
        end
    end
    return index and dribble_role_for_index(s, index) or "ai"
end

-- Observe one frame, AFTER match.step(s, dt, ...) for the same dt (so
-- s.events holds exactly this frame's actions).
---@param c MetricsCollector
---@param s MatchState
---@param dt number
function metrics.observe(c, s, dt)
    c.t = c.t + dt

    for _, e in ipairs(s.events) do
        local team = e.player and c.team_of[e.player] or nil
        local is_keeper = e.player ~= nil and c.keeper[e.player]
        if e.kind == "pass" then
            c.passes = c.passes + 1
            c.pending_pass = team
        elseif e.kind == "catch" or e.kind == "parry" then
            c.saves = c.saves + 1
        elseif
            (e.kind == "shot" or e.kind == "header" or e.kind == "volley" or e.kind == "bicycle")
            and not is_keeper
        then
            -- Keeper "shot" events are punts/clearances, not strikes at goal.
            c.shots = c.shots + 1
            c.longest_drought = math.max(c.longest_drought, c.t - c.last_chance_t)
            c.last_chance_t = c.t
        elseif e.kind == "touch" and e.player and c.prev_owner_id == e.player then
            local role = c.prev_owner_role or "ai"
            local bucket = c.dribble[role]
            local owner = s.owner and s.players[s.owner] or nil
            if owner and owner.id == e.player then
                bucket.touches = bucket.touches + 1
            elseif not owner then
                bucket.heavy_losses = bucket.heavy_losses + 1
            end
        elseif e.kind == "juke" and e.player then
            local role = dribble_role(s, e.player)
            c.dribble[role].jukes = c.dribble[role].jukes + 1
        end
    end

    if s.score.home > c.prev_home or s.score.away > c.prev_away then
        local team = s.score.home > c.prev_home and "home" or "away"
        c.goals[#c.goals + 1] = { t = c.t, team = team }
        c.prev_home, c.prev_away = s.score.home, s.score.away
        c.longest_drought = math.max(c.longest_drought, c.t - c.last_chance_t)
        c.last_chance_t = c.t
        c.pending_pass = nil -- a goal ends any pass in flight
    end

    local owner_team = s.owner and s.players[s.owner].team or nil
    if owner_team then
        c.own_time[owner_team] = c.own_time[owner_team] + dt
        if c.pending_pass then
            if owner_team == c.pending_pass then
                c.passes_completed = c.passes_completed + 1
            end
            c.pending_pass = nil
        end
        -- A turnover is settled possession changing team, not ownership
        -- flicker: in a poke-and-scramble the ball changes hands every few
        -- frames, and counting each touch reads as ping-pong chaos. The new
        -- team must hold the ball SETTLE_HOLD seconds (pass flights bridge:
        -- loose frames pause the streak, only the other team's touch resets).
        if owner_team ~= c.hold_team then
            c.hold_team = owner_team
            c.hold_t = 0
        end
        c.hold_t = c.hold_t + dt
        if c.hold_t >= metrics.SETTLE_HOLD and c.settled_team ~= owner_team then
            if c.settled_team then
                c.turnovers = c.turnovers + 1
            end
            c.settled_team = owner_team
        end
    end

    if s.owner then
        local owner = s.players[s.owner]
        if not owner.is_keeper then
            local role = dribble_role_for_index(s, s.owner)
            local bucket = c.dribble[role]
            bucket.carry_s = bucket.carry_s + dt
            if owner.vel:length() < owner.move_speed * TUNE.DRIBBLE_CLOSE then
                bucket.close_s = bucket.close_s + dt
            end
            if owner.sprinting then
                bucket.sprint_s = bucket.sprint_s + dt
            end
            if owner.dodge_timer > 0 then
                bucket.juke_s = bucket.juke_s + dt
            end
            c.prev_owner_role = role
        else
            c.prev_owner_role = nil
        end
        c.prev_owner_id = owner.id
    else
        c.prev_owner_id = nil
        c.prev_owner_role = nil
    end
end

-- The moment the final winner took a lead they never lost (draw: the full
-- match — tension never resolved).
---@param goals { t: number, team: "home"|"away" }[]
---@param duration number
---@return number frac
local function decided_at(goals, duration)
    local diff = 0
    for _, g in ipairs(goals) do
        diff = diff + (g.team == "home" and 1 or -1)
    end
    if diff == 0 or duration <= 0 then
        return 1
    end
    local winner = diff > 0 and "home" or "away"
    -- Walk backwards: the deciding goal is the one that last put the winner
    -- ahead for good (margin from the loser's view never recovers after it).
    local h, a = 0, 0
    local decided = 0
    for _, g in ipairs(goals) do
        if g.team == "home" then
            h = h + 1
        else
            a = a + 1
        end
        local lead = winner == "home" and h - a or a - h
        if lead == 1 then
            decided = g.t -- candidate; overwritten if the lead is later lost
        end
    end
    return math.min(1, decided / duration)
end

---@param goals { t: number, team: "home"|"away" }[]
---@return integer
local function lead_changes(goals)
    local h, a, leader, changes = 0, 0, 0, 0
    for _, g in ipairs(goals) do
        if g.team == "home" then
            h = h + 1
        else
            a = a + 1
        end
        local sign = h > a and 1 or (a > h and -1 or 0)
        if sign ~= 0 and leader ~= 0 and sign ~= leader then
            changes = changes + 1
        end
        if sign ~= 0 then
            leader = sign
        end
    end
    return changes
end

---@param c MetricsCollector
---@param s MatchState
---@return MatchMetrics
function metrics.finish(c, s)
    c.longest_drought = math.max(c.longest_drought, c.t - c.last_chance_t)
    local gh, ga = s.score.home, s.score.away
    local owned = c.own_time.home + c.own_time.away
    local on_target = c.saves + gh + ga
    local controlled = c.dribble.controlled
    local ai_dribble = c.dribble.ai
    return {
        duration = c.t,
        goals_home = gh,
        goals_away = ga,
        goals_total = gh + ga,
        margin = math.abs(gh - ga),
        lead_changes = lead_changes(c.goals),
        decided_late = decided_at(c.goals, c.t),
        shots = c.shots,
        shots_per_goal = (gh + ga) > 0 and c.shots / (gh + ga) or nil,
        save_rate = on_target > 0 and c.saves / on_target or nil,
        passes = c.passes,
        pass_completion = c.passes > 0 and c.passes_completed / c.passes or nil,
        turnovers_per_min = c.t > 0 and c.turnovers / (c.t / 60) or 0,
        possession_balance = owned > 0 and c.own_time.home / owned or nil,
        longest_drought_s = c.longest_drought,
        controlled_dribble_carry_s = controlled.carry_s,
        controlled_dribble_close_share = controlled.carry_s > 0
                and controlled.close_s / controlled.carry_s
            or nil,
        controlled_dribble_sprint_share = controlled.carry_s > 0
                and controlled.sprint_s / controlled.carry_s
            or nil,
        controlled_dribble_juke_share = controlled.carry_s > 0
                and controlled.juke_s / controlled.carry_s
            or nil,
        controlled_dribble_touches_per_min = controlled.carry_s > 0
                and controlled.touches / (controlled.carry_s / 60)
            or 0,
        controlled_dribble_heavy_losses_per_min = controlled.carry_s > 0
                and controlled.heavy_losses / (controlled.carry_s / 60)
            or 0,
        controlled_jukes = controlled.jukes,
        ai_dribble_carry_s = ai_dribble.carry_s,
        ai_dribble_close_share = ai_dribble.carry_s > 0 and ai_dribble.close_s / ai_dribble.carry_s
            or nil,
        ai_dribble_sprint_share = ai_dribble.carry_s > 0
                and ai_dribble.sprint_s / ai_dribble.carry_s
            or nil,
        ai_dribble_juke_share = ai_dribble.carry_s > 0 and ai_dribble.juke_s / ai_dribble.carry_s
            or nil,
        ai_dribble_touches_per_min = ai_dribble.carry_s > 0
                and ai_dribble.touches / (ai_dribble.carry_s / 60)
            or 0,
        ai_dribble_heavy_losses_per_min = ai_dribble.carry_s > 0
                and ai_dribble.heavy_losses / (ai_dribble.carry_s / 60)
            or 0,
        ai_jukes = ai_dribble.jukes,
    }
end

-- Desirability of `v` under trapezoid band {zero_lo, good_lo, good_hi, zero_hi}.
---@param v number
---@param band { [1]: number, [2]: number, [3]: number, [4]: number }
---@return number  -- 0..1
function metrics.desirability(v, band)
    local zl, gl, gh, zh = band[1], band[2], band[3], band[4]
    if v <= zl or v >= zh then
        return 0
    end
    if v < gl then
        return (v - zl) / (gl - zl)
    end
    if v > gh then
        return (zh - v) / (zh - gh)
    end
    return 1
end

-- Geometric mean of the banded metrics present in `m`. A collapsed dimension
-- (desirability 0) zeroes the whole score by design; missing metrics
-- (nil denominators) are skipped, not defaulted.
---@param m MatchMetrics
---@return number score  -- 0..1
---@return table<string, number> per_metric
function metrics.fun_score(m)
    local product, n, per = 1, 0, {}
    for key, band in pairs(metrics.bands) do
        local v = m[key]
        if v ~= nil then
            local d = metrics.desirability(v, band)
            per[key] = d
            product = product * d
            n = n + 1
        end
    end
    if n == 0 then
        return 0, per
    end
    return product ^ (1 / n), per
end

---@class MetricStats
---@field n integer
---@field mean number
---@field sd number
---@field min number
---@field max number

-- Per-key distribution stats over a batch of per-match metric tables (or any
-- tables with numeric fields). nil values (missing denominators) are excluded
-- from that key's stats.
---@param list table<string, any>[]
---@return table<string, MetricStats>
function metrics.aggregate(list)
    local keys = {}
    for _, m in ipairs(list) do
        for k, v in pairs(m) do
            if type(v) == "number" then
                keys[k] = true
            end
        end
    end
    local out = {}
    for k in pairs(keys) do
        local n, sum, min, max = 0, 0, math.huge, -math.huge
        for _, m in ipairs(list) do
            local v = m[k]
            if type(v) == "number" then
                n = n + 1
                sum = sum + v
                min = math.min(min, v)
                max = math.max(max, v)
            end
        end
        local mean = sum / n
        local var = 0
        for _, m in ipairs(list) do
            local v = m[k]
            if type(v) == "number" then
                var = var + (v - mean) ^ 2
            end
        end
        out[k] = {
            n = n,
            mean = mean,
            sd = n > 1 and math.sqrt(var / (n - 1)) or 0,
            min = min,
            max = max,
        }
    end
    return out
end

return metrics
