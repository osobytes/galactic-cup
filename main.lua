-- Entry point. Modes:
--   love .                    -> run the game (screen stack)
--   love . --test             -> run the headless test suite and exit with status code
--   love . --sim [n]          -> play n unattended matches, print fun-proxy metrics, exit
--   love . --rate-validate [n] -> validate frozen squad ratings over n paired seeds, exit
--   love . --levers [n]       -> paired liveness checks for built-in manager levers, exit
--   love . --sweep [n]        -> per-knob min/max sensitivity sweep over n seeds, exit
--   love . --search K1,K2 [n] [start] -> coordinate ascent over the named knobs
--                                (warm-started from tuning blob file `start`), exit
--   love . --eval FILE [n] [REF] -> tuning blob FILE vs REF blob (default: the
--                                defaults) on held-out seeds, exit
--   love . --tripwire [write] -> compare the fun signature against the checked-in
--                                baseline (exit 1 on drift); `write` refreshes it

---@param a string
---@return boolean
local function has_flag(a)
    for _, v in ipairs(arg or {}) do
        if v == a then
            return true
        end
    end
    return false
end

if has_flag("--test") then
    function love.load()
        local runner = require("spec.support.runner")
        runner.load_and_run("spec")
        os.exit(runner.summary() and 0 or 1)
    end
    return
end

-- The (up to three) values following `flag`, e.g. `--search KNOBS [n] [start]`.
---@param flag string
---@return string?, string?, string?
local function args_after(flag)
    for i, v in ipairs(arg or {}) do
        if v == flag then
            return arg[i + 1], arg[i + 2], arg[i + 3]
        end
    end
    return nil, nil, nil
end

if has_flag("--sim") then
    function love.load()
        local n_arg = args_after("--sim")
        local n = tonumber(n_arg) and math.floor(tonumber(n_arg) --[[@as number]]) or 20
        local headless = require("sim.headless")
        print(headless.report(headless.run_batch({ n = n })))
        os.exit(0)
    end
    return
end

if has_flag("--tripwire") then
    function love.load()
        local sub = args_after("--tripwire")
        local tripwire = require("sim.tripwire")
        if sub == "write" then
            local current, n = tripwire.measure()
            local f = assert(io.open("data/fun_baseline.lua", "w"))
            f:write(tripwire.serialize(current, n))
            f:close()
            print("fun baseline refreshed: data/fun_baseline.lua (" .. n .. " seeds)")
            os.exit(0)
        end
        local ok_load, baseline = pcall(require, "data.fun_baseline")
        if not ok_load or type(baseline) ~= "table" then
            print("no baseline: data/fun_baseline.lua missing — create it with:")
            print("    love . --tripwire write")
            os.exit(1)
        end
        local current, n = tripwire.measure(baseline.n)
        local ok, rows = tripwire.compare(baseline, current)
        print(tripwire.report(rows, ok, n))
        os.exit(ok and 0 or 1)
    end
    return
end

if has_flag("--rate-validate") then
    function love.load()
        local n_arg = args_after("--rate-validate")
        local n = tonumber(n_arg) and math.floor(tonumber(n_arg) --[[@as number]]) or 20
        local validation = require("sim.rating_validation")
        print(validation.report(validation.run(n)))
        os.exit(0)
    end
    return
end

if has_flag("--levers") then
    function love.load()
        local n_arg = args_after("--levers")
        local n = tonumber(n_arg) and math.floor(tonumber(n_arg) --[[@as number]]) or 30
        assert(n > 0, "--levers needs a positive seed count")
        local lever_metrics = require("sim.lever_metrics")
        local seeds = {}
        for i = 1, n do
            seeds[i] = i
        end
        local config_name, runs = lever_metrics.run_built_ins(seeds, print)
        print(lever_metrics.report(config_name, runs))
        os.exit(0)
    end
    return
end

if has_flag("--sweep") then
    function love.load()
        local n_arg = args_after("--sweep")
        local n = tonumber(n_arg) and math.floor(tonumber(n_arg) --[[@as number]]) or 30
        local sweep = require("sim.sweep")
        local seeds = {}
        for i = 1, n do
            seeds[i] = i
        end
        local result = sweep.sensitivity({ seeds = seeds, log = print })
        print(sweep.sensitivity_report(result))
        os.exit(0)
    end
    return
end

