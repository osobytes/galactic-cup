-- Pure 2.5D projection. Maps a point on the flat pitch (world space) to a screen
-- point plus a depth scale, producing a perspective trapezoid: the far edge
-- (world y = 0) is higher and narrower, the near edge (world y = field.h) is
-- lower and wider. No love calls — so the projection is unit-testable.

local camera = {}

---@class CameraConfig
---@field far_scale number  -- sprite/spread scale at the far edge
---@field near_scale number  -- sprite/spread scale at the near edge
---@field horizon_frac number  -- screen-height fraction where the far edge sits
---@field bottom_frac number  -- screen-height fraction where the near edge sits

---@type CameraConfig
camera.DEFAULTS = {
    far_scale = 0.62,
    near_scale = 1.25,
    horizon_frac = 0.20,
    bottom_frac = 0.94,
}

-- Project a world point onto the screen.
---@param wx number
---@param wy number
---@param field { w: number, h: number }
---@param vp { w: number, h: number }
---@param cfg CameraConfig?
---@return number sx
---@return number sy
---@return number scale
function camera.project(wx, wy, field, vp, cfg)
    cfg = cfg or camera.DEFAULTS
    local t = wy / field.h -- 0 = far, 1 = near
    local scale = cfg.far_scale + (cfg.near_scale - cfg.far_scale) * t
    local horizon = vp.h * cfg.horizon_frac
    local bottom = vp.h * cfg.bottom_frac
    local sy = horizon + (bottom - horizon) * t
    local sx = vp.w / 2 + (wx - field.w / 2) * scale * (vp.w / field.w)
    return sx, sy, scale
end

return camera
