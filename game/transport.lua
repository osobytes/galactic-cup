local BrowserTransport = require("game.transport.browser")
local FakeTransport = require("game.transport.fake")

---@class TransportModule
local transport = {}

---@param options FakeTransportOptions?
---@return FakeTransport
function transport.fake(options)
    return FakeTransport.new(options)
end

---@param options BrowserTransportOptions?
---@return BrowserTransport
function transport.browser(options)
    return BrowserTransport.new(options or {})
end

return transport
