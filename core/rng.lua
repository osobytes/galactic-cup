-- Deterministic PRNG (Park–Miller "minstd"). The sim must stay reproducible —
-- same seed, same match — so randomness is explicit state threaded through
-- MatchState, never math.random. All arithmetic stays exact in doubles
-- (MULT * MOD < 2^53).

local rng = {}

local MOD = 2147483647 -- 2^31 - 1 (prime)
local MULT = 16807 -- the minimal-standard multiplier

-- Clamp any number into a valid, non-degenerate seed.
---@param seed number
---@return integer
function rng.seed(seed)
    seed = math.floor(math.abs(seed)) % MOD
    if seed == 0 then
        seed = 1
    end
    return seed
end

-- Advance the state and return a uniform sample in [0, 1).
---@param state integer
---@return integer new_state
---@return number sample
function rng.roll(state)
    local s = (state * MULT) % MOD
    return s, (s - 1) / (MOD - 1)
end

return rng
