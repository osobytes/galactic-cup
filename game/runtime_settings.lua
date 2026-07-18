local audio = require("game.audio")
local bloom = require("game.render.bloom")

---@class RuntimeSettingsModule
local runtime_settings = {}

---@param settings GameSettings
function runtime_settings.apply(settings)
    bloom.config.enabled = settings.bloom
    audio.configure(settings)

    if love.audio and love.audio.setVolume then
        love.audio.setVolume(settings.master_volume)
    end
    if love.window and love.window.getFullscreen and love.window.setFullscreen then
        local fullscreen = love.window.getFullscreen()
        if fullscreen ~= settings.fullscreen then
            love.window.setFullscreen(settings.fullscreen, "desktop")
        end
    end
end

return runtime_settings
