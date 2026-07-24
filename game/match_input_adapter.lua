-- Offline input sampling is render-rate driven, but legacy MatchInput records
-- are consumed only by the fixed simulation clock. Pending edges survive a
-- zero-tick render update and are emitted once on the next simulated tick.

local Vec2 = require("core.vec2")

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
---@field equipment_held boolean

---@class MatchInputAdapterState
---@field held MatchInputHeld
---@field pending MatchInputEdges
---@field equipment_sampled_held boolean
---@field equipment_transitioned boolean

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
        equipment_held = false,
    }
end

---@return MatchInputAdapterState
function match_input_adapter.new()
    return {
        held = neutral_held(),
        pending = no_edges(),
        equipment_sampled_held = false,
        equipment_transitioned = false,
    }
end

-- Capture one render-sampled input without consuming its one-shot actions.
---@param state MatchInputAdapterState
---@param input MatchInput
---@return MatchInputAdapterState
function match_input_adapter.sample(state, input)
    local equipment_transitioned = state.equipment_transitioned
        or input.equipment_pressed
        or input.equipment_released
        or state.held.equipment_held ~= input.equipment_held
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
            equipment_held = input.equipment_held,
        },
        pending = {
            shoot = state.pending.shoot or input.shoot,
            pass = state.pending.pass or input.pass,
            switch = state.pending.switch or input.switch,
            dash = state.pending.dash or input.dash,
            dodge = state.pending.dodge or input.dodge,
            lob = state.pending.lob or (input.lob and (input.shoot or input.pass)),
        },
        equipment_sampled_held = state.equipment_sampled_held,
        equipment_transitioned = equipment_transitioned,
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
    local equipment_pressed = false
    local equipment_released = false
    if state.equipment_transitioned then
        if state.equipment_sampled_held then
            if held.equipment_held then
                equipment_pressed = true
            else
                equipment_released = true
            end
        else
            equipment_pressed = true
            equipment_released = not held.equipment_held
        end
    end
    return {
        held = held,
        pending = no_edges(),
        equipment_sampled_held = held.equipment_held,
        equipment_transitioned = false,
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
        equipment_held = held.equipment_held,
        equipment_pressed = equipment_pressed,
        equipment_released = equipment_released,
    }
end

return match_input_adapter