if has_flag("--search") then
    function love.load()
        local keys_arg, n_arg, start_arg = args_after("--search")
        assert(keys_arg, "--search needs a comma-separated knob list")
        local keys = {}
        for key in keys_arg:gmatch("[%w_]+") do
            keys[#keys + 1] = key
        end
        local n = tonumber(n_arg) and math.floor(tonumber(n_arg) --[[@as number]]) or 30
        local sweep = require("sim.sweep")
        local headless = require("sim.headless")
        local start = nil
        if start_arg then
            local f = assert(io.open(start_arg, "r"), "cannot open " .. start_arg)
            start = sweep.parse_blob(f:read("*a"))
            f:close()
        end
        local seeds = {}
        for i = 1, n do
            seeds[i] = i
        end
        local r = sweep.ascend({ keys = keys, seeds = seeds, start = start, log = print })
        print(("best blob (dFun %+.3f +/- %.3f on search seeds):"):format(r.delta.mean, r.delta.se))
        print(r.blob ~= "" and r.blob or "(defaults)")
        print(headless.report(headless.run_batch({ seeds = seeds, tuning_blob = r.blob })))
        os.exit(0)
    end
    return
end

if has_flag("--eval") then
    function love.load()
        local path, n_arg, ref_arg = args_after("--eval")
        assert(path, "--eval needs a tuning blob file path")
        local function slurp(p)
            local f = assert(io.open(p, "r"), "cannot open " .. tostring(p))
            local blob = f:read("*a")
            f:close()
            return blob
        end
        local blob = slurp(path)
        local ref = ref_arg and slurp(ref_arg) or ""
        local n = tonumber(n_arg) and math.floor(tonumber(n_arg) --[[@as number]]) or 60
        local sweep = require("sim.sweep")
        local headless = require("sim.headless")
        -- Held-out seeds, disjoint from the 1..N the sweep/search train on.
        local seeds = {}
        for i = 1, n do
            seeds[i] = 1000 + i
        end
        local base = sweep.evaluate(ref, seeds)
        local cand = sweep.evaluate(blob, seeds)
        local d = sweep.paired_delta(base.funs, cand.funs)
        print(
            ("held-out seeds %d..%d: dFun %+.3f +/- %.3f (paired, vs %s)"):format(
                seeds[1],
                seeds[n],
                d.mean,
                d.se,
                ref_arg or "defaults"
            )
        )
        print("--- reference ---")
        print(headless.report(headless.run_batch({ seeds = seeds, tuning_blob = ref })))
        print("--- candidate ---")
        print(headless.report(headless.run_batch({ seeds = seeds, tuning_blob = blob })))
        os.exit(0)
    end
    return
end

local bootstrap = require("game.bootstrap")
local compatibility_metrics = require("game.compatibility_metrics")
local runtime_settings = require("game.runtime_settings")

---@type App
local app
---@type CompatibilityMetrics
local metrics
local last_route

---@return number
local function clock()
    return love.timer.getTime()
end

---@param kind string
local function record_input(kind)
    if metrics then
        metrics:input(clock(), kind)
    end
end

function love.load()
    metrics = compatibility_metrics.new(clock())
    local width, height = love.graphics.getDimensions()
    app = bootstrap.new(width, height, {
        apply_settings = runtime_settings.apply,
        request_quit = function()
            love.event.quit()
        end,
    })
    runtime_settings.apply(app.settings)
    app:resize(love.graphics.getDimensions())
    last_route = app:current_route()
    metrics:route(clock(), last_route)
end

---@param dt number
function love.update(dt)
    metrics:begin_update(clock())
    app:update(dt)
    local now = clock()
    metrics:finish_update(now)
    local route = app:current_route()
    if route ~= last_route then
        metrics:route(now, route)
        last_route = route
        if route == "result" then
            metrics:flow_complete(now, route)
        end
    end
end

function love.draw()
    metrics:begin_draw(clock())
    app:draw()
    metrics:finish_draw(clock())
end

function love.quit()
    if metrics then
        metrics:finish(clock())
    end
end

---@param key string
function love.keypressed(key)
    record_input("key_" .. key)
    app:event({ kind = "key", key = key })
end

---@param x number
---@param y number
---@param button number
function love.mousepressed(x, y, button)
    record_input("mouse_" .. button)
    app:event({ kind = "click", x = x, y = y, button = button })
end

---@param joystick love.Joystick
---@param button love.GamepadButton
function love.gamepadpressed(joystick, button)
    local _ = joystick
    record_input("gamepad_" .. button)
    app:event({ kind = "gamepad", button = button })
end

---@param width number
---@param height number
function love.resize(width, height)
    metrics:lifecycle(clock(), "resize")
    app:resize(width, height)
end

---@param focused boolean
function love.focus(focused)
    metrics:lifecycle(clock(), focused and "focus" or "blur")
    app:focus(focused)
end

---@param joystick love.Joystick
function love.joystickremoved(joystick)
    local _ = joystick
    metrics:lifecycle(clock(), "joystick_removed")
    app:pause_match()
end
