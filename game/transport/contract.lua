---@alias TransportMessageType "input"|"event"|"state"
---@alias TransportState "new"|"connected"|"disconnected"|"closed"|"error"
---@alias TransportErrorCode
---| "not_initialized"
---| "not_connected"
---| "closed"
---| "malformed"
---| "unsupported_version"
---| "payload_too_large"
---| "overflow"
---| "bridge_unavailable"
---| "bridge_error"
---| "disconnected"

---@class TransportMessage
---@field version integer
---@field type TransportMessageType
---@field seq integer -- Monotonic transport sequence, starting at zero.
---@field tick integer? -- Required for input messages; omitted for control messages.
---@field payload string -- UTF-8 payload owned by the next protocol layer.

---@class TransportMessageOptions
---@field version integer?
---@field type TransportMessageType
---@field seq integer
---@field tick integer?
---@field payload string

---@class TransportEvent
---@field kind "state"|"error"
---@field state TransportState?
---@field code TransportErrorCode?
---@field message string?

---@class TransportDiagnostics
---@field state TransportState
---@field queue_limit integer
---@field outbound_depth integer
---@field inbound_depth integer
---@field event_depth integer
---@field dropped_outbound integer
---@field dropped_inbound integer
---@field malformed integer
---@field unsupported_version integer
---@field overflow integer
---@field sent integer
---@field received integer
---@field last_error string?

---@class TransportAdapter
---@field initialize fun(self: TransportAdapter): boolean?, string?, TransportErrorCode?
---@field shutdown fun(self: TransportAdapter): boolean?, string?, TransportErrorCode?
---@field enqueue fun(self: TransportAdapter, message: TransportMessage): boolean?, string?, TransportErrorCode?
---@field send fun(self: TransportAdapter, message: TransportMessage): boolean?, string?, TransportErrorCode?
---@field poll fun(self: TransportAdapter): TransportMessage?, string?, TransportErrorCode?
---@field poll_event fun(self: TransportAdapter): TransportEvent?
---@field state fun(self: TransportAdapter): TransportState
---@field diagnostics fun(self: TransportAdapter): TransportDiagnostics

---@class TransportContractModule
local contract = {}

contract.VERSION = 1
contract.DEFAULT_QUEUE_LIMIT = 64
contract.MAX_QUEUE_LIMIT = 256
contract.MAX_PAYLOAD_BYTES = 1024

local MESSAGE_TYPES = {
    input = true,
    event = true,
    state = true,
}

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

---@param code TransportErrorCode
---@param message string
---@return nil, string, TransportErrorCode
local function failure(code, message)
    return nil, message, code
end

---@param message any
---@return boolean?, string?, TransportErrorCode?
function contract.validate(message)
    if type(message) ~= "table" then
        return failure("malformed", "transport message must be a table")
    end
    if not is_integer(message.version) then
        return failure("malformed", "transport message version must be an integer")
    end
    if message.version ~= contract.VERSION then
        return failure("unsupported_version", "unsupported transport message version")
    end
    if type(message.type) ~= "string" or not MESSAGE_TYPES[message.type] then
        return failure("malformed", "transport message type is invalid")
    end
    if not is_integer(message.seq) or message.seq < 0 then
        return failure("malformed", "transport message seq must be a non-negative integer")
    end
    if message.type == "input" then
        if not is_integer(message.tick) or message.tick < 0 then
            return failure("malformed", "input message tick must be a non-negative integer")
        end
    elseif message.tick ~= nil and (not is_integer(message.tick) or message.tick < 0) then
        return failure("malformed", "transport message tick must be a non-negative integer")
    end
    if type(message.payload) ~= "string" then
        return failure("malformed", "transport message payload must be a string")
    end
    if #message.payload > contract.MAX_PAYLOAD_BYTES then
        return failure("payload_too_large", "transport message payload exceeds the byte limit")
    end
    return true
end

---@param options TransportMessageOptions
---@return TransportMessage?, string?, TransportErrorCode?
function contract.new(options)
    local message = {
        version = options.version or contract.VERSION,
        type = options.type,
        seq = options.seq,
        tick = options.tick,
        payload = options.payload,
    }
    local ok, err, code = contract.validate(message)
    if not ok then
        return nil, err, code
    end
    return message
end

---@param message TransportMessage
---@return TransportMessage
function contract.copy(message)
    local ok, err = contract.validate(message)
    assert(ok, err)
    return {
        version = message.version,
        type = message.type,
        seq = message.seq,
        tick = message.tick,
        payload = message.payload,
    }
end

---@param value string
---@return string
local function escape(value)
    return (
        value:gsub("([^%w%-%._~])", function(character)
            return ("%%%02X"):format(string.byte(character))
        end)
    )
end

---@param value string
---@return string?, string?
local function unescape(value)
    local result = {}
    local index = 1
    while index <= #value do
        local character = value:sub(index, index)
        if character == "%" then
            local hex = value:sub(index + 1, index + 2)
            if #hex ~= 2 or not hex:match("^%x%x$") then
                return nil, "transport wire field has an invalid escape"
            end
            result[#result + 1] = string.char(tonumber(hex, 16))
            index = index + 3
        else
            result[#result + 1] = character
            index = index + 1
        end
    end
    return table.concat(result)
end

---@param value string
---@return integer
local function parse_integer(value)
    local number = assert(tonumber(value))
    ---@cast number integer
    return number
end

---@param message TransportMessage
---@return string?, string?, TransportErrorCode?
function contract.encode(message)
    local ok, err, code = contract.validate(message)
    if not ok then
        return nil, err, code
    end
    return table.concat({
        tostring(message.version),
        escape(message.type),
        tostring(message.seq),
        message.tick and tostring(message.tick) or "",
        escape(message.payload),
    }, "|")
end

---@param wire string
---@return TransportMessage?, string?, TransportErrorCode?
function contract.decode(wire)
    if type(wire) ~= "string" then
        return failure("malformed", "transport wire message must be a string")
    end
    local raw_version, raw_type, raw_seq, raw_tick, raw_payload =
        wire:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if not raw_version then
        return failure("malformed", "transport wire message has invalid fields")
    end
    if not raw_version:match("^%d+$") or not raw_seq:match("^%d+$") then
        return failure("malformed", "transport wire message numbers are invalid")
    end
    if raw_tick ~= "" and not raw_tick:match("^%d+$") then
        return failure("malformed", "transport wire message tick is invalid")
    end
    local message_type, type_err = unescape(raw_type)
    local payload, payload_err = unescape(raw_payload)
    if not message_type or not payload then
        return failure("malformed", type_err or payload_err or "transport wire escape is invalid")
    end
    return contract.new({
        version = parse_integer(raw_version),
        type = message_type,
        seq = parse_integer(raw_seq),
        tick = raw_tick == "" and nil or parse_integer(raw_tick),
        payload = payload,
    })
end

return contract
