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

---@return MatchState
local function new_match()
    local ownership = match.ownership_for_teams(teams.nebula, teams.orion)
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 73,
        input_ownership = ownership,
    })
end

---@return MatchState
local function new_legacy_match()
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = 73,
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
        t.is_true(not input.equipment_held)
        t.is_true(not input.equipment_pressed)
        t.is_true(not input.equipment_released)
    end)

    t.it("round trips canonical equipment held and edge intent", function()
        local pressed = slot_input.neutral_match_input()
        pressed.equipment_held = true
        pressed.equipment_pressed = true
        local pressed_sample = slot_input.to_sample(pressed)
        local pressed_input = slot_input.to_match_input(pressed_sample)
        t.is_true(pressed_input.equipment_held)
        t.is_true(pressed_input.equipment_pressed)
        t.is_true(not pressed_input.equipment_released)

        local tapped = slot_input.neutral_match_input()
        tapped.equipment_pressed = true
        tapped.equipment_released = true
        local tapped_input = slot_input.to_match_input(slot_input.to_sample(tapped))
        t.is_true(not tapped_input.equipment_held)
        t.is_true(tapped_input.equipment_pressed)
        t.is_true(tapped_input.equipment_released)
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

    t.it("does not hand slot-mode legacy selection to a pass receiver", function()
        local s = new_match()
        local local_player = s.slot_players[4]
        s.controlled = local_player
        local pass = assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.pass }))
        match.step(s, fixed_clock.TICK_SECONDS, frame(0, { [4] = pass }))

        t.eq(s.controlled, local_player, "a pass cannot move slot-mode legacy metadata")
        t.is_true(s.owner ~= local_player, "the pass was released from the fixed local player")
    end)

    t.it("suppresses the real legacy turnover and aerial reselection branches", function()
        ---@param s MatchState
        local function setup_smother(s)
            s.controlled = 2
            s.owner = 5
            s.players[5].pos.x, s.players[5].pos.y = 850, 270
            s.players[5].facing.x, s.players[5].facing.y = 1, 0
            s.players[6].pos.x, s.players[6].pos.y = 868, 270
            s.ball.x, s.ball.y = 868, 270
            s.ball_vel.x, s.ball_vel.y = 0, 0
        end

        local slot_turnover = new_match()
        local legacy_turnover = new_legacy_match()
        setup_smother(slot_turnover)
        setup_smother(legacy_turnover)
        match.step(slot_turnover, fixed_clock.TICK_SECONDS, frame(0))
        match.step(legacy_turnover, fixed_clock.TICK_SECONDS, slot_input.neutral_match_input())

        t.eq(slot_turnover.owner, 6, "away keeper really takes the home carrier's ball")
        t.eq(legacy_turnover.owner, 6, "the comparison reaches the same turnover")
        t.eq(slot_turnover.controlled, 2, "slot mode suppresses turnover reselection")
        t.is_true(
            legacy_turnover.controlled ~= 2,
            "the same transition exercises legacy turnover reselection"
        )

        ---@param s MatchState
        local function setup_aerial(s)
            s.controlled = 2
            s.owner = nil
            s.pickup_cd = 1
            s.players[5].pos.x, s.players[5].pos.y = 700, 270
            s.ball.x, s.ball.y = 700, 270
            s.ball_z, s.ball_vz = 50, 100
            s.ball_vel.x, s.ball_vel.y = 0, 0
        end

        local slot_aerial = new_match()
        local legacy_aerial = new_legacy_match()
        setup_aerial(slot_aerial)
        setup_aerial(legacy_aerial)
        match.step(slot_aerial, fixed_clock.TICK_SECONDS, frame(0))
        match.step(legacy_aerial, fixed_clock.TICK_SECONDS, slot_input.neutral_match_input())

        t.is_true(slot_aerial.owner == nil and slot_aerial.ball_z > 30)
        t.is_true(legacy_aerial.owner == nil and legacy_aerial.ball_z > 30)
        t.eq(slot_aerial.controlled, 2, "slot mode suppresses aerial assistance")
        t.eq(legacy_aerial.controlled, 5, "the same rising cross triggers legacy assistance")
    end)

    t.it("clears a heavy-touch carrier before the loss tick ends", function()
        local s = new_match()
        local carrier_idx = assert(s.owner)
        local carrier = s.players[carrier_idx]
        carrier.pos.x, carrier.pos.y = 300, 270
        carrier.facing.x, carrier.facing.y = 1, 0
        carrier.vel.x, carrier.vel.y = 0, 0
        carrier.run_vel.x, carrier.run_vel.y = 0, 0
        carrier.dribble = 0
        carrier.charge = 0.7
        carrier.pass_charge = 0.8
        carrier.pass_target = s.slot_players[1]
        carrier.windup_timer = fixed_clock.TICK_SECONDS * 2
        carrier.windup_shot = {
            dir = carrier.facing,
            speed = 500,
            vz = 0,
            spin = 0,
            shot_type = "ground",
        }
        s.ball.x, s.ball.y = 325, 270
        s.ball_vel.x, s.ball_vel.y = 1000, 0

        match.step(s, fixed_clock.TICK_SECONDS, frame(0))

        t.eq(s.owner, nil, "the fast touch runs outside the carrier's control radius")
        t.eq(carrier.charge, 0)
        t.eq(carrier.pass_charge, 0)
        t.eq(carrier.pass_target, nil)
        t.eq(carrier.windup_timer, 0)
        t.eq(carrier.windup_shot, nil, "the loss tick clears the pending release")

        s.owner = carrier_idx
        s.ball = carrier.pos:add(carrier.facing:scale(18))
        s.ball_vel.x, s.ball_vel.y = 0, 0
        match.step(s, fixed_clock.TICK_SECONDS, frame(1))
        t.eq(s.owner, carrier_idx, "reacquisition cannot release the cancelled wind-up")
        for _, event in ipairs(s.events) do
            t.is_true(event.kind ~= "shot", "no stale shot event can fire after reacquisition")
        end
    end)

    t.it("keeps concurrent holds and wind-up cancellation on their owning players", function()
        local s = new_match()
        local first = assert(s.owner)
        local first_slot = assert(s.slot_for_player[first])
        local second_slot = 5
        local second = s.slot_players[second_slot]

        local pass_hold = assert(input_frame.new_sample({ held = input_frame.HELD_BITS.pass }))
        match.step(s, fixed_clock.TICK_SECONDS, frame(0, { [first_slot] = pass_hold }))
        t.is_true(s.players[first].pass_charge > 0, "the carrier owns its pass charge")
        t.is_true(s.players[first].pass_target ~= nil, "the carrier owns its pass preview")

        s.owner = second
        s.ball = s.players[second].pos:add(s.players[second].facing:scale(18))
        s.ball_vel.x, s.ball_vel.y = 0, 0
        local shot_hold = assert(input_frame.new_sample({ held = input_frame.HELD_BITS.shoot }))
        match.step(
            s,
            fixed_clock.TICK_SECONDS,
            frame(1, { [first_slot] = pass_hold, [second_slot] = shot_hold })
        )

        t.eq(s.players[first].pass_charge, 0, "possession loss cancels only the old owner")
        t.eq(s.players[first].pass_target, nil, "the old owner's preview is cleared")
        t.is_true(s.players[second].charge > 0, "the new owner's simultaneous hold is independent")

        local shot_release = assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.shoot }))
        match.step(s, fixed_clock.TICK_SECONDS, frame(2, { [second_slot] = shot_release }))
        t.is_true(s.players[second].windup_shot ~= nil, "release commits the owning player's shot")
        t.is_true(s.players[second].windup_timer > 0)

        s.owner = first
        s.ball = s.players[first].pos:add(s.players[first].facing:scale(18))
        match.step(s, fixed_clock.TICK_SECONDS, frame(3))
        t.eq(s.players[second].windup_shot, nil, "possession loss cancels the pending payload")
        t.eq(s.players[second].windup_timer, 0, "cancellation cannot release on a later possession")
    end)

    t.it(
        "resolves simultaneous pass and tackle releases without overwriting either slot",
        function()
            local s = new_match()
            local passer = assert(s.owner)
            local passer_slot = assert(s.slot_for_player[passer])
            local defender_slot = 5
            local defender = s.slot_players[defender_slot]
            s.players[defender].pos.x = s.field.w - 80
            s.players[defender].pos.y = 60

            local pass_release =
                assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.pass }))
            local tackle_release =
                assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.dash }))
            match.step(
                s,
                fixed_clock.TICK_SECONDS,
                frame(0, {
                    [passer_slot] = pass_release,
                    [defender_slot] = tackle_release,
                })
            )

            t.is_true(s.owner ~= passer, "the passer's release is consumed")
            t.is_true(
                s.players[defender].tackle_timer > 0,
                "the defender's release is also consumed"
            )
            local saw_pass = false
            for _, event in ipairs(s.events) do
                if event.kind == "pass" and event.player == s.players[passer].id then
                    saw_pass = true
                end
            end
            t.is_true(saw_pass, "the pass action remains attributed to its owning slot")
        end
    )

    t.it("resolves a direct same-tick tackle before the carrier's pass release", function()
        local s = new_match()
        local passer = assert(s.owner)
        local passer_slot = assert(s.slot_for_player[passer])
        local defender_slot = 5
        local defender = s.players[s.slot_players[defender_slot]]
        defender.pos = s.ball

        local pass_release = assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.pass }))
        local tackle_release =
            assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.dash }))
        match.step(
            s,
            fixed_clock.TICK_SECONDS,
            frame(0, {
                [passer_slot] = pass_release,
                [defender_slot] = tackle_release,
            })
        )

        local saw_tackle, saw_pass = false, false
        for _, event in ipairs(s.events) do
            saw_tackle = saw_tackle or event.kind == "tackle"
            saw_pass = saw_pass or event.kind == "pass"
        end
        t.is_true(saw_tackle, "the in-range release wins the ball")
        t.is_true(not saw_pass, "canonical movement/tackle priority cancels the later pass")
        t.eq(s.players[passer].pass_charge, 0, "the dispossessed carrier ends the tick clean")
    end)

    t.it("keeps slot selection fixed through switching, keeper capture, and kickoff", function()
        local slot_capture = new_match()
        local legacy_capture = new_legacy_match()

        ---@param s MatchState
        local function setup_capture(s)
            s.controlled = 2
            s.owner = nil
            s.players[1].pos.x, s.players[1].pos.y = 60, 270
            s.ball.x, s.ball.y = 65, 270
            s.ball_vel.x, s.ball_vel.y = 0, 0
            s.pickup_cd = 0
        end

        setup_capture(slot_capture)
        setup_capture(legacy_capture)
        local switch = assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.switch }))
        match.step(slot_capture, fixed_clock.TICK_SECONDS, frame(0, { [1] = switch }))
        match.step(legacy_capture, fixed_clock.TICK_SECONDS, slot_input.neutral_match_input())

        t.eq(slot_capture.owner, 1, "the loose ball is actually captured by the home keeper")
        t.eq(legacy_capture.owner, 1, "the legacy comparison reaches the same keeper capture")
        t.eq(slot_capture.controlled, 2, "switch and keeper capture cannot reselect in slot mode")
        t.eq(legacy_capture.controlled, 1, "legacy mode still hands a new capture to the keeper")
        t.eq(slot_capture.slot_for_player[1], nil, "keeper capture never creates a keeper slot")

        for _, player in ipairs(slot_capture.players) do
            player.pos.y = 50
        end
        slot_capture.owner = nil
        slot_capture.pickup_cd = 1
        slot_capture.ball.x, slot_capture.ball.y =
            slot_capture.field.w - 7, slot_capture.field.h / 2
        slot_capture.ball_vel.x, slot_capture.ball_vel.y = 1000, 0
        slot_capture.ball_z, slot_capture.ball_vz = 0, 0
        match.step(slot_capture, fixed_clock.TICK_SECONDS, frame(1))

        t.eq(slot_capture.score.home, 1, "the forced goal reaches the kickoff path")
        t.eq(slot_capture.controlled, 2, "kickoff does not rewrite slot-mode selection metadata")
        t.eq(slot_capture.slot_for_player[1], nil, "the restarted keeper remains AI-only")
    end)

    t.it("keeps online input off the keeper while deterministic keeper AI distributes", function()
        local s = new_match()
        local selected = s.slot_players[1]
        local keeper = s.players[1]
        s.controlled = selected
        s.owner = 1
        keeper.pos.x, keeper.pos.y = 60, s.field.h / 2
        keeper.facing.x, keeper.facing.y = 1, 0
        keeper.hold_timer = 0
        s.ball = keeper.pos
        local attempted_keeper_pass =
            assert(input_frame.new_sample({ edges = input_frame.EDGE_BITS.pass }))
        match.step(s, fixed_clock.TICK_SECONDS, frame(0, { [1] = attempted_keeper_pass }))

        t.eq(s.slot_for_player[1], nil, "no frame row can route to the keeper")
        t.eq(s.controlled, selected, "keeper possession cannot change slot selection")
        t.is_true(s.owner ~= 1, "the keeper AI releases the ball on its own schedule")
        local distributed = false
        for _, event in ipairs(s.events) do
            if (event.kind == "pass" or event.kind == "shot") and event.player == keeper.id then
                distributed = true
            end
        end
        t.is_true(distributed, "the keeper AI owns distribution in slot mode")
    end)

    t.it(
        "materializes only explicitly bot-configured slots from independent seeded streams",
        function()
            local sources = frame_sources()
            sources[1] = { kind = "bot", seed = 901 }
            sources[5] = { kind = "bot", seed = 902 }
            local left = new_match()
            local right = new_match()
            local left_producer = slot_input.new_producer(sources)
            local right_producer = slot_input.new_producer(sources)
            for tick = 0, 30 do
                local base = frame(tick)
                local left_frame = slot_input.materialize(left_producer, left, base)
                local right_frame = slot_input.materialize(right_producer, right, base)
                match.step(left, fixed_clock.TICK_SECONDS, left_frame)
                match.step(right, fixed_clock.TICK_SECONDS, right_frame)
            end
            for index = 1, #left.players do
                t.near(left.players[index].pos.x, right.players[index].pos.x, 1e-9)
                t.near(left.players[index].pos.y, right.players[index].pos.y, 1e-9)
            end
            t.eq(left_producer.sources[1].seed, 901)
            t.eq(left_producer.sources[5].seed, 902)
            t.eq(left_producer.sources[2].kind, "frame")
        end
    )

    t.it("rejects non-finite bot seeds", function()
        local sources = frame_sources()
        ---@type any
        local positive_infinity = math.huge
        sources[1] = { kind = "bot", seed = positive_infinity }
        t.is_true(
            not pcall(slot_input.new_producer, sources),
            "positive infinity cannot seed a bot"
        )

        ---@type any
        local negative_infinity = -math.huge
        sources[1] = { kind = "bot", seed = negative_infinity }
        t.is_true(
            not pcall(slot_input.new_producer, sources),
            "negative infinity cannot seed a bot"
        )

        ---@type any
        local nan = 0 / 0
        sources[1] = { kind = "bot", seed = nan }
        t.is_true(not pcall(slot_input.new_producer, sources), "NaN cannot seed a bot")
    end)

    t.it("rejects seeds on non-bot slot sources", function()
        local sources = frame_sources()
        sources[1] = { kind = "frame", seed = 73 }
        t.is_true(
            not pcall(slot_input.new_producer, sources),
            "frame rows cannot carry bot seed identity"
        )

        sources[1] = { kind = "neutral", seed = 73 }
        t.is_true(
            not pcall(slot_input.new_producer, sources),
            "neutral rows cannot carry bot seed identity"
        )
    end)

    t.it("canonicalizes stored bot seeds before materializing", function()
        local sources = frame_sources()
        sources[1] = { kind = "bot", seed = -901 }
        local producer = slot_input.new_producer(sources)
        t.eq(producer.sources[1].seed, 901)
    end)

    t.it("materializes frame, neutral, and quantized bot rows before sim.match", function()
        local s = new_match()
        local sources = frame_sources()
        sources[2] = { kind = "neutral" }
        sources[3] = { kind = "bot", seed = 901 }
        local producer = slot_input.new_producer(sources)
        local source_sample = assert(input_frame.new_sample({ move_x = 42, edges = 1 }))
        local effective = slot_input.materialize(producer, s, frame(0, { [1] = source_sample }))

        t.eq(effective.slots[1].move_x, 42, "frame rows are copied")
        t.eq(effective.slots[2].move_x, 0, "neutral rows are rewritten")
        t.is_true(effective.slots[3].move_x >= -127 and effective.slots[3].move_x <= 127)
        t.is_true(effective.slots[3].held >= 0 and effective.slots[3].edges >= 0)
        t.is_true(producer.bots[3] ~= nil, "only the producer owns bot RNG state")
    end)

    t.it("replays effective bot-filled frames with an all-frame producer", function()
        local sources = {}
        for index = 1, input_frame.SLOT_COUNT do
            sources[index] = { kind = "bot", seed = 400 + index }
        end
        local live = new_match()
        local producer = slot_input.new_producer(sources)
        local recording = {}
        for tick = 0, 120 do
            local effective = slot_input.materialize(producer, live, frame(tick))
            recording[tick + 1] = effective
            match.step(live, fixed_clock.TICK_SECONDS, effective)
        end

        local replay = new_match()
        local all_frame = slot_input.new_producer(frame_sources())
        t.is_true(next(all_frame.bots) == nil, "the replay producer has no bot state")
        for _, recorded in ipairs(recording) do
            local effective = slot_input.materialize(all_frame, replay, recorded)
            match.step(replay, fixed_clock.TICK_SECONDS, effective)
        end

        t.eq(replay.score.home, live.score.home)
        t.eq(replay.score.away, live.score.away)
        t.eq(replay.owner, live.owner)
        t.eq(replay.rng, live.rng)
        t.eq(replay.input_tick, live.input_tick)
        t.near(replay.ball.x, live.ball.x, 1e-12)
        t.near(replay.ball.y, live.ball.y, 1e-12)
        for index = 1, #live.players do
            t.near(replay.players[index].pos.x, live.players[index].pos.x, 1e-12)
            t.near(replay.players[index].pos.y, live.players[index].pos.y, 1e-12)
        end
    end)

    t.it("requires the exact fixed tick interval in slot mode", function()
        local s = new_match()
        local ok = pcall(match.step, s, fixed_clock.TICK_SECONDS * 2, frame(0))
        t.is_true(not ok)
    end)

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
            equipment_held = false,
            equipment_pressed = false,
            equipment_released = false,
        }
        local ok = pcall(function()
            match.step(s, fixed_clock.TICK_SECONDS, legacy_input)
        end)
        t.is_true(not ok)
    end)
end)
