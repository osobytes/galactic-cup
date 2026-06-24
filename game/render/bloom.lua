-- Additive bloom post-process. Render a frame through bloom.draw(fn): the frame
-- is captured to a canvas, bright areas are extracted, blurred, and added back
-- for a neon glow.
--
-- Defensive by design: if shader compilation or canvas creation fails (driver
-- quirks, headless GL), it logs once and degrades to a plain passthrough so the
-- game keeps running without glow. Tunable via bloom.config.

local bloom = {}

local THRESHOLD_SRC = [[
extern number threshold;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc);
    number b = max(c.r, max(c.g, c.b));
    number f = smoothstep(threshold, threshold + 0.15, b);
    return vec4(c.rgb * f, 1.0);
}
]]

local BLUR_SRC = [[
extern vec2 direction;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 sum = vec4(0.0);
    sum += Texel(tex, tc + direction * -4.0) * 0.05;
    sum += Texel(tex, tc + direction * -3.0) * 0.09;
    sum += Texel(tex, tc + direction * -2.0) * 0.12;
    sum += Texel(tex, tc + direction * -1.0) * 0.15;
    sum += Texel(tex, tc) * 0.18;
    sum += Texel(tex, tc + direction *  1.0) * 0.15;
    sum += Texel(tex, tc + direction *  2.0) * 0.12;
    sum += Texel(tex, tc + direction *  3.0) * 0.09;
    sum += Texel(tex, tc + direction *  4.0) * 0.05;
    return sum;
}
]]

bloom.config = {
    enabled = true,
    threshold = 0.55, -- brightness above which pixels glow
    intensity = 1.3, -- additive strength of the glow
    passes = 2, -- blur iterations (more = softer/wider)
    radius = 2.0, -- blur step (texels in low-res space)
    downscale = 2, -- bright/blur buffers at 1/downscale resolution
}

local state = {
    failed = false,
    w = 0,
    h = 0,
    ---@type love.Canvas?
    scene = nil,
    ---@type love.Canvas?
    a = nil,
    ---@type love.Canvas?
    b = nil,
    ---@type love.Shader?
    threshold_shader = nil,
    ---@type love.Shader?
    blur_shader = nil,
}

---@param w number
---@param h number
---@return boolean ok
local function ensure(w, h)
    if state.failed then
        return false
    end

    if not state.threshold_shader then
        local ok1, s1 = pcall(love.graphics.newShader, THRESHOLD_SRC)
        local ok2, s2 = pcall(love.graphics.newShader, BLUR_SRC)
        if not (ok1 and ok2) then
            state.failed = true
            print(
                "bloom disabled (shader compile failed): " .. tostring(s1) .. " / " .. tostring(s2)
            )
            return false
        end
        state.threshold_shader = s1
        state.blur_shader = s2
    end

    if state.w ~= w or state.h ~= h or not state.scene then
        state.w, state.h = w, h
        local lw = math.max(1, math.floor(w / bloom.config.downscale))
        local lh = math.max(1, math.floor(h / bloom.config.downscale))
        local ok, err = pcall(function()
            state.scene = love.graphics.newCanvas(math.floor(w), math.floor(h))
            state.a = love.graphics.newCanvas(lw, lh)
            state.b = love.graphics.newCanvas(lw, lh)
        end)
        if not ok then
            state.failed = true
            print("bloom disabled (canvas creation failed): " .. tostring(err))
            return false
        end
    end
    return true
end

-- Render `render_fn` with bloom applied (or plain, if bloom is unavailable).
---@param render_fn fun()
function bloom.draw(render_fn)
    local w, h = love.graphics.getDimensions()
    if not bloom.config.enabled or not ensure(w, h) then
        render_fn()
        return
    end

    local cfg = bloom.config
    -- ensure() guarantees these exist; assert narrows the optional types.
    local scene = assert(state.scene)
    local a = assert(state.a)
    local b = assert(state.b)
    local lw, lh = a:getWidth(), a:getHeight()

    -- 1. Capture the frame.
    love.graphics.setCanvas(scene)
    love.graphics.clear(0, 0, 0, 1)
    render_fn()
    love.graphics.setCanvas()

    -- 2. Bright-pass into the low-res buffer.
    love.graphics.setCanvas(a)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(state.threshold_shader)
    state.threshold_shader:send("threshold", cfg.threshold)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(scene, 0, 0, 0, lw / w, lh / h)
    love.graphics.setShader()
    love.graphics.setCanvas()

    -- 3. Separable Gaussian blur, ping-ponging a <-> b.
    love.graphics.setShader(state.blur_shader)
    for _ = 1, cfg.passes do
        love.graphics.setCanvas(b)
        love.graphics.clear(0, 0, 0, 1)
        state.blur_shader:send("direction", { cfg.radius / lw, 0 })
        love.graphics.draw(a, 0, 0)
        love.graphics.setCanvas()

        love.graphics.setCanvas(a)
        love.graphics.clear(0, 0, 0, 1)
        state.blur_shader:send("direction", { 0, cfg.radius / lh })
        love.graphics.draw(b, 0, 0)
        love.graphics.setCanvas()
    end
    love.graphics.setShader()

    -- 4. Composite: original frame + additive glow.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(scene, 0, 0)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(cfg.intensity, cfg.intensity, cfg.intensity, 1)
    love.graphics.draw(a, 0, 0, 0, w / lw, h / lh)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return bloom
