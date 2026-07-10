-- Impure rendering of a layout. This is the ONLY UI file that calls love.graphics.
-- Screens build a pure Layout; this turns it into pixels.

---@class FormationPreviewData
---@field keeper Anchor
---@field outfield Anchor[]

local draw = {}

local COLORS = {
    panel = { 0.10, 0.14, 0.22 },
    panel_line = { 0.25, 0.55, 0.8 },
    button = { 0.14, 0.20, 0.32 },
    button_sel = { 0.2, 0.55, 0.85 },
    text = { 0.9, 0.95, 1.0 },
    title = { 0.6, 0.85, 1.0 },
    accent = { 1.0, 0.6, 0.3 },
    pitch = { 0.06, 0.18, 0.18 },
    keeper = { 0.75, 0.85, 1.0 },
}

local PREVIEW_INSET = 6
local PREVIEW_DOT_RADIUS = 3

---@param c number[]
---@param a number?
local function set(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

---@param w Widget
local function draw_button(w)
    set(w.selected and COLORS.button_sel or COLORS.button)
    love.graphics.rectangle("fill", w.rect.x, w.rect.y, w.rect.w, w.rect.h, 6, 6)
    set(COLORS.panel_line, 0.8)
    love.graphics.rectangle("line", w.rect.x, w.rect.y, w.rect.w, w.rect.h, 6, 6)
    if w.text then
        set(COLORS.text)
        love.graphics.printf(w.text, w.rect.x, w.rect.y + w.rect.h / 2 - 7, w.rect.w, "center")
    end
end

---@param w Widget
local function draw_card(w)
    set(COLORS.panel)
    love.graphics.rectangle("fill", w.rect.x, w.rect.y, w.rect.w, w.rect.h, 6, 6)
    set(COLORS.panel_line, 0.5)
    love.graphics.rectangle("line", w.rect.x, w.rect.y, w.rect.w, w.rect.h, 6, 6)
    if w.text then
        set(COLORS.text)
        love.graphics.printf(w.text, w.rect.x + 12, w.rect.y + 10, w.rect.w - 24, "left")
    end
end

---@param w Widget
local function draw_label(w)
    set(w.kind == "title" and COLORS.title or COLORS.text)
    local align = w.data and w.data.align or "left"
    love.graphics.printf(w.text or "", w.rect.x, w.rect.y, w.rect.w, align)
end

---@param rect Rect
---@param anchor Anchor
---@return number x, number y
local function anchor_position(rect, anchor)
    local inner_w = rect.w - PREVIEW_INSET * 2
    local inner_h = rect.h - PREVIEW_INSET * 2
    return rect.x + PREVIEW_INSET + anchor.x * inner_w, rect.y + PREVIEW_INSET + anchor.y * inner_h
end

---@param w Widget
local function draw_formation_preview(w)
    ---@type FormationPreviewData
    local data = w.data

    set(w.selected and COLORS.button_sel or COLORS.button)
    love.graphics.rectangle("fill", w.rect.x, w.rect.y, w.rect.w, w.rect.h, 6, 6)
    set(COLORS.panel_line, w.selected and 1 or 0.8)
    love.graphics.rectangle("line", w.rect.x, w.rect.y, w.rect.w, w.rect.h, 6, 6)

    local pitch = {
        x = w.rect.x + PREVIEW_INSET,
        y = w.rect.y + PREVIEW_INSET,
        w = w.rect.w - PREVIEW_INSET * 2,
        h = w.rect.h - PREVIEW_INSET * 2,
    }
    set(COLORS.pitch)
    love.graphics.rectangle("fill", pitch.x, pitch.y, pitch.w, pitch.h, 3, 3)
    set(COLORS.panel_line, 0.55)
    love.graphics.rectangle("line", pitch.x, pitch.y, pitch.w, pitch.h, 3, 3)
    love.graphics.line(pitch.x + pitch.w / 2, pitch.y, pitch.x + pitch.w / 2, pitch.y + pitch.h)

    local keeper_x, keeper_y = anchor_position(w.rect, data.keeper)
    set(COLORS.keeper)
    love.graphics.circle("fill", keeper_x, keeper_y, PREVIEW_DOT_RADIUS)

    set(COLORS.accent)
    for _, anchor in ipairs(data.outfield) do
        local x, y = anchor_position(w.rect, anchor)
        love.graphics.circle("fill", x, y, PREVIEW_DOT_RADIUS)
    end
end

-- Render an entire layout over a starfield-ish backdrop.
---@param layout Layout
function draw.layout(layout)
    local gw, gh = love.graphics.getDimensions()
    love.graphics.setColor(0.04, 0.05, 0.10)
    love.graphics.rectangle("fill", 0, 0, gw, gh)

    for _, w in ipairs(layout) do
        if w.kind == "button" then
            draw_button(w)
        elseif w.kind == "card" then
            draw_card(w)
        elseif w.kind == "formation_preview" then
            draw_formation_preview(w)
        else
            draw_label(w)
        end
    end
end

return draw
