-- Browser-safe FNV-1a-64. The 64-bit value is carried as two unsigned
-- 32-bit limbs, so LuaJIT and love.js never depend on native integer support.

---@class Fnv1a64State
---@field hi number
---@field lo number

---@class Fnv1a64
local fnv1a64 = {}

local LIMB = 4294967296
local BYTE = 256
local PRIME_LOW = 435
local OFFSET_HI = 3421674724
local OFFSET_LO = 2216829733
local HEX = "0123456789abcdef"
local FLOOR = math.floor

-- love.js cannot rely on native bitwise integers. A 4-bit lookup preserves
-- the portable number-only implementation while avoiding eight arithmetic
-- bit iterations for every byte hashed.
---@type integer[]
local XOR_NIBBLE = {}
for left = 0, 15 do
    for right = 0, 15 do
        local a = left
        local b = right
        local result = 0
        local place = 1
        for _ = 1, 4 do
            if a % 2 ~= b % 2 then
                result = result + place
            end
            a = FLOOR(a / 2)
            b = FLOOR(b / 2)
            place = place * 2
        end
        XOR_NIBBLE[left * 16 + right + 1] = result
    end
end

---@param left integer
---@param right integer
---@return integer
local function xor_byte(left, right)
    local low = XOR_NIBBLE[(left % 16) * 16 + (right % 16) + 1]
    local high = XOR_NIBBLE[FLOOR(left / 16) * 16 + FLOOR(right / 16) + 1]
    return low + high * 16
end

---@param value number
---@return string
local function limb_hex(value)
    local chars = {}
    for index = 8, 1, -1 do
        local digit = value % 16
        ---@cast digit integer
        chars[index] = HEX:sub(digit + 1, digit + 1)
        value = FLOOR(value / 16)
    end
    return table.concat(chars)
end

---@return Fnv1a64State
function fnv1a64.new()
    return { hi = OFFSET_HI, lo = OFFSET_LO }
end

---@param state Fnv1a64State
---@param byte integer
function fnv1a64.update_byte(state, byte)
    assert(byte >= 0 and byte < BYTE and byte == FLOOR(byte), "hash byte is invalid")
    local low_byte = state.lo % BYTE
    ---@cast low_byte integer
    state.lo = state.lo - low_byte + xor_byte(low_byte, byte)

    -- FNV prime = 2^40 + 435. With two 32-bit limbs:
    -- hash * 435 contributes to both limbs and hash << 40 contributes
    -- (low << 8) to the high limb. Every intermediate stays below 2^53.
    local low_product = state.lo * PRIME_LOW
    local next_lo = low_product % LIMB
    local carry = FLOOR(low_product / LIMB)
    local shifted_high = (state.lo * BYTE) % LIMB
    local next_hi = (state.hi * PRIME_LOW + carry + shifted_high) % LIMB
    state.hi = next_hi
    state.lo = next_lo
end

---@param state Fnv1a64State
---@param bytes string
---@return Fnv1a64State
function fnv1a64.update(state, bytes)
    assert(type(bytes) == "string", "hash input must be bytes")
    local hi = state.hi
    local lo = state.lo
    for index = 1, #bytes do
        local byte = bytes:byte(index)
        local low_byte = lo % BYTE
        local low = XOR_NIBBLE[(low_byte % 16) * 16 + (byte % 16) + 1]
        local high = XOR_NIBBLE[FLOOR(low_byte / 16) * 16 + FLOOR(byte / 16) + 1]
        lo = lo - low_byte + low + high * 16

        local low_product = lo * PRIME_LOW
        local carry = FLOOR(low_product / LIMB)
        hi = (hi * PRIME_LOW + carry + (lo * BYTE) % LIMB) % LIMB
        lo = low_product % LIMB
    end
    state.hi = hi
    state.lo = lo
    return state
end

---@param state Fnv1a64State
---@return string
function fnv1a64.hex(state)
    return limb_hex(state.hi) .. limb_hex(state.lo)
end

---@param bytes string
---@return string
function fnv1a64.hash(bytes)
    return fnv1a64.hex(fnv1a64.update(fnv1a64.new(), bytes))
end

return fnv1a64
