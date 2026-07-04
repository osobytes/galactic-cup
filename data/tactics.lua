-- Team mentalities. Each one nudges AI behavior; effects are intentionally simple
-- and readable (see AGENTS.md vision: strategy felt, not a full simulation).
--
--   press      : how many off-ball players hunt the contested ball
--   line_shift : anchor depth bias along the attack axis (fraction of pitch);
--                + pushes the shape upfield, - drops it deeper
--   stamina_drain : multiplier (stub for M4)

-- Off-ball marking/shape config (see sim/ai.lua + move_players). `scheme` picks
-- how non-presser defenders behave; the rest are tuning knobs for how tight the
-- press is, how hard the block collapses toward the ball, and how far attackers
-- push to support. `match.new` fills any missing block with the hybrid default.
---@class MarkingConfig
---@field scheme "zonal"|"man"|"hybrid"
---@field man_marks integer  -- opponents to man-mark in hybrid (0 ignored otherwise)
---@field standoff number  -- px the presser holds off the carrier
---@field compactness number  -- 0..1 how hard the block shifts to ball/goal when defending
---@field support number  -- 0..1 attacking off-ball aggressiveness (support depth)

---@class TacticData
---@field id string
---@field name string
---@field press integer
---@field line_shift number
---@field stamina_drain number
---@field marking MarkingConfig

---@type table<string, TacticData>
return {
    balanced = {
        id = "balanced",
        name = "Balanced",
        press = 1,
        line_shift = 0.0,
        stamina_drain = 1.0,
        marking = {
            scheme = "hybrid",
            man_marks = 1,
            standoff = 32,
            compactness = 0.5,
            support = 0.5,
        },
    },
    press_high = {
        id = "press_high",
        name = "Press High",
        press = 2,
        line_shift = 0.12,
        stamina_drain = 1.4,
        marking = {
            scheme = "man",
            man_marks = 3,
            standoff = 22,
            compactness = 0.7,
            support = 0.65,
        },
    },
    counter = {
        id = "counter",
        name = "Counter Attack",
        press = 1,
        line_shift = -0.12,
        stamina_drain = 0.9,
        marking = {
            scheme = "zonal",
            man_marks = 0,
            standoff = 40,
            compactness = 0.35,
            support = 0.4,
        },
    },
}
