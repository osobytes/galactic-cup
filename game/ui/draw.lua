-- Impure rendering of pure UI layouts. Screens own state and layout; this file
-- owns the shared product look and the only love.graphics calls in non-match UI.

local theme = require("game.ui.theme")
local motion = require("game.ui.motion")
local viewport_model = require("game.ui.viewport")

---@class FormationPreviewData
---@field keeper Anchor
---@field outfield Anchor[]
---@field markers FormationMarkerData[]?

---@class FormationMarkerData
---@field color number[]
---@field shape string?
---@field name string

---@class UiDrawModule
local draw = {}

local COLORS = theme.colors
local PREVIEW_INSET = 7
local PREVIEW_DOT_RADIUS = 4
local STAR_POINTS = {
    { 0.06, 0.12, 1 },
    { 0.13, 0.78, 1 },
    { 0.21, 0.28, 2 },
    { 0.28, 0.9, 1 },
    { 0.36, 0.16, 1 },
    { 0.44, 0.72, 1 },
    { 0.52, 0.08, 2 },
    { 0.61, 0.86, 1 },
    { 0.68, 0.23, 1 },
    { 0.75, 0.67, 2 },
    { 0.84, 0.14, 1 },
    { 0.91, 0.82, 1 },
    { 0.96, 0.38, 1 },
}

---@type table<string, any>
local fonts = {}

---@param color number[]
---@param alpha number?
local function set_color(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
end

---@param kind string
local function set_font(kind)
    if love.graphics.newFont and love.graphics.setFont then
        if not fonts[kind] then
            fonts[kind] = love.graphics.newFont(theme.fonts[kind] or theme.fonts.body)
        end
        love.graphics.setFont(fonts[kind])
    end
end

---@param rect Rect
---@param color number[]
---@param alpha number?
local function panel_fill(rect, color, alpha)
    set_color(color, alpha)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, theme.radius, theme.radius)
end

---@param rect Rect
---@param color number[]
---@param alpha number?
---@param width number?
local function panel_line(rect, color, alpha, width)
    love.graphics.setLineWidth(width or theme.border_width)
    set_color(color, alpha)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, theme.radius, theme.radius)
end

---@param widget Widget
local function draw_focus(widget)
    if widget.focused then
        panel_line(widget.rect, COLORS.cyan, 1, theme.focus_width)
        set_color(COLORS.cyan, 0.95)
        love.graphics.polygon(
            "fill",
            widget.rect.x - 10,
            widget.rect.y + widget.rect.h / 2,
            widget.rect.x - 4,
            widget.rect.y + widget.rect.h / 2 - 5,
            widget.rect.x - 4,
            widget.rect.y + widget.rect.h / 2 + 5
        )
    end
end

---@param widget Widget
local function draw_button(widget)
    local disabled = widget.data and widget.data.disabled
    local fill = widget.selected and COLORS.panel_selected or COLORS.panel_raised
    if disabled then
        fill = COLORS.disabled
    elseif widget.focused then
        fill = COLORS.panel_selected
    end
    panel_fill(widget.rect, fill, disabled and 0.6 or 1)
    panel_line(
        widget.rect,
        widget.focused and COLORS.cyan or COLORS.border,
        disabled and 0.35 or 0.8
    )
    draw_focus(widget)

    if widget.text then
        set_font("body")
        set_color(disabled and COLORS.text_muted or COLORS.text, disabled and 0.55 or 1)
        local align = widget.data and widget.data.align or "center"
        local inset = align == "left" and 16 or 0
        local text_y = widget.rect.h > 50 and widget.rect.y + 10
            or widget.rect.y + widget.rect.h / 2 - 7
        love.graphics.printf(
            widget.text,
            widget.rect.x + inset,
            text_y,
            widget.rect.w - inset * 2,
            align
        )
    end
end

