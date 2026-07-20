local input_frame = require("sim.input_frame")
local match = require("sim.match")
local slot_input = require("sim.slot_input")
local teams = require("data.teams")
local fixed_clock = require("sim.fixed_clock")
local t = require("spec.support.runner")

---@return MatchSlotSource[]
local function frame_sources()
    local sources = {}
    for index = 1, input_frame.SLOT_COUNT do
        sources[index] = { kind = "frame" }
    end
    return sources
end

---@param tick integer
---@param samples table<integer, InputSample>?
---@return InputFrame
local function frame(tick, samples)
    local slots = {}
    for index = 1, input_frame.SLOT_COUNT do
        slots[index] = samples and samples[index] or input_frame.neutral_sample()
    end
    return assert(input_frame.new(tick, slots))
end

---@param sources MatchSlotSource[]?
---@return MatchState
local function new_match(sources)
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion)
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 73,
        input_ownership = ownership,
        slot_sources = sources or frame_sources(),
    })
end

---@param s MatchState
---@return table<integer, integer>
local function copy_slots(s)
    local copied = {}
    for index = 1, input_frame.SLOT_COUNT do
        copied[index] = s.slot_players[index]
    end
    return copied
end

t.describe("fixed match input slots", function()
    t.it("converts a neutral sample without mistaking valid false bits for an error", function()
        local input = slot_input.to_match_input(input_frame.neutral_sample())
        t.eq(input.move.x, 0)
        t.eq(input.move.y, 0)
        t.is_true(not input.shoot)
        t.is_true(not input.pass)
        t.is_true(not input.sprint)
        t.is_true(not input.aerial_strike)
    end)

    t.it("maps exactly four permanent outfield slots per side and excludes both keepers", function()
        local s = new_match()
        local seen = {}
        for index = 1, input_frame.SLOT_COUNT do
            local player_index = s.slot_players[index]
            local player = s.players[player_index]
            local slot = assert(input_frame.slot(index))
            t.eq(player.team, slot.team)
            t.is_true(not player.is_keeper)
            t.eq(s.slot_for_player[player_index], index)
            t.is_true(not seen[player_index])
            seen[player_index] = true
        end
        t.eq(#s.input_ownership.slots, input_frame.SLOT_COUNT)
        t.is_true(s.slot_for_player[1] == nil, "home keeper is never an input owner")
        t.is_true(s.slot_for_player[6] == nil, "away keeper is never an input owner")
    end)

    t.it("routes simultaneous opposing rows without reading controlled or possession", function()
        local s = new_match()
        local home_player = s.slot_players[1]
        local away_player = s.slot_players[5]
        s.players[home_player].pos.x = 180
        s.players[away_player].pos.x = 780
        s.players[home_player].run_vel.x = 0
        s.players[away_player].run_vel.x = 0
        s.controlled = 1 -- Legacy metadata must not redirect either frame row.
        s.owner = s.slot_players[4]

        local samples = {
            [1] = assert(input_frame.new_sample({ move_x = 127 })),
            [5] = assert(input_frame.new_sample({ move_x = -127 })),
        }
        match.step(s, fixed_clock.TICK_SECONDS, frame(0, samples))

        t.is_true(s.players[home_player].run_vel.x > 0, "home_1 consumes its own right input")
        t.is_true(s.players[away_player].run_vel.x < 0, "away_1 consumes its own left input")
    end)

    t.it(
        "keeps ownership stable through legacy metadata, turnover, kickoff, and aerial state changes",
        function()
            local s = new_match()
            local before = copy_slots(s)
            s.controlled = 1
            s.owner = s.slot_players[5]
            s.ball_z = 40
            s.ball_vz = -20
            match.step(s, fixed_clock.TICK_SECONDS, frame(0))
            s.owner = s.slot_players[2]
            s.controlled = 6
            match.step(s, fixed_clock.TICK_SECONDS, frame(1))

            for index = 1, input_frame.SLOT_COUNT do
                t.eq(s.slot_players[index], before[index], "slot mapping stays immutable")
                t.eq(
                    s.slot_for_player[before[index]],
                    index,
                    "player routes back to its original slot"
                )
            end
        end
    )

    t.it(
        "fills only explicitly bot-configured slots from their independent seeded streams",
        function()
            local sources = frame_sources()
            sources[1] = { kind = "bot", seed = 901 }
            sources[5] = { kind = "bot", seed = 902 }
            local left = new_match(sources)
            local right = new_match(sources)
            for tick = 0, 30 do
                local input = frame(tick)
                match.step(left, fixed_clock.TICK_SECONDS, input)
                match.step(right, fixed_clock.TICK_SECONDS, input)
            end
            for index = 1, #left.players do
                t.near(left.players[index].pos.x, right.players[index].pos.x, 1e-9)
                t.near(left.players[index].pos.y, right.players[index].pos.y, 1e-9)
            end
            t.eq(left.slot_input_state.sources[1].seed, 901)
            t.eq(left.slot_input_state.sources[5].seed, 902)
            t.eq(left.slot_input_state.sources[2].kind, "frame")
        end
    )

    t.it("rejects a legacy MatchInput in slot mode", function()
        local s = new_match()
        ---@type MatchInput
        local legacy_input = {
            move = { x = 0, y = 0 },
            shoot = false,
            shoot_held = false,
            pass = false,
            pass_held = false,
            switch = false,
            dash = false,
            dodge = false,
            lob = false,
            sprint = false,
            jockey = false,
        }
        local ok = pcall(function()
            match.step(s, fixed_clock.TICK_SECONDS, legacy_input)
        end)
        t.is_true(not ok)
    end)
end)
