-- Pure species-to-match translation. Attribute deltas are the first of the
-- readability cap's two modifier layers; the arena layer is the reserved second.

local MIN_STAT = 0
local MAX_STAT = 10

---@class Species
local species = {}

---@param value integer
---@return integer
local function clamp_stat(value)
    return math.max(MIN_STAT, math.min(MAX_STAT, value))
end

---@param owned_verb SimVerb
---@param seam SimVerb
---@return number neutral_effect
local function neutral_hook(owned_verb, seam)
    if owned_verb == seam then
        return 0
    end
    return 0
end

---Apply one additive species modifier vector without mutating authored player data.
---@param stat_block StatBlock
---@param species_data SpeciesData
---@return StatBlock effective_stats
function species.apply(stat_block, species_data)
    local modifiers = species_data.modifiers
    return {
        pace = clamp_stat(stat_block.pace + modifiers.pace),
        strength = clamp_stat(stat_block.strength + modifiers.strength),
        technique = clamp_stat(stat_block.technique + modifiers.technique),
        stamina = clamp_stat(stat_block.stamina + modifiers.stamina),
        mental = clamp_stat(stat_block.mental + modifiers.mental),
    }
end

-- Named verb hooks deliberately return neutral values. Issues #0010–#0012 can
-- bind skill effects here while the match keeps one stable lookup at each action seam.

---@param owned_verb SimVerb
---@return number pixels
function species.jump_reach(owned_verb)
    return neutral_hook(owned_verb, "jump")
end

---@param owned_verb SimVerb
---@return number pixels
function species.jump_lift(owned_verb)
    return neutral_hook(owned_verb, "jump")
end

---@param owned_verb SimVerb
---@return number pixels
function species.collision_reach(owned_verb)
    return neutral_hook(owned_verb, "collision")
end

---@param owned_verb SimVerb
---@return number multiplier
function species.burst_speed(owned_verb)
    return 1 + neutral_hook(owned_verb, "burst")
end

---@param owned_verb SimVerb
---@return number pixels
function species.dribble_protection(owned_verb)
    return neutral_hook(owned_verb, "dribble")
end

---@param owned_verb SimVerb
---@return number pixels
function species.block_reach(owned_verb)
    return neutral_hook(owned_verb, "block")
end

---@param owned_verb SimVerb
---@return number multiplier
function species.link_pass_speed(owned_verb)
    return 1 + neutral_hook(owned_verb, "link")
end

return species
