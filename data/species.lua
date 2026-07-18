-- Showcase species identity. MVP species use authored player stats for their
-- mechanical identity; modifiers and verbs remain neutral until after MVP.

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
---@field tagline string?
---@field palette number[]?
---@field shape "round"|"broad"|"angular"|"cluster"?

---@type table<string, SpeciesData>
return {
    neutral = {
        id = "neutral",
        name = "Neutral",
        modifiers = { pace = 0, strength = 0, technique = 0, stamina = 0, mental = 0 },
        verb = "none",
        skill = nil,
        tagline = "Adaptable all-rounders",
        palette = { 0.55, 0.72, 0.92 },
        shape = "round",
    },
    terran = {
        id = "terran",
        name = "Terran",
        modifiers = { pace = 0, strength = 0, technique = 0, stamina = 0, mental = 0 },
        verb = "none",
        skill = nil,
        tagline = "Composed and versatile",
        palette = { 0.35, 0.75, 1.0 },
        shape = "round",
    },
    gravling = {
        id = "gravling",
        name = "Gravling",
        modifiers = { pace = 0, strength = 0, technique = 0, stamina = 0, mental = 0 },
        verb = "none",
        skill = nil,
        tagline = "Powerful anchor players",
        palette = { 1.0, 0.55, 0.25 },
        shape = "broad",
    },
    voltari = {
        id = "voltari",
        name = "Voltari",
        modifiers = { pace = 0, strength = 0, technique = 0, stamina = 0, mental = 0 },
        verb = "none",
        skill = nil,
        tagline = "Electric breakaway speed",
        palette = { 0.9, 0.85, 0.2 },
        shape = "angular",
    },
    myceloid = {
        id = "myceloid",
        name = "Myceloid",
        modifiers = { pace = 0, strength = 0, technique = 0, stamina = 0, mental = 0 },
        verb = "none",
        skill = nil,
        tagline = "Technical collective minds",
        palette = { 0.7, 0.4, 0.95 },
        shape = "cluster",
    },
}
