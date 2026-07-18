local contract = require("game.transport.contract")

---@class FakeTransportOptions
---@field queue_limit integer?

---@class FakeTransport: TransportAdapter
---@field _state TransportState
---@field _queue_limit integer
---@field _outbound TransportMessage[]
---@field _inbound TransportMessage[]
---@field _events TransportEvent[]
---@field _dropped_outbound integer
---@field _dropped_inbound integer
---@field _malformed integer
---@field _unsupported_version integer
---@field _overflow integer
---@field _sent integer
---@field _received integer
---@field _last_error string?
local FakeTransport = {}
FakeTransport.__index = FakeTransport

---@param options FakeTransportOptions?
---@return FakeTransport
function FakeTransport.new(options)
    options = options or {}
    local queue_limit = options.queue_limit or contract.DEFAULT_QUEUE_LIMIT
    assert(
        queue_limit == math.floor(queue_limit)
            and queue_limit > 0
            and queue_limit <= contract.MAX_QUEUE_LIMIT,
        "fake transport queue_limit is outside the supported range"
    )
    return setmetatable({
        _state = "new",
        _queue_limit = queue_limit,
        _outbound = {},
        _inbound = {},
        _events = {},
        _dropped_outbound = 0,
        _dropped_inbound = 0,
        _malformed = 0,
        _unsupported_version = 0,
        _overflow = 0,
        _sent = 0,
        _received = 0,
        _last_error = nil,
    }, FakeTransport)
end

---@param event TransportEvent
function FakeTransport:_push_event(event)
    if #self._events >= self._queue_limit then
        table.remove(self._events, 1)
        self._overflow = self._overflow + 1
        self._last_error = "fake transport event queue is full"
    end
    self._events[#self._events + 1] = event
end

---@param code TransportErrorCode
---@param message string
function FakeTransport:_record_error(code, message)
    self._last_error = message
    if code == "malformed" or code == "payload_too_large" then
        self._malformed = self._malformed + 1
    elseif code == "unsupported_version" then
        self._unsupported_version = self._unsupported_version + 1
    elseif code == "overflow" then
        self._overflow = self._overflow + 1
    end
    self:_push_event({ kind = "error", code = code, message = message })
end

---@param value TransportState
function FakeTransport:_set_state(value)
    self._state = value
    self:_push_event({ kind = "state", state = value })
end

---@return boolean?, string?, TransportErrorCode?
function FakeTransport:initialize()
    if self._state == "connected" then
        return true
    end
    self:_set_state("connected")
    return true
end

---@return boolean?, string?, TransportErrorCode?
function FakeTransport:shutdown()
    if self._state == "closed" then
        return true
    end
    self._dropped_outbound = self._dropped_outbound + #self._outbound
    self._dropped_inbound = self._dropped_inbound + #self._inbound
    self._outbound = {}
    self._inbound = {}
    self:_set_state("closed")
    return true
end

---@return boolean?, string?, TransportErrorCode?
function FakeTransport:_require_connected()
    if self._state == "new" then
        return nil, "transport is not initialized", "not_initialized"
    end
    if self._state == "closed" then
        return nil, "transport is closed", "closed"
    end
    if self._state ~= "connected" then
        return nil, "transport is not connected", "not_connected"
    end
    return true
end

function FakeTransport:_deliver()
    while #self._outbound > 0 and #self._inbound < self._queue_limit do
        self._inbound[#self._inbound + 1] = table.remove(self._outbound, 1)
    end
end

---@param message TransportMessage
---@return boolean?, string?, TransportErrorCode?
function FakeTransport:enqueue(message)
    local ok, err, code = self:_require_connected()
    if not ok then
        return nil, err, code
    end
    ok, err, code = contract.validate(message)
    if not ok then
        local error_code = code or "malformed"
        local error_message = err or "fake transport rejected a message"
        self:_record_error(error_code, error_message)
        return nil, error_message, error_code
    end
    if #self._outbound >= self._queue_limit then
        self:_record_error("overflow", "fake transport outbound queue is full")
        self._dropped_outbound = self._dropped_outbound + 1
        return nil, "fake transport outbound queue is full", "overflow"
    end
    self._outbound[#self._outbound + 1] = contract.copy(message)
    self._sent = self._sent + 1
    self:_deliver()
    return true
end

---@param message TransportMessage
---@return boolean?, string?, TransportErrorCode?
function FakeTransport:send(message)
    return self:enqueue(message)
end

---@param message TransportMessage
---@return boolean?, string?, TransportErrorCode?
function FakeTransport:inject(message)
    local ok, err, code = self:_require_connected()
    if not ok then
        return nil, err, code
    end
    ok, err, code = contract.validate(message)
    if not ok then
        local error_code = code or "malformed"
        local error_message = err or "fake transport rejected a message"
        self:_record_error(error_code, error_message)
        return nil, error_message, error_code
    end
    if #self._inbound >= self._queue_limit then
        self:_record_error("overflow", "fake transport inbound queue is full")
        self._dropped_inbound = self._dropped_inbound + 1
        return nil, "fake transport inbound queue is full", "overflow"
    end
    self._inbound[#self._inbound + 1] = contract.copy(message)
    return true
end

---@return TransportMessage?, string?, TransportErrorCode?
function FakeTransport:poll()
    local ok, err, code = self:_require_connected()
    if not ok then
        return nil, err, code
    end
    self:_deliver()
    local message = table.remove(self._inbound, 1)
    if not message then
        return nil
    end
    self._received = self._received + 1
    self:_deliver()
    return message
end

---@return TransportEvent?
function FakeTransport:poll_event()
    return table.remove(self._events, 1)
end

---@param reason string?
---@return boolean?, string?, TransportErrorCode?
function FakeTransport:disconnect(reason)
    if self._state ~= "connected" then
        return nil, "transport is not connected", "not_connected"
    end
    self:_set_state("disconnected")
    self:_record_error("disconnected", reason or "fake transport disconnected")
    return true
end

---@return TransportState
function FakeTransport:state()
    return self._state
end

---@return TransportDiagnostics
function FakeTransport:diagnostics()
    return {
        state = self._state,
        queue_limit = self._queue_limit,
        outbound_depth = #self._outbound,
        inbound_depth = #self._inbound,
        event_depth = #self._events,
        dropped_outbound = self._dropped_outbound,
        dropped_inbound = self._dropped_inbound,
        malformed = self._malformed,
        unsupported_version = self._unsupported_version,
        overflow = self._overflow,
        sent = self._sent,
        received = self._received,
        last_error = self._last_error,
    }
end

return FakeTransport
