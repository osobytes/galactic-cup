-- Pure render-only reconciliation for corrected player and ball positions.
-- The authoritative MatchState is read, never copied into or mutated by this
-- model. Small corrections preserve the last displayed pose and linearly shed
-- their offset over render time; large corrections snap immediately.

---@class CorrectionSmoothingPoint
---@field x number
---@field y number

---@class CorrectionSmoothingPose
---@field players table<string, CorrectionSmoothingPoint>
---@field ball CorrectionSmoothingPoint

---@class CorrectionSmoothingOffset
---@field x number
---@field y number
---@field remaining number

---@class CorrectionSmoothingOptions
---@field duration number?
---@field hard_snap_distance number?

---@class CorrectionSmoothingState
---@field duration number
---@field hard_snap_distance number
---@field player_offsets table<string, CorrectionSmoothingOffset>
---@field ball_offset CorrectionSmoothingOffset?
---@field displayed CorrectionSmoothingPose

---@class CorrectionSmoothingDiagnostics
---@field maximum_magnitude number
---@field active_count integer

---@class CorrectionSmoothingModule
local correction_smoothing = {}

correction_smoothing.DEFAULT_DURATION = 0.1
correction_smoothing.DEFAULT_HARD_SNAP_DISTANCE = 160

local EPSILON = 1e-9

---@param value any
---@param label string
local function assert_nonnegative_finite(value, label)
    assert(
        type(value) == "number"
            and value == value
            and value ~= math.huge
            and value ~= -math.huge
            and value >= 0,
        label .. " must be a non-negative finite number"
    )
end

---@param point { x: number, y: number }
---@return CorrectionSmoothingPoint
local function copy_point(point)
    return { x = point.x, y = point.y }
end

---@param pose CorrectionSmoothingPose
---@return CorrectionSmoothingPose
local function copy_pose(pose)
    local players = {}
    for id, point in pairs(pose.players) do
        players[id] = copy_point(point)
    end
    return {
        players = players,
        ball = copy_point(pose.ball),
    }
end

---@param source MatchState
---@return CorrectionSmoothingPose
local function authoritative_pose(source)
    local players = {}
    for _, player in ipairs(source.players) do
        players[player.id] = copy_point(player.pos)
    end
    return {
        players = players,
        ball = copy_point(source.ball),
    }
end

---@param offset CorrectionSmoothingOffset
---@return CorrectionSmoothingOffset
local function copy_offset(offset)
    return {
        x = offset.x,
        y = offset.y,
        remaining = offset.remaining,
    }
end

---@param previous CorrectionSmoothingPoint?
---@param authoritative CorrectionSmoothingPoint
---@param duration number
---@param hard_snap_distance number
---@return CorrectionSmoothingOffset?
local function corrected_offset(previous, authoritative, duration, hard_snap_distance)
    if previous == nil or duration <= EPSILON then
        return nil
    end
    local x = previous.x - authoritative.x
    local y = previous.y - authoritative.y
    local magnitude = math.sqrt(x * x + y * y)
    if magnitude <= EPSILON or magnitude >= hard_snap_distance then
        return nil
    end
    return {
        x = x,
        y = y,
        remaining = duration,
    }
end

---@param authoritative CorrectionSmoothingPoint
---@param offset CorrectionSmoothingOffset?
---@return CorrectionSmoothingPoint
local function displayed_point(authoritative, offset)
    if offset == nil then
        return copy_point(authoritative)
    end
    return {
        x = authoritative.x + offset.x,
        y = authoritative.y + offset.y,
    }
end

---@param offset CorrectionSmoothingOffset?
---@param dt number
---@return CorrectionSmoothingOffset?
local function decayed_offset(offset, dt)
    if offset == nil then
        return nil
    end
    local remaining = math.max(0, offset.remaining - dt)
    if remaining <= EPSILON then
        return nil
    end
    local scale = remaining / offset.remaining
    return {
        x = offset.x * scale,
        y = offset.y * scale,
        remaining = remaining,
    }
end

