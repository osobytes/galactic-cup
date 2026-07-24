local t = require("spec.support.runner")
local fnv1a64 = require("core.fnv1a64")

t.describe("core.fnv1a64", function()
    t.it("matches published FNV-1a-64 vectors without native integer support", function()
        t.eq(fnv1a64.hash(""), "cbf29ce484222325")
        t.eq(fnv1a64.hash("a"), "af63dc4c8601ec8c")
        t.eq(fnv1a64.hash("foobar"), "85944171f73967e8")
        t.eq(fnv1a64.hash("hello"), "a430d84680aabd0b")
    end)

    t.it("supports incremental byte updates", function()
        local state = fnv1a64.new()
        fnv1a64.update(state, "foo")
        fnv1a64.update(state, "bar")
        t.eq(fnv1a64.hex(state), fnv1a64.hash("foobar"))
    end)

    t.it("keeps bulk and byte-at-a-time updates identical across every byte", function()
        local values = {}
        local incremental = fnv1a64.new()
        for byte = 0, 255 do
            values[#values + 1] = string.char(byte)
            fnv1a64.update_byte(incremental, byte)
        end
        local bytes = table.concat(values)
        t.eq(fnv1a64.hash(bytes), "4242dc5249c33625")
        t.eq(fnv1a64.hex(incremental), "4242dc5249c33625")
    end)
end)
