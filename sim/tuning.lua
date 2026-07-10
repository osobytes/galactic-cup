-- Runtime-tunable gameplay knobs, for the in-match tuning panel (F1).
-- The sim reads live values through `tuning.values`; defaults here ARE the
-- shipped balance, so a fresh match plays identically to the constants they
-- replaced. Pure module: no love, no I/O — (de)serialization is string-based
-- and the game layer decides where bytes go.

local tuning = {}

---@class Knob
---@field key string
---@field label string
---@field cat string
---@field default number
---@field min number
---@field max number
---@field step number

-- Registry order = display order. Categories group the panel's tabs.
---@type Knob[]
tuning.knobs = {
    -- Movement
    {
        key = "MOVE_ACCEL",
        label = "Acceleration",
        cat = "Movement",
        default = 1100,
        min = 400,
        max = 2400,
        step = 100,
    },
    {
        key = "MOVE_DECEL",
        label = "Deceleration",
        cat = "Movement",
        default = 1500,
        min = 400,
        max = 3000,
        step = 100,
    },
    {
        key = "SPRINT_MULT",
        label = "Sprint speed x",
        cat = "Movement",
        default = 1.35,
        min = 1.1,
        max = 1.8,
        step = 0.05,
    },
    {
        key = "SPRINT_REFILL",
        label = "Sprint refill /s",
        cat = "Movement",
        default = 0.4,
        min = 0.1,
        max = 1.0,
        step = 0.05,
    },
    {
        key = "JOCKEY_SLOW",
        label = "Jockey speed x",
        cat = "Movement",
        default = 0.75,
        min = 0.5,
        max = 1.0,
        step = 0.05,
    },

    -- Attacking
    {
        key = "CHARGE_RATE",
        label = "Shot charge /s",
        cat = "Attacking",
        default = 1.5,
        min = 0.5,
        max = 3.0,
        step = 0.1,
    },
    {
        key = "PASS_CHARGE_RATE",
        label = "Pass charge /s",
        cat = "Attacking",
        default = 1.6,
        min = 0.5,
        max = 3.0,
        step = 0.1,
    },
    {
        key = "SHOT_WINDUP",
        label = "Shot wind-up s",
        cat = "Attacking",
        default = 0.15,
        min = 0,
        max = 0.4,
        step = 0.01,
    },
    {
        key = "PASS_RANGE_MAX",
        label = "Max pass range",
        cat = "Attacking",
        default = 520,
        min = 300,
        max = 800,
        step = 20,
    },
    {
        key = "HEADER_SPEED",
        label = "Header pace x",
        cat = "Attacking",
        default = 0.85,
        min = 0.5,
        max = 1.2,
        step = 0.05,
    },
    {
        key = "VOLLEY_SKY_P",
        label = "Volley sky odds",
        cat = "Attacking",
        default = 0.35,
        min = 0,
        max = 1,
        step = 0.05,
    },

    -- Defending
    {
        key = "AI_STEAL_CD",
        label = "AI poke cooldown",
        cat = "Defending",
        default = 1.2,
        min = 0.4,
        max = 2.5,
        step = 0.1,
    },
    {
        key = "STEAL_ATTEMPT",
        label = "AI poke range",
        cat = "Defending",
        default = 40,
        min = 28,
        max = 60,
        step = 2,
    },
    {
        key = "WHIFF_STUMBLE",
        label = "Whiff stumble s",
        cat = "Defending",
        default = 0.3,
        min = 0,
        max = 0.8,
        step = 0.05,
    },
    {
        key = "CARRIER_SETTLE",
        label = "AI settle touch s",
        cat = "Defending",
        default = 0.35,
        min = 0,
        max = 0.8,
        step = 0.05,
    },
    {
        key = "AI_PASS_PRESSURE",
        label = "AI pass-out range",
        cat = "Defending",
        default = 70,
        min = 30,
        max = 120,
        step = 5,
    },

    -- Keeper
    {
        key = "SAVE_SPEED_REF",
        label = "Save pace ref",
        cat = "Keeper",
        default = 1300,
        -- min widened 700 -> 400: the balance search's optimum sat on the old
        -- fence (docs/design/fun_metrics.md, phase 3).
        min = 400,
        max = 2000,
        step = 50,
    },
    {
        key = "CATCH_EVEN_QUALITY",
        label = "Catch coin-flip q",
        cat = "Keeper",
        default = 0.45,
        min = 0.2,
        max = 0.8,
        step = 0.02,
    },
    {
        key = "KEEPER_RESPECT_DIST",
        label = "Keeper ring",
        cat = "Keeper",
        default = 120,
        min = 60,
        max = 180,
        step = 10,
    },
    {
        key = "KEEPER_HOLD_HUMAN",
        label = "Keeper hold limit s",
        cat = "Keeper",
        default = 5,
        min = 2,
        max = 10,
        step = 0.5,
    },
    {
        key = "PUNT_MAX",
        label = "Max punt range",
        cat = "Keeper",
        default = 640,
        min = 400,
        max = 900,
        step = 20,
    },

    -- AI
    {
        key = "AI_SHOOT_RANGE",
        label = "AI shoot range",
        cat = "AI",
        default = 240,
        min = 160,
        -- max widened 340 -> 480 (half pitch): the balance search's optimum
        -- sat on the old fence (docs/design/fun_metrics.md, phase 3).
        max = 480,
        step = 10,
    },
    {
        key = "AI_HEADER_RANGE",
        label = "AI header range",
        cat = "AI",
        default = 200,
        min = 120,
        -- max widened 300 -> 420: the balance search's optimum sat on the old
        -- fence (docs/design/fun_metrics.md, phase 3).
        max = 420,
        step = 10,
    },
    {
        key = "CROSS_MIN_SPACE",
        label = "Cross space need",
        cat = "AI",
        default = 30,
        min = 10,
        max = 60,
        step = 5,
    },
    {
        key = "LOOSE_MAGNET",
        label = "Loose-ball magnet",
        cat = "AI",
        default = 90,
        min = 40,
        max = 160,
        step = 10,
    },
    {
        key = "TRIANGLE_DIST",
        label = "Triangle pass range",
        cat = "AI",
        default = 170,
        min = 120,
        max = 260,
        step = 10,
    },
    {
        key = "STAND_WAKE",
        label = "Positional calm",
        cat = "AI",
        default = 34,
        min = 16,
        max = 80,
        step = 2,
    },

    -- Replay (presentation)
    {
        key = "REPLAY_SLOWMO",
        label = "Replay speed x",
        cat = "Replay",
        default = 0.35,
        min = 0.1,
        max = 1.0,
        step = 0.05,
    },
    {
        key = "REPLAY_SECONDS",
        label = "Replay length s",
        cat = "Replay",
        default = 4,
        min = 2,
        max = 8,
        step = 0.5,
    },
}