---@param source MatchState
---@param options CorrectionSmoothingOptions?
---@return CorrectionSmoothingState
function correction_smoothing.new(source, options)
    options = options or {}
    local duration = options.duration or correction_smoothing.DEFAULT_DURATION
    local hard_snap_distance = options.hard_snap_distance
        or correction_smoothing.DEFAULT_HARD_SNAP_DISTANCE
    assert_nonnegative_finite(duration, "correction smoothing duration")
    assert_nonnegative_finite(hard_snap_distance, "correction hard-snap distance")
    assert(hard_snap_distance > 0, "correction hard-snap distance must be positive")
    return {
        duration = duration,
        hard_snap_distance = hard_snap_distance,
        player_offsets = {},
        ball_offset = nil,
        displayed = authoritative_pose(source),
    }
end

-- Start a correction without advancing presentation time. Every smoothed
-- drawable therefore begins exactly at its pose from the preceding render.
---@param state CorrectionSmoothingState
---@param source MatchState
---@return CorrectionSmoothingState
function correction_smoothing.correct(state, source)
    local authoritative = authoritative_pose(source)
    local offsets = {}
    local displayed_players = {}
    for id, point in pairs(authoritative.players) do
        local offset = corrected_offset(
            state.displayed.players[id],
            point,
            state.duration,
            state.hard_snap_distance
        )
        if offset then
            offsets[id] = offset
        end
        displayed_players[id] = displayed_point(point, offset)
    end
    local ball_offset = corrected_offset(
        state.displayed.ball,
        authoritative.ball,
        state.duration,
        state.hard_snap_distance
    )
    return {
        duration = state.duration,
        hard_snap_distance = state.hard_snap_distance,
        player_offsets = offsets,
        ball_offset = ball_offset,
        displayed = {
            players = displayed_players,
            ball = displayed_point(authoritative.ball, ball_offset),
        },
    }
end

-- Advance only with render dt. Authoritative movement remains immediate under
-- the decaying correction offset; this state is never fed back into the sim.
---@param state CorrectionSmoothingState
---@param source MatchState
---@param dt number
---@return CorrectionSmoothingState
function correction_smoothing.advance(state, source, dt)
    assert_nonnegative_finite(dt, "correction smoothing render dt")
    local authoritative = authoritative_pose(source)
    local offsets = {}
    local displayed_players = {}
    for id, point in pairs(authoritative.players) do
        local previous = state.player_offsets[id]
        local offset = previous and decayed_offset(copy_offset(previous), dt) or nil
        if offset then
            offsets[id] = offset
        end
        displayed_players[id] = displayed_point(point, offset)
    end
    local ball_offset = state.ball_offset and decayed_offset(copy_offset(state.ball_offset), dt)
        or nil
    return {
        duration = state.duration,
        hard_snap_distance = state.hard_snap_distance,
        player_offsets = offsets,
        ball_offset = ball_offset,
        displayed = {
            players = displayed_players,
            ball = displayed_point(authoritative.ball, ball_offset),
        },
    }
end

-- Clear offsets at a scene discontinuity while preserving configured tuning.
---@param state CorrectionSmoothingState
---@param source MatchState
---@return CorrectionSmoothingState
function correction_smoothing.clear(state, source)
    return correction_smoothing.new(source, {
        duration = state.duration,
        hard_snap_distance = state.hard_snap_distance,
    })
end

---@param state CorrectionSmoothingState
---@return CorrectionSmoothingPose
function correction_smoothing.pose(state)
    return copy_pose(state.displayed)
end

---@param state CorrectionSmoothingState
---@return CorrectionSmoothingDiagnostics
function correction_smoothing.diagnostics(state)
    local active_count = 0
    local maximum_magnitude = 0
    for _, offset in pairs(state.player_offsets) do
        active_count = active_count + 1
        maximum_magnitude =
            math.max(maximum_magnitude, math.sqrt(offset.x * offset.x + offset.y * offset.y))
    end
    if state.ball_offset then
        active_count = active_count + 1
        maximum_magnitude = math.max(
            maximum_magnitude,
            math.sqrt(
                state.ball_offset.x * state.ball_offset.x
                    + state.ball_offset.y * state.ball_offset.y
            )
        )
    end
    return {
        maximum_magnitude = maximum_magnitude,
        active_count = active_count,
    }
end

return correction_smoothing