---@param shape string?
---@param x number
---@param y number
---@param color number[]
---@param size number?
local function draw_species_mark(shape, x, y, color, size)
    size = size or 8
    set_color(color)
    if shape == "broad" then
        love.graphics.rectangle("fill", x - size, y - size * 0.75, size * 2, size * 1.5, 3, 3)
    elseif shape == "angular" then
        love.graphics.polygon(
            "fill",
            x,
            y - size * 1.1,
            x + size,
            y + size * 0.9,
            x - size,
            y + size * 0.9
        )
    elseif shape == "cluster" then
        love.graphics.circle("fill", x - size * 0.55, y + size * 0.35, size * 0.55)
        love.graphics.circle("fill", x + size * 0.55, y + size * 0.35, size * 0.55)
        love.graphics.circle("fill", x, y - size * 0.55, size * 0.55)
    else
        love.graphics.circle("fill", x, y, size)
    end
end

---@param widget Widget
local function draw_card(widget)
    local data = widget.data or {}
    local accent = data.accent or COLORS.border
    local fill = widget.selected and COLORS.panel_selected or COLORS.panel
    panel_fill(widget.rect, fill)
    panel_line(widget.rect, widget.focused and COLORS.cyan or COLORS.border_soft, 0.9)
    set_color(accent)
    love.graphics.rectangle(
        "fill",
        widget.rect.x,
        widget.rect.y,
        5,
        widget.rect.h,
        theme.radius,
        theme.radius
    )

    local text_inset = 14
    if data.species_shape then
        draw_species_mark(data.species_shape, widget.rect.x + 24, widget.rect.y + 24, accent)
        text_inset = 44
    end
    if data.locked then
        set_font("eyebrow")
        set_color(COLORS.amber)
        love.graphics.printf(
            "LOCKED",
            widget.rect.x + widget.rect.w - 70,
            widget.rect.y + 9,
            56,
            "right"
        )
    end
    if widget.selected then
        set_color(COLORS.cyan)
        love.graphics.circle(
            "fill",
            widget.rect.x + widget.rect.w - 13,
            widget.rect.y + widget.rect.h - 13,
            4
        )
    end
    if widget.text then
        set_font("body")
        set_color(COLORS.text)
        love.graphics.printf(
            widget.text,
            widget.rect.x + text_inset,
            widget.rect.y + 10,
            widget.rect.w - text_inset - 12,
            data.align or "left"
        )
    end
    draw_focus(widget)
end

---@param widget Widget
local function draw_label(widget)
    local data = widget.data or {}
    local font_kind = "body"
    local color = COLORS.text
    if widget.kind == "hero_title" then
        font_kind = "hero"
        color = COLORS.text
    elseif widget.kind == "title" then
        font_kind = "title"
        color = COLORS.text
    elseif widget.kind == "eyebrow" then
        font_kind = "eyebrow"
        color = COLORS.cyan
    elseif data.tone == "muted" then
        color = COLORS.text_muted
    end

    set_font(font_kind)
    if widget.kind == "hero_title" then
        set_color(COLORS.cyan, 0.22)
        love.graphics.printf(
            widget.text or "",
            widget.rect.x + 2,
            widget.rect.y + 3,
            widget.rect.w,
            data.align or "left"
        )
    end
    set_color(color)
    love.graphics.printf(
        widget.text or "",
        widget.rect.x,
        widget.rect.y,
        widget.rect.w,
        data.align or "left"
    )
end

---@param rect Rect
---@param anchor Anchor
---@return number x, number y
local function anchor_position(rect, anchor)
    local inner_w = rect.w - PREVIEW_INSET * 2
    local inner_h = rect.h - PREVIEW_INSET * 2
    return rect.x + PREVIEW_INSET + anchor.x * inner_w, rect.y + PREVIEW_INSET + anchor.y * inner_h
end

