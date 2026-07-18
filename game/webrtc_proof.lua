-- Pure protocol and diagnostics helpers for the OMP-0 WebRTC proof.
-- Browser APIs stay in scripts/webrtc_proof_host.js; this module is reusable by
-- a later game-facing adapter without importing love, JavaScript, or WebRTC.

---@alias WebRTCProofRole "host"|"guest"
---@alias WebRTCProofErrorCode
---| "malformed"
---| "unsupported_version"
---| "build_mismatch"
---| "role_mismatch"
---| "input_too_large"
---| "non_monotonic_tick"

---@class WebRTCHandshake
---@field kind "handshake"
---@field version integer
---@field build_id string
---@field role WebRTCProofRole

---@class WebRTCInput
---@field kind "input"
---@field version integer
---@field seq integer
---@field tick integer
---@field payload string
---@field history integer[]

---@class WebRTCProofDiagnostics
---@field started_at number
---@field sent integer
---@field received integer
---@field unique_ticks integer
---@field history_retransmits integer
---@field sequence_gaps integer
---@field out_of_order integer
---@field dropped integer
---@field queue_depth integer
---@field max_queue_depth integer
---@field rtt_samples number[]
---@field jitter_samples number[]
---@field last_received_seq integer?
---@field last_received_tick integer?
---@field seen_ticks table<integer, boolean>

---@class WebRTCProofSummary
---@field duration_s number
---@field send_rate number
---@field receive_rate number
---@field sent integer
---@field received integer
---@field unique_ticks integer
---@field history_retransmits integer
---@field sequence_gaps integer
---@field out_of_order integer
---@field dropped integer
---@field queue_depth integer
---@field max_queue_depth integer
---@field rtt_p50_ms number?
---@field rtt_p95_ms number?
---@field rtt_max_ms number?
---@field jitter_p50_ms number?
---@field jitter_p95_ms number?
---@field jitter_max_ms number?

---@class WebRTCProofModule
local proof = {}

proof.VERSION = 1
proof.MAX_HISTORY = 6
proof.MAX_INPUT_BYTES = 128

local ROLES = { host = true, guest = true }

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

---@param code WebRTCProofErrorCode
---@param message string
---@return nil, string, WebRTCProofErrorCode
local function failure(code, message)
    return nil, message, code
end

---@param values number[]
---@param fraction number
---@return number?
local function percentile(values, fraction)
    if #values == 0 then
        return nil
    end
    local sorted = {}
    for index, value in ipairs(values) do
        sorted[index] = value
    end
    table.sort(sorted)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

---@param values number[]
---@return number?
local function maximum(values)
    local result = nil
    for _, value in ipairs(values) do
        if not result or value > result then
            result = value
        end
    end
    return result
end

---@param role any
---@param build_id any
---@return WebRTCHandshake?, string?, WebRTCProofErrorCode?
function proof.new_handshake(role, build_id)
    if type(role) ~= "string" or not ROLES[role] then
        return failure("role_mismatch", "WebRTC proof role must be host or guest")
    end
    if type(build_id) ~= "string" or build_id == "" then
        return failure("malformed", "WebRTC proof build_id must be a non-empty string")
    end
    ---@cast role WebRTCProofRole
    return {
        kind = "handshake",
        version = proof.VERSION,
        build_id = build_id,
        role = role,
    }
end

---@param message any
---@param expected_version integer?
---@param expected_build_id string?
---@param expected_peer_role WebRTCProofRole?
---@return boolean?, string?, WebRTCProofErrorCode?
function proof.validate_handshake(message, expected_version, expected_build_id, expected_peer_role)
    if type(message) ~= "table" or message.kind ~= "handshake" then
        return failure("malformed", "WebRTC proof handshake is malformed")
    end
    if not is_integer(message.version) then
        return failure("malformed", "WebRTC proof handshake version must be an integer")
    end
    if message.version ~= (expected_version or proof.VERSION) then
        return failure("unsupported_version", "WebRTC proof protocol version is unsupported")
    end
    if type(message.build_id) ~= "string" or message.build_id == "" then
        return failure("malformed", "WebRTC proof handshake build_id is missing")
    end
    if expected_build_id and message.build_id ~= expected_build_id then
        return failure("build_mismatch", "WebRTC proof build identity does not match")
    end
    if type(message.role) ~= "string" or not ROLES[message.role] then
        return failure("role_mismatch", "WebRTC proof handshake role is invalid")
    end
    if expected_peer_role and message.role ~= expected_peer_role then
        return failure("role_mismatch", "WebRTC proof peer role does not match")
    end
    return true
end

---@param seq any
---@param tick any
---@param payload any
---@param history integer[]?
---@return WebRTCInput?, string?, WebRTCProofErrorCode?
function proof.new_input(seq, tick, payload, history)
    if not is_integer(seq) or seq < 0 or not is_integer(tick) or tick < 0 then
        return failure(
            "malformed",
            "WebRTC proof input sequence and tick must be non-negative integers"
        )
    end
    if type(payload) ~= "string" then
        return failure("malformed", "WebRTC proof input payload must be a string")
    end
    if #payload > proof.MAX_INPUT_BYTES then
        return failure("input_too_large", "WebRTC proof input payload exceeds 128 bytes")
    end
    history = history or {}
    if type(history) ~= "table" or #history > proof.MAX_HISTORY then
        return failure("malformed", "WebRTC proof input history exceeds six ticks")
    end
    for _, history_tick in ipairs(history) do
        if not is_integer(history_tick) or history_tick < 0 or history_tick >= tick then
            return failure("malformed", "WebRTC proof input history must contain earlier ticks")
        end
    end
    return {
        kind = "input",
        version = proof.VERSION,
        seq = seq,
        tick = tick,
        payload = payload,
        history = history,
    }
