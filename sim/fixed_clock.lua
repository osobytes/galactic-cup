-- The sole simulation-time authority for render-driven matches. The clock is
-- deliberately input-shape agnostic: OMP-1's current offline adapter supplies
-- one legacy MatchInput per tick, while the later multi-slot refactor can
-- supply an InputFrame without changing the cadence contract.

---@class FixedClockState
---@field tick integer -- Next tick to simulate; starts at zero and only increases.
---@field accumulator number -- Unsimulated render time, always smaller than one tick after advance.
---@field dropped_ticks integer -- Whole simulation ticks discarded after overloads.
---@field overloads integer -- Number of render updates that exceeded the catch-up budget.

---@class FixedClockAdvance
---@field ticks integer -- Ticks simulated during this render update.
---@field first_tick integer? -- First input tick consumed, if any.
---@field last_tick integer? -- Last input tick consumed, if any.
---@field dropped_ticks integer -- Whole ticks discarded during this render update.
---@field stopped boolean -- The step callback ended the simulation early.

---@alias FixedClockInputProvider fun(tick: integer): any
---@alias FixedClockStep fun(tick: integer, input: any): boolean?

---@class FixedClockModule
local fixed_clock = {}

fixed_clock.TICK_RATE = 60
fixed_clock.TICK_SECONDS = 1 / fixed_clock.TICK_RATE
fixed_clock.MAX_TICKS_PER_UPDATE = 8

local EPSILON = fixed_clock.TICK_SECONDS * 1e-9

---@param value number
---@param label string
local function assert_finite_non_negative(value, label)
    assert(type(value) == "number" and value == value and value < math.huge and value >= 0, label)
end

---@param state FixedClockState
local function assert_state(state)
    assert(type(state) == "table", "fixed clock state is required")
    assert(
        type(state.tick) == "number" and state.tick >= 0 and state.tick == math.floor(state.tick),
        "tick invalid"
    )
    assert(type(state.accumulator) == "number" and state.accumulator >= 0, "accumulator invalid")
    assert(
        type(state.dropped_ticks) == "number"
            and state.dropped_ticks >= 0
            and state.dropped_ticks == math.floor(state.dropped_ticks),
        "dropped tick count invalid"
    )
    assert(
        type(state.overloads) == "number"
            and state.overloads >= 0
            and state.overloads == math.floor(state.overloads),
        "overload count invalid"
    )
end

---@return FixedClockState
function fixed_clock.new()
    return {
        tick = 0,
        accumulator = 0,
        dropped_ticks = 0,
        overloads = 0,
    }
end

-- Run exactly one canonical tick. Headless callers use this rather than an
-- independent `match.step(..., 1 / 60, ...)` loop, so both paths share the
-- same tick numbering and simulation interval.
---@param state FixedClockState
---@param input any
---@param step FixedClockStep
---@return integer tick
---@return boolean continue
function fixed_clock.step(state, input, step)
    assert_state(state)
    assert(type(step) == "function", "fixed clock step callback is required")
    local tick = state.tick
    local continue = step(tick, input)
    state.tick = tick + 1
    return tick, continue ~= false
end

-- Advance a render-driven simulation. At most MAX_TICKS_PER_UPDATE canonical
-- ticks run for one render update. If a frame arrives with more whole ticks of
-- debt, the excess is intentionally dropped and only the fractional remainder
-- is retained. The match therefore slows under sustained overload instead of
-- growing an unbounded catch-up queue or receiving a variable simulation dt.
---@param state FixedClockState
---@param render_dt number
---@param input_for_tick FixedClockInputProvider
---@param step FixedClockStep
---@return FixedClockAdvance
function fixed_clock.advance(state, render_dt, input_for_tick, step)
    assert_state(state)
    assert_finite_non_negative(render_dt, "render dt must be a finite non-negative number")
    assert(type(input_for_tick) == "function", "fixed clock input provider is required")
    assert(type(step) == "function", "fixed clock step callback is required")

    state.accumulator = state.accumulator + render_dt
    local result = {
        ticks = 0,
        first_tick = nil,
        last_tick = nil,
        dropped_ticks = 0,
        stopped = false,
    }

    while
        state.accumulator + EPSILON >= fixed_clock.TICK_SECONDS
        and result.ticks < fixed_clock.MAX_TICKS_PER_UPDATE
    do
        local tick = state.tick
        local input = input_for_tick(tick)
        local _, continue = fixed_clock.step(state, input, step)
        state.accumulator = state.accumulator - fixed_clock.TICK_SECONDS
        if state.accumulator < 0 then
            state.accumulator = 0
        end
        result.ticks = result.ticks + 1
        result.first_tick = result.first_tick or tick
        result.last_tick = tick
        if not continue then
            state.accumulator = 0
            result.stopped = true
            return result
        end
    end

    if state.accumulator + EPSILON >= fixed_clock.TICK_SECONDS then
        local dropped = math.floor((state.accumulator + EPSILON) / fixed_clock.TICK_SECONDS)
        state.accumulator = state.accumulator - dropped * fixed_clock.TICK_SECONDS
        if state.accumulator < 0 then
            state.accumulator = 0
        end
        state.dropped_ticks = state.dropped_ticks + dropped
        state.overloads = state.overloads + 1
        result.dropped_ticks = dropped
    end

    return result
end

return fixed_clock
