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

    t.it("keeps persistent identity separate from presentation and loadout ids", function()
        local seen_ids = {}
        for _, player in ipairs(players) do
            t.is_true(not seen_ids[player.id], "duplicate player id " .. player.id)
            seen_ids[player.id] = true
            t.is_true(player.number >= 1 and player.number <= 99)
            t.is_true(player.presentation_id ~= "")
            if player.position == "keeper" then
                t.eq(player.loadout_id, nil, player.id .. " keeper has no combat loadout")
            else
                t.is_true(player.loadout_id ~= nil and player.loadout_id ~= "")
            end
            t.eq(
                rawget(player, "species"),
                nil,
                "mechanical species moved to showcase compatibility"
            )
            t.eq(
                rawget(player, "presentation_species"),
                nil,
                "showcase presentation moved to compatibility data"
            )
        end
    end)
end)
