-- Entry point. Modes:
--   love .                    -> run the game (screen stack)
--   love . --test             -> run the headless test suite and exit with status code
--   love . --sim [n]          -> play n unattended matches, print fun-proxy metrics, exit
--   love . --sweep [n]        -> per-knob min/max sensitivity sweep over n seeds, exit
--   love . --search K1,K2 [n] [start] -> coordinate ascent over the named knobs
--                                (warm-started from tuning blob file `start`), exit
--   love . --eval FILE [n] [REF] -> tuning blob FILE vs REF blob (default: the
--                                defaults) on held-out seeds, exit

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

local ScreenStack = require("game.screen_stack")
local Flow = require("game.flow")

---@type ScreenStack
local stack

function love.load()
    stack = ScreenStack.new()
    local viewport = { w = love.graphics.getWidth(), h = love.graphics.getHeight() }
    Flow.start(stack, viewport)
end

---@param dt number
function love.update(dt)
    stack:update(dt)
end

function love.draw()
    stack:draw()
end

---@param key string
function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
        return
    end
    stack:event({ kind = "key", key = key })
end

---@param x number
---@param y number
---@param button number
function love.mousepressed(x, y, button)
    stack:event({ kind = "click", x = x, y = y, button = button })
end
