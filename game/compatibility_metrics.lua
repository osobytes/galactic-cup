-- Lightweight runtime measurements shared by native and browser runs.
-- Samples are emitted as pipe-delimited console lines so a browser console
-- export and a native stdout capture can be compared without a transport
-- bridge or a browser-specific dependency in the simulation layers.

---@class CompatibilityPendingInput
---@field at number
---@field kind string
---@field sequence integer

---@class CompatibilityMetrics
---@field started_at number
---@field warmup_seconds number
---@field sample_seconds number
---@field sample_started_at number?
---@field sample_number integer
---@field update_samples number[]
---@field draw_samples number[]
---@field frame_samples number[]
---@field input_samples number[]
---@field pending_inputs CompatibilityPendingInput[]
---@field last_frame_at number?
---@field update_started_at number?
---@field draw_started_at number?
---@field input_sequence integer
---@field flow_finished boolean
---@field begin_update fun(self: CompatibilityMetrics, now: number)
---@field finish_update fun(self: CompatibilityMetrics, now: number)
---@field begin_draw fun(self: CompatibilityMetrics, now: number)
---@field finish_draw fun(self: CompatibilityMetrics, now: number)
---@field input fun(self: CompatibilityMetrics, now: number, kind: string)
---@field route fun(self: CompatibilityMetrics, now: number, route: string)
---@field lifecycle fun(self: CompatibilityMetrics, now: number, event: string)
---@field settings fun(self: CompatibilityMetrics, now: number, settings: GameSettings)
---@field flow_complete fun(self: CompatibilityMetrics, now: number, route: string)
---@field finish fun(self: CompatibilityMetrics, now: number)

---@class CompatibilityMetricsModule
local compatibility_metrics = {}
compatibility_metrics.__index = compatibility_metrics

local WARMUP_SECONDS = 10
local SAMPLE_SECONDS = 60

---@param kind string
---@param fields table<string, string|number|boolean>
local function emit(kind, fields)
    local parts = { "GC_METRICS", kind }
    local keys = {}
    for key in pairs(fields) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = key .. "=" .. tostring(fields[key])
    end
    print(table.concat(parts, "|"))
end

---@param values number[]
---@return number[]
local function sorted_copy(values)
    local copy = {}
    for i, value in ipairs(values) do
        copy[i] = value
    end
    table.sort(copy)
    return copy
end

---@param values number[]
---@param fraction number
---@return number?
local function percentile(values, fraction)
    if #values == 0 then
        return nil
    end
    local sorted = sorted_copy(values)
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

---@param value number?
---@return string
local function metric_value(value)
    return value and ("%.3f"):format(value) or "na"
end

---@param self CompatibilityMetrics
local function clear_sample(self)
    self.update_samples = {}
    self.draw_samples = {}
    self.frame_samples = {}
    self.input_samples = {}
end

---@param self CompatibilityMetrics
---@param now number
---@param partial boolean
local function emit_sample(self, now, partial)
    local started_at = assert(self.sample_started_at)
    local frame_over_33 = 0
    local frame_over_250 = 0
    for _, interval in ipairs(self.frame_samples) do
        if interval > 33 then
            frame_over_33 = frame_over_33 + 1
        end
        if interval > 250 then
            frame_over_250 = frame_over_250 + 1
        end
    end
    emit("sample", {
        draw_max_ms = metric_value(maximum(self.draw_samples)),
        draw_p50_ms = metric_value(percentile(self.draw_samples, 0.50)),
        draw_p95_ms = metric_value(percentile(self.draw_samples, 0.95)),
        duration_s = ("%.3f"):format(now - started_at),
        frame_over_250_ms = frame_over_250,
        frame_over_33_ms = frame_over_33,
        frame_p50_ms = metric_value(percentile(self.frame_samples, 0.50)),
        frame_p95_ms = metric_value(percentile(self.frame_samples, 0.95)),
        frames = #self.frame_samples,
        input_max_ms = metric_value(maximum(self.input_samples)),
        input_p50_ms = metric_value(percentile(self.input_samples, 0.50)),
        input_p95_ms = metric_value(percentile(self.input_samples, 0.95)),
        partial = partial,
        sample = self.sample_number,
        update_max_ms = metric_value(maximum(self.update_samples)),
        update_p50_ms = metric_value(percentile(self.update_samples, 0.50)),
        update_p95_ms = metric_value(percentile(self.update_samples, 0.95)),
        updates = #self.update_samples,
    })
end

