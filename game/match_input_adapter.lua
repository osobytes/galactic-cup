-- Offline input sampling is render-rate driven, but legacy MatchInput records
-- are consumed only by the fixed simulation clock. Pending edges survive a
-- zero-tick render update and are emitted once on the next simulated tick.

local Vec2 = require("core.vec2")
local input_frame = require("sim.input_frame")
local slot_input = require("sim.slot_input")

---@class MatchInputEdges
---@field shoot boolean
---@field pass boolean
---@field switch boolean
---@field dash boolean
---@field dodge boolean
---@field lob boolean -- Captures the modifier paired with a pending release edge.

---@class MatchInputHeld
---@field move Vec2
---@field shoot_held boolean
---@field pass_held boolean
---@field lob boolean
---@field sprint boolean
---@field jockey boolean
---@field aerial_strike boolean
---@field aerial_acrobatic boolean

---@class MatchInputAdapterState
---@field held MatchInputHeld
---@field pending MatchInputEdges

---@class MatchInputAdapterModule
local match_input_adapter = {}

---@return MatchInputEdges
local function no_edges()
    return {
        shoot = false,
        pass = false,
        switch = false,
        dash = false,
        dodge = false,
        lob = false,
    }
end

---@return MatchInputHeld
local function neutral_held()
    return {
        move = Vec2.new(0, 0),
        shoot_held = false,
        pass_held = false,
        lob = false,
        sprint = false,
        jockey = false,
        aerial_strike = false,
        aerial_acrobatic = false,
    }
end

---@return MatchInputAdapterState
function match_input_adapter.new()
    return {
        held = neutral_held(),
        pending = no_edges(),
    }
end

-- Capture one render-sampled input without consuming its one-shot actions.
---@param state MatchInputAdapterState
---@param input MatchInput
---@return MatchInputAdapterState
function match_input_adapter.sample(state, input)
    return {
        held = {
            move = input.move,
            shoot_held = input.shoot_held,
            pass_held = input.pass_held,
            lob = input.lob,
            sprint = input.sprint,
            jockey = input.jockey,
            aerial_strike = input.aerial_strike == true,
            aerial_acrobatic = input.aerial_acrobatic == true,
        },
        pending = {
            shoot = state.pending.shoot or input.shoot,
            pass = state.pending.pass or input.pass,
            switch = state.pending.switch or input.switch,
            dash = state.pending.dash or input.dash,
            dodge = state.pending.dodge or input.dodge,
            lob = state.pending.lob or (input.lob and (input.shoot or input.pass)),
        },
    }
end

-- Produce one legacy MatchInput for a single clock tick, then clear only the
-- edges that have been consumed. Holds remain live for every catch-up tick.
---@param state MatchInputAdapterState
---@return MatchInputAdapterState state
---@return MatchInput input
function match_input_adapter.next_tick(state)
    local held = state.held
    local pending = state.pending
    return {
        held = held,
        pending = no_edges(),
    }, {
        move = held.move,
        shoot = pending.shoot,
        shoot_held = held.shoot_held,
        pass = pending.pass,
        pass_held = held.pass_held,
        switch = pending.switch,
        dash = pending.dash,
        dodge = pending.dodge,
        lob = held.lob or pending.lob,
        sprint = held.sprint,
        jockey = held.jockey,
        aerial_strike = held.aerial_strike,
        aerial_acrobatic = held.aerial_acrobatic,
    }
end

-- The showcase's one keyboard/gamepad stream owns one fixed outfield slot.
-- The remaining rows stay present and neutral here; sim.match applies its
-- explicit configured bot/neutral source policy to those rows. This keeps
-- legacy MatchInput entirely on the render adapter side of InputFrame.
---@param state MatchInputAdapterState
---@param tick integer
---@param slot_index integer
---@return MatchInputAdapterState state
---@return InputFrame frame
function match_input_adapter.next_frame(state, tick, slot_index)
    assert(slot_index >= 1 and slot_index <= input_frame.SLOT_COUNT, "offline slot index invalid")
    local next, input = match_input_adapter.next_tick(state)
    local slots = {}
    for index = 1, input_frame.SLOT_COUNT do
        slots[index] = input_frame.neutral_sample()
    end
    slots[slot_index] = slot_input.to_sample(input)
    return next, assert(input_frame.new(tick, slots))
end

return match_input_adapter