---@param widget Widget
local function draw_formation_preview(widget)
    ---@type FormationPreviewData
    local data = widget.data
    panel_fill(widget.rect, widget.selected and COLORS.panel_selected or COLORS.panel_raised)
    panel_line(widget.rect, widget.selected and COLORS.cyan or COLORS.border, 0.85)

    local pitch = {
        x = widget.rect.x + PREVIEW_INSET,
        y = widget.rect.y + PREVIEW_INSET,
        w = widget.rect.w - PREVIEW_INSET * 2,
        h = widget.rect.h - PREVIEW_INSET * 2,
    }
    set_color(COLORS.pitch)
    love.graphics.rectangle("fill", pitch.x, pitch.y, pitch.w, pitch.h, 3, 3)
    set_color(COLORS.border, 0.55)
    love.graphics.rectangle("line", pitch.x, pitch.y, pitch.w, pitch.h, 3, 3)
    love.graphics.line(pitch.x + pitch.w / 2, pitch.y, pitch.x + pitch.w / 2, pitch.y + pitch.h)

    local markers = data.markers or {}
    local keeper_x, keeper_y = anchor_position(widget.rect, data.keeper)
    local keeper_marker = markers[1]
    draw_species_mark(
        keeper_marker and keeper_marker.shape or "round",
        keeper_x,
        keeper_y,
        keeper_marker and keeper_marker.color or COLORS.keeper,
        PREVIEW_DOT_RADIUS
    )

    for i, anchor in ipairs(data.outfield) do
        local x, y = anchor_position(widget.rect, anchor)
        local marker = markers[i + 1]
        draw_species_mark(
            marker and marker.shape or "round",
            x,
            y,
            marker and marker.color or COLORS.amber,
            PREVIEW_DOT_RADIUS
        )
    end
end

---@param width number
---@param height number
local function draw_backdrop(width, height)
    set_color(COLORS.space)
    love.graphics.rectangle("fill", 0, 0, width, height)
    set_color(COLORS.nebula, 0.22)
    love.graphics.ellipse("fill", width * 0.16, height * 0.18, width * 0.34, height * 0.22)
    love.graphics.ellipse("fill", width * 0.86, height * 0.82, width * 0.28, height * 0.2)
    for _, star in ipairs(STAR_POINTS) do
        set_color(star[3] == 2 and COLORS.cyan or COLORS.text, star[3] == 2 and 0.7 or 0.38)
        love.graphics.circle("fill", star[1] * width, star[2] * height, star[3])
    end
    set_color(COLORS.border_soft, 0.25)
    love.graphics.line(0, height - 20, width, height - 20)
end

-- Render a layout into its virtual viewport, letterboxed into the current window.
---@param layout Layout
---@param viewport { w: number, h: number }?
---@param transition number?
function draw.layout(layout, viewport, transition)
    local actual_w, actual_h = love.graphics.getDimensions()
    local base = viewport or { w = 960, h = 540 }
    local transform = viewport_model.new(actual_w, actual_h, base.w, base.h)
    local can_transform = love.graphics.push
        and love.graphics.pop
        and love.graphics.translate
        and love.graphics.scale

    set_color(COLORS.void)
    love.graphics.rectangle("fill", 0, 0, actual_w, actual_h)
    if can_transform then
        love.graphics.push()
        love.graphics.translate(transform.offset_x, transform.offset_y)
        love.graphics.scale(transform.scale, transform.scale)
    end

    draw_backdrop(base.w, base.h)
    for _, widget in ipairs(layout) do
        if widget.kind == "button" then
            draw_button(widget)
        elseif widget.kind == "card" then
            draw_card(widget)
        elseif widget.kind == "formation_preview" then
            draw_formation_preview(widget)
        else
            draw_label(widget)
        end
    end
    if transition and transition < 1 then
        local wipe_x, wipe_w = motion.wipe(transition, base.w)
        set_color(COLORS.void, 0.96)
        love.graphics.rectangle("fill", wipe_x, 0, wipe_w, base.h)
        set_color(COLORS.cyan, 0.75)
        love.graphics.rectangle("fill", wipe_x - 2, 0, 2, base.h)
    end

    if can_transform then
        love.graphics.pop()
    end
end

return draw
