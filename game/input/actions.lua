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
---|"toggle_fullscreen"
---|"toggle_mute"

---@class ActionEvent
---@field kind "action"
---@field action ActionName
---@field pressed boolean?

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
---@return ActionEvent
function actions.event(name)
    return { kind = "action", action = name, pressed = true }
end

---@param key string
---@return ActionEvent?
function actions.from_key(key)
    local action = KEY_MAP[key]
    return action and actions.event(action) or nil
end

---@param button string
---@return ActionEvent?
function actions.from_gamepad(button)
    local action = GAMEPAD_MAP[button]
    return action and actions.event(action) or nil
end

return actions