---@param self CompatibilityMetrics
---@param now number
local function advance_sample(self, now)
    if not self.sample_started_at then
        if now - self.started_at < self.warmup_seconds then
            return
        end
        self.sample_started_at = now
        self.sample_number = 1
        emit("sample_start", { sample = self.sample_number })
        return
    end

    if now - self.sample_started_at >= self.sample_seconds then
        emit_sample(self, now, false)
        self.sample_number = self.sample_number + 1
        self.sample_started_at = now
        clear_sample(self)
        emit("sample_start", { sample = self.sample_number })
    end
end

---@param now number
---@return CompatibilityMetrics
function compatibility_metrics.new(now)
    local self = {
        started_at = now,
        warmup_seconds = WARMUP_SECONDS,
        sample_seconds = SAMPLE_SECONDS,
        sample_started_at = nil,
        sample_number = 0,
        update_samples = {},
        draw_samples = {},
        frame_samples = {},
        input_samples = {},
        pending_inputs = {},
        last_frame_at = nil,
        update_started_at = nil,
        draw_started_at = nil,
        input_sequence = 0,
        flow_finished = false,
    }
    emit("boot", { at_ms = 0 })
    local result = setmetatable(self, compatibility_metrics)
    ---@cast result CompatibilityMetrics
    return result
end

---@param self CompatibilityMetrics
---@param now number
function compatibility_metrics.begin_update(self, now)
    advance_sample(self, now)
    if
        self.last_frame_at
        and self.sample_started_at
        and self.last_frame_at >= self.sample_started_at
    then
        self.frame_samples[#self.frame_samples + 1] = (now - self.last_frame_at) * 1000
    end
    self.last_frame_at = now
    self.update_started_at = now
end

---@param self CompatibilityMetrics
---@param now number
function compatibility_metrics.finish_update(self, now)
    advance_sample(self, now)
    if
        self.update_started_at
        and self.sample_started_at
        and self.update_started_at >= self.sample_started_at
    then
        self.update_samples[#self.update_samples + 1] = (now - self.update_started_at) * 1000
    end
    for _, input in ipairs(self.pending_inputs) do
        local latency = (now - input.at) * 1000
        emit("input_latency", {
            kind = input.kind,
            latency_ms = ("%.3f"):format(latency),
            sequence = input.sequence,
        })
        if self.sample_started_at and input.at >= self.sample_started_at then
            self.input_samples[#self.input_samples + 1] = latency
        end
    end
    self.pending_inputs = {}
end

---@param self CompatibilityMetrics
---@param now number
function compatibility_metrics.begin_draw(self, now)
    advance_sample(self, now)
    self.draw_started_at = now
end

---@param self CompatibilityMetrics
---@param now number
function compatibility_metrics.finish_draw(self, now)
    advance_sample(self, now)
    if
        self.draw_started_at
        and self.sample_started_at
        and self.draw_started_at >= self.sample_started_at
    then
        self.draw_samples[#self.draw_samples + 1] = (now - self.draw_started_at) * 1000
    end
end

---@param self CompatibilityMetrics
---@param now number
---@param kind string
function compatibility_metrics.input(self, now, kind)
    self.input_sequence = self.input_sequence + 1
    self.pending_inputs[#self.pending_inputs + 1] = {
        at = now,
        kind = kind,
        sequence = self.input_sequence,
    }
    emit("input", {
        at_ms = (now - self.started_at) * 1000,
        kind = kind,
        sequence = self.input_sequence,
    })
end

---@param self CompatibilityMetrics
---@param now number
---@param route string
function compatibility_metrics.route(self, now, route)
    emit("route", {
        at_ms = (now - self.started_at) * 1000,
        route = route,
    })
end

---@param self CompatibilityMetrics
---@param now number
---@param event string
function compatibility_metrics.lifecycle(self, now, event)
    emit("lifecycle", {
        at_ms = (now - self.started_at) * 1000,
        event = event,
    })
end

---@param self CompatibilityMetrics
---@param now number
---@param settings GameSettings
function compatibility_metrics.settings(self, now, settings)
    emit("settings", {
        at_ms = (now - self.started_at) * 1000,
        fullscreen = settings.fullscreen,
        muted = settings.muted,
    })
end

---@param self CompatibilityMetrics
---@param now number
---@param route string
function compatibility_metrics.flow_complete(self, now, route)
    if self.flow_finished then
        return
    end
    self.flow_finished = true
    emit("flow_complete", {
        at_ms = (now - self.started_at) * 1000,
        route = route,
    })
end

---@param self CompatibilityMetrics
---@param now number
function compatibility_metrics.finish(self, now)
    advance_sample(self, now)
    if self.sample_started_at and #self.frame_samples > 0 then
        emit_sample(self, now, true)
        clear_sample(self)
    end
end

return compatibility_metrics
