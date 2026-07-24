local t = require("spec.support.runner")
local rating = require("sim.rating")

---@param id string
---@param position Position
---@param value integer
---@return PlayerData
local function player(id, position, value)
    return {
        id = id,
        name = id,
        number = 1,
        position = position,
        stats = {
            pace = value,
            strength = value,
            technique = value,
            stamina = value,
            mental = value,
        },
        presentation_id = "test",
        cosmetic_variant_id = nil,
        loadout_id = position == "keeper" and nil or "test",
    }
end

---@param value integer
---@return string[], table<string, PlayerData>
local function squad(value)
    local roster = { "keeper", "defender", "midfielder", "forward_a", "forward_b" }
    local by_id = {
        keeper = player("keeper", "keeper", value),
        defender = player("defender", "defender", value),
        midfielder = player("midfielder", "midfielder", value),
        forward_a = player("forward_a", "forward", value),
        forward_b = player("forward_b", "forward", value),
    }
    return roster, by_id
end

t.describe("rating.squad", function()
    t.it("strictly stronger starters out-rate weaker starters", function()
        local weak_roster, weak = squad(2)
        local strong_roster, strong = squad(8)
        t.is_true(rating.squad(strong_roster, strong) > rating.squad(weak_roster, weak))
    end)

    t.it("pins the frozen red-team #11 weights", function()
        local roster, by_id = squad(0)
        for _, starter in pairs(by_id) do
            starter.stats = { pace = 1, strength = 2, technique = 3, stamina = 4, mental = 5 }
        end
        t.near(rating.squad(roster, by_id), 13.95, 1e-12)
    end)

    t.it("is invariant to roster order, including where the keeper id appears", function()
        local roster, by_id = squad(6)
        local shuffled = { roster[4], roster[2], roster[5], roster[1], roster[3] }
        t.near(rating.squad(roster, by_id), rating.squad(shuffled, by_id), 1e-12)
    end)

    t.it("uses goalkeeper identity and authored position, not an array slot", function()
        local roster, by_id = squad(5)
        by_id.reserve_keeper = player("reserve_keeper", "keeper", 9)
        local upgraded = { "reserve_keeper", roster[2], roster[3], roster[4], roster[5] }
        t.is_true(rating.squad(upgraded, by_id) > rating.squad(roster, by_id))
    end)

    t.it("is deterministic", function()
        local roster, by_id = squad(7)
        local first = rating.squad(roster, by_id)
        t.eq(rating.squad(roster, by_id), first)
        t.eq(rating.squad(roster, by_id), first)
    end)
end)
