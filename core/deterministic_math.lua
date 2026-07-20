---@class DeterministicMath
local deterministic_math = {}

local MIN_ATANH_TERMS = 30

---Compute -log(1 - ratio) with an ordered atanh series.
---@param ratio number
---@return number
function deterministic_math.negative_log_one_minus(ratio)
    assert(
        type(ratio) == "number" and ratio >= 0 and ratio < 0.95,
        "negative_log_one_minus ratio must be in [0, 0.95)"
    )

    local z = ratio / (2 - ratio)
    local z_squared = z * z
    local power = z
    local sum = 0
    local term_index = 0
    while true do
        local contribution = power / (2 * term_index + 1)
        local next_sum = sum + contribution
        term_index = term_index + 1
        if term_index >= MIN_ATANH_TERMS and next_sum == sum then
            return 2 * sum
        end
        sum = next_sum
        power = power * z_squared
    end
end

return deterministic_math
