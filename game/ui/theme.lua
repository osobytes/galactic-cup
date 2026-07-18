---@class UiTheme
---@field colors table<string, number[]>
---@field radius number
---@field border_width number
---@field focus_width number
---@field fonts table<string, integer>

---@type UiTheme
return {
    colors = {
        void = { 0.015, 0.022, 0.055 },
        space = { 0.035, 0.052, 0.11 },
        nebula = { 0.12, 0.09, 0.24 },
        panel = { 0.065, 0.095, 0.17 },
        panel_raised = { 0.09, 0.135, 0.23 },
        panel_selected = { 0.105, 0.255, 0.39 },
        border = { 0.18, 0.43, 0.62 },
        border_soft = { 0.12, 0.27, 0.4 },
        cyan = { 0.25, 0.88, 1.0 },
        amber = { 1.0, 0.66, 0.24 },
        text = { 0.91, 0.96, 1.0 },
        text_muted = { 0.55, 0.67, 0.78 },
        text_dark = { 0.025, 0.055, 0.08 },
        disabled = { 0.22, 0.28, 0.34 },
        pitch = { 0.025, 0.16, 0.17 },
        keeper = { 0.78, 0.9, 1.0 },
    },
    radius = 6,
    border_width = 1,
    focus_width = 2,
    fonts = {
        body = 13,
        eyebrow = 11,
        title = 24,
        hero = 38,
    },
}