end

---@param message any
---@return boolean?, string?, WebRTCProofErrorCode?
function proof.validate_input(message)
    if type(message) ~= "table" or message.kind ~= "input" then
        return failure("malformed", "WebRTC proof input is malformed")
    end
    if message.version ~= proof.VERSION then
        return failure("unsupported_version", "WebRTC proof input version is unsupported")
    end
    local input, err, code =
        proof.new_input(message.seq, message.tick, message.payload, message.history)
    if not input then
        return nil, err, code
    end
    return input ~= nil
end

---@param now number
---@return WebRTCProofDiagnostics
function proof.new_diagnostics(now)
    return {
        started_at = now,
        sent = 0,
        received = 0,
        unique_ticks = 0,
        history_retransmits = 0,
        sequence_gaps = 0,
        out_of_order = 0,
        dropped = 0,
        queue_depth = 0,
        max_queue_depth = 0,
        rtt_samples = {},
        jitter_samples = {},
        last_received_seq = nil,
        last_received_tick = nil,
        seen_ticks = {},
    }
end

---@param diagnostics WebRTCProofDiagnostics
---@param now number
---@param queue_depth integer
function proof.record_sent(diagnostics, now, queue_depth)
    local _ = now
    diagnostics.sent = diagnostics.sent + 1
    diagnostics.queue_depth = queue_depth
    diagnostics.max_queue_depth = math.max(diagnostics.max_queue_depth, queue_depth)
end

---@param diagnostics WebRTCProofDiagnostics
---@param now number
---@param input WebRTCInput
function proof.record_received(diagnostics, now, input)
    local _ = now
    diagnostics.received = diagnostics.received + 1
    if diagnostics.last_received_seq then
        if input.seq > diagnostics.last_received_seq + 1 then
            diagnostics.sequence_gaps = diagnostics.sequence_gaps
                + input.seq
                - diagnostics.last_received_seq
                - 1
        elseif input.seq <= diagnostics.last_received_seq then
            diagnostics.out_of_order = diagnostics.out_of_order + 1
        end
    end
    local history = input.history or {}
    for _, history_tick in ipairs(history) do
        if not diagnostics.seen_ticks[history_tick] then
            diagnostics.seen_ticks[history_tick] = true
            diagnostics.unique_ticks = diagnostics.unique_ticks + 1
            diagnostics.history_retransmits = diagnostics.history_retransmits + 1
        end
    end
    if not diagnostics.seen_ticks[input.tick] then
        diagnostics.seen_ticks[input.tick] = true
        diagnostics.unique_ticks = diagnostics.unique_ticks + 1
    end
    diagnostics.last_received_seq = math.max(diagnostics.last_received_seq or input.seq, input.seq)
    diagnostics.last_received_tick =
        math.max(diagnostics.last_received_tick or input.tick, input.tick)
end

---@param diagnostics WebRTCProofDiagnostics
---@param rtt_ms number
function proof.record_rtt(diagnostics, rtt_ms)
    if rtt_ms < 0 then
        return
    end
    local previous = diagnostics.rtt_samples[#diagnostics.rtt_samples]
    diagnostics.rtt_samples[#diagnostics.rtt_samples + 1] = rtt_ms
    if previous then
        diagnostics.jitter_samples[#diagnostics.jitter_samples + 1] = math.abs(rtt_ms - previous)
    end
end

---@param diagnostics WebRTCProofDiagnostics
---@param now number
---@return WebRTCProofSummary
function proof.summary(diagnostics, now)
    local duration = math.max(0, now - diagnostics.started_at)
    return {
        duration_s = duration,
        send_rate = diagnostics.sent / math.max(duration, 0.001),
        receive_rate = diagnostics.received / math.max(duration, 0.001),
        sent = diagnostics.sent,
        received = diagnostics.received,
        unique_ticks = diagnostics.unique_ticks,
        history_retransmits = diagnostics.history_retransmits,
        sequence_gaps = diagnostics.sequence_gaps,
        out_of_order = diagnostics.out_of_order,
        dropped = diagnostics.dropped,
        queue_depth = diagnostics.queue_depth,
        max_queue_depth = diagnostics.max_queue_depth,
        rtt_p50_ms = percentile(diagnostics.rtt_samples, 0.50),
        rtt_p95_ms = percentile(diagnostics.rtt_samples, 0.95),
        rtt_max_ms = maximum(diagnostics.rtt_samples),
        jitter_p50_ms = percentile(diagnostics.jitter_samples, 0.50),
        jitter_p95_ms = percentile(diagnostics.jitter_samples, 0.95),
        jitter_max_ms = maximum(diagnostics.jitter_samples),
    }
end

return proof
