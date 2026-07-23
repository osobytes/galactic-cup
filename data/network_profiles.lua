---@alias NetworkProfileName "clean"|"omp0_parity"|"playable"|"stress"

---@class NetworkProfile
---@field base_delay_ticks integer
---@field jitter_min_ticks integer
---@field jitter_max_ticks integer
---@field independent_loss_rate number
---@field duplication_rate number
---@field burst_start_rate number
---@field burst_length_ticks integer

---@type table<NetworkProfileName, NetworkProfile>
return {
    clean = {
        base_delay_ticks = 0,
        jitter_min_ticks = 0,
        jitter_max_ticks = 0,
        independent_loss_rate = 0,
        duplication_rate = 0,
        burst_start_rate = 0,
        burst_length_ticks = 0,
    },
    omp0_parity = {
        base_delay_ticks = 3,
        jitter_min_ticks = 0,
        jitter_max_ticks = 0,
        independent_loss_rate = 0.01,
        duplication_rate = 0,
        burst_start_rate = 0,
        burst_length_ticks = 0,
    },
    playable = {
        base_delay_ticks = 3,
        jitter_min_ticks = -2,
        jitter_max_ticks = 2,
        independent_loss_rate = 0.01,
        duplication_rate = 0.0025,
        burst_start_rate = 0.0025,
        burst_length_ticks = 3,
    },
    stress = {
        base_delay_ticks = 6,
        jitter_min_ticks = -3,
        jitter_max_ticks = 3,
        independent_loss_rate = 0.03,
        duplication_rate = 0.01,
        burst_start_rate = 0.01,
        burst_length_ticks = 3,
    },
}
