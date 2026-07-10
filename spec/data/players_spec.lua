local players = require("data.players")
local t = require("spec.support.runner")

---@type table<string, boolean>
local CANONICAL_STATS = {
    pace = true,
    strength = true,
    technique = true,
    stamina = true,
    mental = true,
}

t.describe("player data", function()
    t.it("authors exactly the five canonical attributes", function()
        for _, player in ipairs(players) do
            local count = 0
            for name, value in pairs(player.stats) do
                count = count + 1
                t.is_true(
                    CANONICAL_STATS[name],
                    player.id .. " has unexpected stat " .. tostring(name)
                )
                t.is_true(
                    type(value) == "number",
                    player.id .. "." .. tostring(name) .. " must be numeric"
                )
            end
            t.eq(count, 5, player.id .. " has exactly five authored attributes")
        end
    end)
end)
