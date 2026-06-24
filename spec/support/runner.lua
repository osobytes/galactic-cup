-- Tiny headless test framework. No luarocks, no sudo — runs in LÖVE's LuaJIT.
-- Specs call describe/it/assertions; main.lua (--test) drives load_and_run + summary.

---@class Runner
---@field passed integer
---@field failed integer
---@field failures string[]
local M = {
    passed = 0,
    failed = 0,
    failures = {},
}

local context = ""

---@param name string
---@param fn fun()
function M.describe(name, fn)
    local prev = context
    context = context == "" and name or (context .. " > " .. name)
    fn()
    context = prev
end

---@param name string
---@param fn fun()
function M.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        M.passed = M.passed + 1
    else
        M.failed = M.failed + 1
        M.failures[#M.failures + 1] = ("%s > %s\n      %s"):format(context, name, tostring(err))
    end
end

---@param cond any
---@param msg string?
function M.is_true(cond, msg)
    if not cond then
        error(msg or "expected truthy value", 2)
    end
end

---@param a any
---@param b any
---@param msg string?
function M.eq(a, b, msg)
    if a ~= b then
        error(
            ("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", tostring(b), tostring(a)),
            2
        )
    end
end

---@param a number
---@param b number
---@param eps number?
---@param msg string?
function M.near(a, b, eps, msg)
    eps = eps or 1e-6
    if math.abs(a - b) > eps then
        error(("%sexpected ~%s (+/-%s), got %s"):format(msg and (msg .. ": ") or "", b, eps, a), 2)
    end
end

-- Recursively load and execute every *_spec.lua under `dir`.
---@param dir string
function M.load_and_run(dir)
    for _, item in ipairs(love.filesystem.getDirectoryItems(dir)) do
        local path = dir .. "/" .. item
        local info = love.filesystem.getInfo(path)
        if info and info.type == "directory" then
            M.load_and_run(path)
        elseif item:match("_spec%.lua$") then
            local chunk = assert(love.filesystem.load(path))
            chunk()
        end
    end
end

---@return boolean ok
function M.summary()
    print(("\n%d passed, %d failed"):format(M.passed, M.failed))
    for _, f in ipairs(M.failures) do
        print("  FAIL: " .. f)
    end
    return M.failed == 0
end

return M
