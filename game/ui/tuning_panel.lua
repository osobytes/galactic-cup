-- In-match tuning panel (F1): live gameplay-knob editing for playtesting.
-- State transitions are pure (testable headless); `draw` is the only love-
-- facing part. Persistence goes through love.filesystem when available.

local tuning = require("sim.tuning")
local presets = require("data.tuning_presets")

local SAVE_FILE = "tuning.txt"

local panel = {
    open = false,
    cat = 1, -- index into tuning.categories()
    row = 1, -- index into the current category's knobs
    preset = 1, -- index into data/tuning_presets (last applied; 1 = defaults)
    status = nil, ---@type string?  -- one-line feedback (saved/loaded/reset)
}

local function cats()
    return tuning.categories()
end

local function rows()
    return tuning.in_category(cats()[panel.cat])
end

function panel.toggle()
    panel.open = not panel.open
    panel.status = nil
end

-- Save/load overrides via love.filesystem (no-op headless).
function panel.save()
    if love.filesystem then
        love.filesystem.write(SAVE_FILE, tuning.serialize())
        panel.status = "saved to " .. SAVE_FILE
    end
end

function panel.load()
    if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(SAVE_FILE) then
        tuning.deserialize(love.filesystem.read(SAVE_FILE) or "")
        panel.status = "loaded " .. SAVE_FILE
        return true
    end
    return false
end

-- Handle a key while the panel is open. Returns true if consumed.
---@param key string
---@param big boolean  -- large steps (shift held)
---@return boolean handled
function panel.key(key, big)
    if not panel.open then
        return false
    end
    local r = rows()
    local mult = big and 10 or 1
    if key == "up" then
        panel.row = (panel.row - 2) % #r + 1
    elseif key == "down" then
        panel.row = panel.row % #r + 1
    elseif key == "left" then
        tuning.nudge(r[panel.row].key, -mult)
    elseif key == "right" then
        tuning.nudge(r[panel.row].key, mult)
    elseif key == "tab" then
        panel.cat = panel.cat % #cats() + 1
        panel.row = 1
    elseif key == "backspace" then
        if big then
            tuning.reset()
            panel.status = "ALL knobs reset to defaults"
        else
            tuning.reset(r[panel.row].key)
            panel.status = nil
        end
    elseif key == "f2" then
        panel.save()
    elseif key == "f3" then
        if not panel.load() then
            panel.status = "no saved tuning"
        end
    elseif key == "f4" then
        -- Cycle balance presets (data/tuning_presets.lua): each applies its
        -- blob on top of a full reset, so presets never stack.
        panel.preset = panel.preset % #presets + 1
        local p = presets[panel.preset]
        tuning.deserialize(p.blob)
        panel.status = "preset: " .. p.name
    elseif key == "f1" or key == "escape" then
        panel.open = false
    else
        return false
    end
    return true
end

-- Draw the overlay. Stub-safe: only setColor/rectangle/print/printf.
---@param vp { w: number, h: number }
function panel.draw(vp)
    if not panel.open then
        return
    end
    local w, x0, y0 = 380, 24, 60
    local r = rows()
    local h = 96 + #r * 22
    love.graphics.setColor(0.02, 0.05, 0.12, 0.92)
    love.graphics.rectangle("fill", x0, y0, w, h)
    love.graphics.setColor(0.35, 0.75, 1.0, 0.9)
    love.graphics.rectangle("line", x0, y0, w, h)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("TUNING (paused)", x0 + 12, y0 + 10)
    local cat_line = {}
    for i, c in ipairs(cats()) do
        cat_line[#cat_line + 1] = (i == panel.cat) and ("[" .. c .. "]") or (" " .. c .. " ")
    end
    love.graphics.setColor(0.7, 0.9, 1)
    love.graphics.print(table.concat(cat_line, " "), x0 + 12, y0 + 30)

    for i, k in ipairs(r) do
        local y = y0 + 56 + (i - 1) * 22
        local sel = i == panel.row
        if sel then
            love.graphics.setColor(0.2, 0.45, 0.7, 0.5)
            love.graphics.rectangle("fill", x0 + 6, y - 2, w - 12, 20)
        end
        local v = tuning.values[k.key]
        local changed = not tuning.is_default(k.key)
        love.graphics.setColor(
            changed and 1 or 0.75,
            changed and 0.8 or 0.85,
            changed and 0.4 or 0.9
        )
        love.graphics.print(k.label, x0 + 14, y)
        love.graphics.print(("%.6g%s"):format(v, changed and " *" or ""), x0 + 210, y)
        -- Value bar within the knob's range.
        local frac = (v - k.min) / (k.max - k.min)
        love.graphics.setColor(0.15, 0.3, 0.45, 0.9)
        love.graphics.rectangle("fill", x0 + 292, y + 4, 74, 8)
        love.graphics.setColor(0.45, 0.85, 1, 0.95)
        love.graphics.rectangle("fill", x0 + 292, y + 4, 74 * math.max(0, math.min(1, frac)), 8)
    end

    love.graphics.setColor(0.65, 0.75, 0.85)
    love.graphics.print(
        "←/→ adjust (Shift = x10)   Tab category   Bksp reset (Shift = all)",
        x0 + 12,
        y0 + h - 34
    )
    love.graphics.print("F2 save   F3 load   F4 preset   F1/Esc close", x0 + 12, y0 + h - 18)
    if panel.status then
        love.graphics.setColor(0.5, 1, 0.7)
        love.graphics.print(panel.status, x0 + 12, y0 + h + 6)
    end
end

return panel
