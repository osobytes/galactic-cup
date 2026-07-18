---@class ArenaData
---@field id string
---@field name string
---@field location string
---@field floor_color number[]
---@field marking_color number[]
---@field rail_color number[]
---@field highlight_color number[]

---@type table<string, ArenaData>
return {
    helios_crown = {
        id = "helios_crown",
        name = "Helios Crown",
        location = "Kairon-9 Orbit",
        floor_color = { 0.025, 0.16, 0.17 },
        marking_color = { 0.35, 0.72, 1.0 },
        rail_color = { 0.25, 0.88, 1.0 },
        highlight_color = { 1.0, 0.66, 0.24 },
    },
}
