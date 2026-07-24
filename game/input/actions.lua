---@alias ActionName
---|"up"
---|"down"
---|"left"
---|"right"
---|"confirm"
---|"back"
---|"pause"
---|"shoot_tackle"
---|"pass_switch"
---|"sprint"
---|"lob"
---|"juke"
---|"equipment"
---|"toggle_fullscreen"
---|"toggle_mute"

---@class ActionEvent
---@field kind "action"
---@field action ActionName
---@field pressed boolean?
---@field source "keyboard"|"gamepad"?

---@class ActionsModule
local actions = {}

---@type table<string, ActionName>
local KEY_MAP = {
    up = "up",
    w = "up",
    down = "down",
    s = "down",
    left = "left",
    a = "left",
    right = "right",
    d = "right",
    ["return"] = "confirm",
    kpenter = "confirm",
    space = "confirm",
    escape = "back",
    p = "pause",
    k = "pass_switch",
    lshift = "sprint",
    rshift = "sprint",
    l = "lob",
    c = "juke",
    j = "equipment",
    f11 = "toggle_fullscreen",
    m = "toggle_mute",
}

---@type table<string, ActionName>
local GAMEPAD_MAP = {
    dpup = "up",
    dpdown = "down",
    dpleft = "left",
    dpright = "right",
    a = "confirm",
    b = "back",
    start = "pause",
    x = "pass_switch",
    y = "lob",
    leftstick = "juke",
    leftshoulder = "sprint",
}

---@param name ActionName
---@param pressed boolean?
---@param source "keyboard"|"gamepad"?
---@return ActionEvent
function actions.event(name, pressed, source)
    return {
        kind = "action",
        action = name,
        pressed = pressed == nil or pressed,
        source = source,
    }
end

---@param key string
---@param pressed boolean?
---@return ActionEvent?
function actions.from_key(key, pressed)
    local action = KEY_MAP[key]
    return action and actions.event(action, pressed, "keyboard") or nil
end

---@param button string
---@param pressed boolean?
---@param in_match boolean?
---@return ActionEvent?
function actions.from_gamepad(button, pressed, in_match)
    local action = GAMEPAD_MAP[button]
    if button == "b" and in_match then
        action = "equipment"
    end
    return action and actions.event(action, pressed, "gamepad") or nil
end

return actions
