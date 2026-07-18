local players = require("data.players")
local species = require("data.species")
local t = require("spec.support.runner")

t.describe("showcase species data", function()
    t.it("authors four distinct visual identities without activating mechanics", function()
        local ids = { "terran", "gravling", "voltari", "myceloid" }
        local shapes = {}
        local seen_ids = {}
        for _, id in ipairs(ids) do
            local data = assert(species[id])
            t.eq(data.id, id)
            t.is_true(not seen_ids[data.id])
            seen_ids[data.id] = true
            t.is_true(data.tagline ~= nil and data.tagline ~= "")
            t.eq(#assert(data.palette), 3)
            for _, value in ipairs(data.palette) do
                t.is_true(value >= 0 and value <= 1)
            end
            t.is_true(data.shape ~= nil)
            t.eq(data.verb, "none")
            t.eq(data.modifiers.pace, 0)
            shapes[assert(data.shape)] = true
        end
        t.eq(#ids, 4)
        t.is_true(shapes.round and shapes.broad and shapes.angular and shapes.cluster)
    end)

    t.it(
        "gives every player a valid presentation species while simulation stays neutral",
        function()
            local seen = {}
            local player_ids = {}
            for _, player in ipairs(players) do
                t.is_true(not player_ids[player.id])
                player_ids[player.id] = true
                t.eq(player.species, "neutral")
                local presentation = assert(player.presentation_species)
                t.is_true(species[presentation] ~= nil)
                seen[presentation] = true
                for _, value in pairs(player.stats) do
                    t.is_true(value >= 0 and value <= 10)
                end
            end
            t.is_true(seen.terran and seen.gravling and seen.voltari and seen.myceloid)
        end
    )
end)
