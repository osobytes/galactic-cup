-- Team mentalities. Each one nudges AI behavior; effects are intentionally simple
-- and readable (see AGENTS.md vision: strategy felt, not a full simulation).
--
--   press      : how many off-ball players hunt the contested ball
--   line_shift : anchor depth bias along the attack axis (fraction of pitch);
--                + pushes the shape upfield, - drops it deeper
--   stamina_drain : multiplier (stub for M4)

---@class TacticData
---@field id string
---@field name string
---@field press integer
---@field line_shift number
---@field stamina_drain number

---@type table<string, TacticData>
return {
    balanced = {
        id = "balanced",
        name = "Balanced",
        press = 1,
        line_shift = 0.0,
        stamina_drain = 1.0,
    },
    press_high = {
        id = "press_high",
        name = "Press High",
        press = 2,
        line_shift = 0.12,
        stamina_drain = 1.4,
    },
    counter = {
        id = "counter",
        name = "Counter Attack",
        press = 1,
        line_shift = -0.12,
        stamina_drain = 0.9,
    },
}
