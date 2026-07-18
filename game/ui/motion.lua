---@class UiMotionModule
local motion = {}

local REVEAL_DURATION = 0.18

---@param progress number
---@param dt number
---@return number
function motion.advance(progress, dt)
    if dt <= 0 then
        return progress
    end
    return math.min(1, progress + dt / REVEAL_DURATION)
end

---@param progress number
---@param width number
---@return number x, number remaining_width
function motion.wipe(progress, width)
    local clamped = math.max(0, math.min(1, progress))
    local eased = 1 - (1 - clamped) * (1 - clamped)
    local x = width * eased
    return x, width - x
end

return motion
