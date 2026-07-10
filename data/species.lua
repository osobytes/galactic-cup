-- Species content. Only the neutral compatibility entry ships with the schema;
-- authored species and their balance values belong to issue #0009.

---@alias SimVerb "jump"|"collision"|"burst"|"dribble"|"block"|"link"|"none"

---@class StatModifier
---@field pace integer
---@field strength integer
---@field technique integer
---@field stamina integer
---@field mental integer

---@class SpeciesData
---@field id string
---@field name string
---@field modifiers StatModifier
---@field verb SimVerb
---@field skill string?

---@type table<string, SpeciesData>
return {
    neutral = {
        id = "neutral",
        name = "Neutral",
        modifiers = { pace = 0, strength = 0, technique = 0, stamina = 0, mental = 0 },
        verb = "none",
        skill = nil,
    },
}