---@type table<string, Knob>
tuning.by_key = {}
---@type table<string, number>
tuning.values = {}
for _, k in ipairs(tuning.knobs) do
    tuning.by_key[k.key] = k
    tuning.values[k.key] = k.default
end

-- Distinct categories, in registry order.
---@return string[]
function tuning.categories()
    local seen, cats = {}, {}
    for _, k in ipairs(tuning.knobs) do
        if not seen[k.cat] then
            seen[k.cat] = true
            cats[#cats + 1] = k.cat
        end
    end
    return cats
end

---@param cat string
---@return Knob[]
function tuning.in_category(cat)
    local out = {}
    for _, k in ipairs(tuning.knobs) do
        if k.cat == cat then
            out[#out + 1] = k
        end
    end
    return out
end

-- Set a knob (clamped to its range). Unknown keys are ignored.
---@param key string
---@param v number
function tuning.set(key, v)
    local k = tuning.by_key[key]
    if k then
        tuning.values[key] = math.max(k.min, math.min(k.max, v))
    end
end

-- Nudge a knob by `dirs` steps (negative = down).
---@param key string
---@param dirs number
function tuning.nudge(key, dirs)
    local k = tuning.by_key[key]
    if k then
        tuning.set(key, tuning.values[key] + k.step * dirs)
    end
end

---@param key string?  -- reset one knob, or everything when nil
function tuning.reset(key)
    if key then
        local k = tuning.by_key[key]
        if k then
            tuning.values[key] = k.default
        end
        return
    end
    for _, k in ipairs(tuning.knobs) do
        tuning.values[k.key] = k.default
    end
end

---@param key string
---@return boolean
function tuning.is_default(key)
    local k = tuning.by_key[key]
    return k ~= nil and tuning.values[key] == k.default
end

-- One `KEY=value` line per NON-default knob (a fresh file means all defaults).
---@return string
function tuning.serialize()
    local out = {}
    for _, k in ipairs(tuning.knobs) do
        if tuning.values[k.key] ~= k.default then
            out[#out + 1] = ("%s=%.6g"):format(k.key, tuning.values[k.key])
        end
    end
    return table.concat(out, "\n")
end

-- Apply a serialized blob on top of defaults. Malformed lines are skipped.
---@param blob string
function tuning.deserialize(blob)
    tuning.reset()
    for line in tostring(blob):gmatch("[^\r\n]+") do
        local key, num = line:match("^([%w_]+)=([%-%d%.eE]+)$")
        local v = key and tonumber(num)
        if v then
            tuning.set(key, v)
        end
    end
end

return tuning
