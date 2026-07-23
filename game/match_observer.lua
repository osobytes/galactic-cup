local fixed_clock = require("sim.fixed_clock")

---@class MatchObserver
---@field team_of table<string, "home"|"away">
---@field keeper table<string, boolean>
---@field player_order string[]
---@field shots { home: integer, away: integer }
---@field saves { home: integer, away: integer }
---@field passes { home: integer, away: integer }
---@field completed_passes { home: integer, away: integer }
---@field possession { home: number, away: number }
---@field involvement table<string, integer>
---@field pending_pass "home"|"away"|nil
---@field last_shooter { home: string?, away: string? }
---@field previous_score { home: integer, away: integer }
---@field confirmed_event_ids table<string, boolean>
---@field last_confirmed_tick integer

---@class ObservedMatchSummary
---@field home_stats TeamResultStats
---@field away_stats TeamResultStats
---@field mvp_player_id string?
---@field mvp_summary string?

---@class MatchObserverModule
local observer = {}

---@param values table<string, integer>
---@param id string?
---@param amount integer
local function award(values, id, amount)
    if id then
        values[id] = (values[id] or 0) + amount
    end
end

---@param state MatchState
---@return MatchObserver
function observer.new(state)
    local team_of = {}
    local keeper = {}
    local player_order = {}
    local involvement = {}
    for _, player in ipairs(state.players) do
        team_of[player.id] = player.team
        keeper[player.id] = player.is_keeper
        player_order[#player_order + 1] = player.id
        involvement[player.id] = 0
    end
    return {
        team_of = team_of,
        keeper = keeper,
        player_order = player_order,
        shots = { home = 0, away = 0 },
        saves = { home = 0, away = 0 },
        passes = { home = 0, away = 0 },
        completed_passes = { home = 0, away = 0 },
        possession = { home = 0, away = 0 },
        involvement = involvement,
        pending_pass = nil,
        last_shooter = { home = nil, away = nil },
        previous_score = { home = state.score.home, away = state.score.away },
        confirmed_event_ids = {},
        last_confirmed_tick = -1,
    }
end

---@param value number
---@param total number
---@return number?
local function share(value, total)
    return total > 0 and value / total or nil
end

---@param value integer
---@param total integer
---@return number?
local function completion(value, total)
    return total > 0 and value / total or nil
end

---@param state MatchState
---@param event MatchEvent
---@return "home"|"away"?
local function event_team(state, event)
    if not event.player then
        return nil
    end
    for _, player in ipairs(state.players) do
        if player.id == event.player then
            return player.team
        end
    end
    return nil
end

---@param value MatchObserver
---@param state MatchState
---@param dt number
---@param events MatchEvent[]?
function observer.observe(value, state, dt, events)
    for _, event in ipairs(events or state.events) do
        local team = event_team(state, event)
        if event.kind == "pass" and team then
            value.passes[team] = value.passes[team] + 1
            value.pending_pass = team
            award(value.involvement, event.player, 1)
        elseif
            (
                event.kind == "shot"
                or event.kind == "header"
                or event.kind == "volley"
                or event.kind == "bicycle"
            )
            and team
            and event.player
            and not value.keeper[event.player]
        then
            value.shots[team] = value.shots[team] + 1
            value.last_shooter[team] = event.player
            award(value.involvement, event.player, 2)
        elseif (event.kind == "catch" or event.kind == "parry") and team then
            value.saves[team] = value.saves[team] + 1
            award(value.involvement, event.player, 3)
        elseif
            event.kind == "tackle"
            or event.kind == "block"
            or event.kind == "claim"
            or event.kind == "juke"
            or event.kind == "reception"
        then
            award(value.involvement, event.player, 1)
        end
    end

    local owner = state.owner and state.players[state.owner] or nil
    if owner then
        value.possession[owner.team] = value.possession[owner.team] + dt
        if value.pending_pass then
            if owner.team == value.pending_pass then
                value.completed_passes[owner.team] = value.completed_passes[owner.team] + 1
            end
            value.pending_pass = nil
        end
    end

    if state.score.home > value.previous_score.home then
        award(value.involvement, value.last_shooter.home, 5)
    end
    if state.score.away > value.previous_score.away then
        award(value.involvement, value.last_shooter.away, 5)
    end
    value.previous_score.home = state.score.home
    value.previous_score.away = state.score.away
end

---@param value MatchObserver
---@param event RollbackWrappedMatchEvent
local function observe_confirmed_event(value, event)
    if value.confirmed_event_ids[event.id] then
        return
    end
    value.confirmed_event_ids[event.id] = true
    local payload = event.payload
    local team = payload.player and value.team_of[payload.player] or nil
    if payload.kind == "pass" and team then
        value.passes[team] = value.passes[team] + 1
        value.pending_pass = team
        award(value.involvement, payload.player, 1)
    elseif
        (
            payload.kind == "shot"
            or payload.kind == "header"
            or payload.kind == "volley"
            or payload.kind == "bicycle"
        )
        and team
        and payload.player
        and not value.keeper[payload.player]
    then
        value.shots[team] = value.shots[team] + 1
        value.last_shooter[team] = payload.player
        award(value.involvement, payload.player, 2)
    elseif (payload.kind == "catch" or payload.kind == "parry") and team then
        value.saves[team] = value.saves[team] + 1
        award(value.involvement, payload.player, 3)
    elseif
        payload.kind == "tackle"
        or payload.kind == "block"
        or payload.kind == "claim"
        or payload.kind == "juke"
        or payload.kind == "reception"
    then
        award(value.involvement, payload.player, 1)
    end
end

-- Rollback matches publish only newly confirmed, immutable steps. This path is
-- boundary-addressed and idempotent; it never reads the speculative live state.
---@param value MatchObserver
---@param step RollbackEventStep
---@return boolean observed
function observer.observe_confirmed(value, step)
    if step.tick <= value.last_confirmed_tick then
        return false
    end
    assert(
        step.tick == value.last_confirmed_tick + 1,
        "confirmed observer steps must be contiguous"
    )
    for _, event in ipairs(step.match_events) do
        observe_confirmed_event(value, event)
    end

    local owner_team = step.state.owner_team
    if owner_team then
        value.possession[owner_team] = value.possession[owner_team] + fixed_clock.TICK_SECONDS
        if value.pending_pass then
            if owner_team == value.pending_pass then
                value.completed_passes[owner_team] = value.completed_passes[owner_team] + 1
            end
            value.pending_pass = nil
        end
    end
    if step.state.score.home > value.previous_score.home then
        award(value.involvement, value.last_shooter.home, 5)
    end
    if step.state.score.away > value.previous_score.away then
        award(value.involvement, value.last_shooter.away, 5)
    end
    value.previous_score.home = step.state.score.home
    value.previous_score.away = step.state.score.away
    value.last_confirmed_tick = step.tick
    return true
end

---@param value MatchObserver
---@return string?
local function mvp_id(value)
    local best_id = nil
    local best_score = 0
    for _, id in ipairs(value.player_order) do
        local score = value.involvement[id] or 0
        if score > best_score then
            best_id = id
            best_score = score
        end
    end
    return best_id
end

---@param value MatchObserver
---@return ObservedMatchSummary
function observer.finish(value)
    local owned = value.possession.home + value.possession.away
    local mvp = mvp_id(value)
    return {
        home_stats = {
            shots = value.shots.home,
            possession = share(value.possession.home, owned),
            saves = value.saves.home,
            pass_completion = completion(value.completed_passes.home, value.passes.home),
        },
        away_stats = {
            shots = value.shots.away,
            possession = share(value.possession.away, owned),
            saves = value.saves.away,
            pass_completion = completion(value.completed_passes.away, value.passes.away),
        },
        mvp_player_id = mvp,
        mvp_summary = mvp and "Recorded the fixture's strongest all-around contribution." or nil,
    }
end

return observer
