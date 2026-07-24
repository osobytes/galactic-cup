local Vec2 = require("core.vec2")
local match_input_adapter = require("game.match_input_adapter")
local fixed_clock = require("sim.fixed_clock")
local t = require("spec.support.runner")

---@param opts { shoot: boolean?, shoot_held: boolean?, pass: boolean?, pass_held: boolean?, switch: boolean?, dash: boolean?, dodge: boolean?, lob: boolean?, sprint: boolean?, jockey: boolean?, equipment_held: boolean?, equipment_pressed: boolean?, equipment_released: boolean? }?
---@return MatchInput
local function input(opts)
    opts = opts or {}
    return {
        move = Vec2.new(0.5, -0.25),
        shoot = opts.shoot == true,
        shoot_held = opts.shoot_held == true,
        pass = opts.pass == true,
        pass_held = opts.pass_held == true,
        switch = opts.switch == true,
        dash = opts.dash == true,
        dodge = opts.dodge == true,
        lob = opts.lob == true,
        sprint = opts.sprint == true,
        jockey = opts.jockey == true,
        equipment_held = opts.equipment_held == true,
        equipment_pressed = opts.equipment_pressed == true,
        equipment_released = opts.equipment_released == true,
    }
end

t.describe("offline match input adapter", function()
    t.it("holds a release edge through a zero-tick render update and consumes it once", function()
        local adapter = match_input_adapter.sample(
            match_input_adapter.new(),
            input({ shoot = true, lob = true })
        )
        local clock = fixed_clock.new()
        local consumed = {}

        fixed_clock.advance(clock, 1 / 120, function(_)
            local next, tick_input = match_input_adapter.next_tick(adapter)
            adapter = next
            return tick_input
        end, function(_, tick_input)
            consumed[#consumed + 1] = tick_input
        end)
        t.eq(#consumed, 0)

        fixed_clock.advance(clock, 1 / 120, function(_)
            local next, tick_input = match_input_adapter.next_tick(adapter)
            adapter = next
            return tick_input
        end, function(_, tick_input)
            consumed[#consumed + 1] = tick_input
        end)
        t.eq(#consumed, 1)
        t.is_true(consumed[1].shoot)
        t.is_true(consumed[1].lob, "the paired lob modifier is preserved for the release")

        local next_adapter, later = match_input_adapter.next_tick(adapter)
        t.is_true(not later.shoot)
        t.is_true(later.lob, "the modifier remains held until the next render sample")

        next_adapter = match_input_adapter.sample(next_adapter, input())
        local _, released = match_input_adapter.next_tick(next_adapter)
        t.is_true(not released.lob)
    end)

    t.it("emits edges only on the first catch-up tick while preserving holds", function()
        local adapter = match_input_adapter.sample(
            match_input_adapter.new(),
            input({
                pass = true,
                pass_held = true,
                sprint = true,
                jockey = true,
                equipment_held = true,
                equipment_pressed = true,
            })
        )
        local first_state, first = match_input_adapter.next_tick(adapter)
        local _, second = match_input_adapter.next_tick(first_state)
        t.is_true(first.pass)
        t.is_true(first.pass_held)
        t.is_true(first.sprint)
        t.is_true(first.jockey)
        t.is_true(first.equipment_held)
        t.is_true(first.equipment_pressed)
        t.is_true(not first.equipment_released)
        t.is_true(not second.pass)
        t.is_true(second.pass_held)
        t.is_true(second.sprint)
        t.is_true(second.jockey)
        t.is_true(second.equipment_held)
        t.is_true(not second.equipment_pressed)
        t.is_true(not second.equipment_released)
    end)

    t.it("folds all canonical equipment transition sequences", function()
        ---@param previous_held boolean
        ---@param samples MatchInput[]
        ---@return MatchInput
        local function fold(previous_held, samples)
            local adapter = match_input_adapter.new()
            if previous_held then
                adapter = match_input_adapter.sample(
                    adapter,
                    input({ equipment_held = true, equipment_pressed = true })
                )
                adapter = select(1, match_input_adapter.next_tick(adapter))
            end
            for _, sample in ipairs(samples) do
                adapter = match_input_adapter.sample(adapter, sample)
            end
            local _, tick_input = match_input_adapter.next_tick(adapter)
            return tick_input
        end

        local up_idle = fold(false, { input() })
        t.is_true(not up_idle.equipment_held)
        t.is_true(not up_idle.equipment_pressed)
        t.is_true(not up_idle.equipment_released)

        local pressed = fold(false, { input({ equipment_held = true }) })
        t.is_true(pressed.equipment_held)
        t.is_true(pressed.equipment_pressed)
        t.is_true(not pressed.equipment_released)

        local fast_tap = fold(false, {
            input({ equipment_held = true, equipment_pressed = true }),
            input({ equipment_released = true }),
        })
        t.is_true(not fast_tap.equipment_held)
        t.is_true(fast_tap.equipment_pressed)
        t.is_true(fast_tap.equipment_released)

        local down_idle = fold(true, { input({ equipment_held = true }) })
        t.is_true(down_idle.equipment_held)
        t.is_true(not down_idle.equipment_pressed)
        t.is_true(not down_idle.equipment_released)

        local released = fold(true, { input({ equipment_released = true }) })
        t.is_true(not released.equipment_held)
        t.is_true(not released.equipment_pressed)
        t.is_true(released.equipment_released)

        local release_repress = fold(true, {
            input({ equipment_released = true }),
            input({ equipment_held = true, equipment_pressed = true }),
        })
        t.is_true(release_repress.equipment_held)
        t.is_true(release_repress.equipment_pressed)
        t.is_true(not release_repress.equipment_released)
    end)
end)
