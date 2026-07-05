local t = require("spec.support.runner")
local Match = require("game.screens.match")

t.describe("match screen rematch (tier 2)", function()
    t.it("R restarts a finished match with the same pre-match choices", function()
        local m = Match.new({ formation = "2-1-1", tactic = "press_high" })
        t.eq(m.state.press.home, 2, "tactic applied to the first match")
        m.state.finished = true
        m.state.score.home = 3
        m:event({ kind = "key", key = "r" })
        t.is_true(not m.state.finished, "a fresh match is underway")
        t.eq(m.state.score.home, 0, "the score is reset")
        t.eq(#m.state.players, 10)
        t.eq(m.state.press.home, 2, "the tactic choice carries into the rematch")
    end)

    t.it("Enter also triggers the rematch", function()
        local m = Match.new()
        m.state.finished = true
        m:event({ kind = "key", key = "return" })
        t.is_true(not m.state.finished)
    end)

    t.it("ignores the rematch keys while the match is live", function()
        local m = Match.new()
        local before = m.state
        m:event({ kind = "key", key = "r" })
        t.is_true(m.state == before, "no restart mid-match")
    end)

    t.it("ignores match inputs after full time", function()
        local m = Match.new()
        m.state.finished = true
        m:event({ kind = "key", key = "k" })
        t.is_true(not m._pass, "pass input does not buffer on the full-time screen")
    end)
end)

t.describe("match screen contextual controls (tier 2)", function()
    t.it("K never switches while carrying the ball (it charges a pass)", function()
        local m = Match.new() -- at kickoff the controlled player has the ball
        m:event({ kind = "key", key = "k" })
        t.is_true(not m._switch, "on the ball, K is the (polled) pass charge, not a switch")
    end)

    t.it("K switches player when not carrying", function()
        local m = Match.new()
        m.state.owner = nil
        m:event({ kind = "key", key = "k" })
        t.is_true(m._switch, "K is a switch off the ball")
        t.is_true(not m._pass)
    end)

    t.it("Space hold = jockey, release = poke (off the ball)", function()
        -- Drive polled inputs with a stubbed keyboard (same pattern as lob-latch test).
        local saved = love.keyboard
        local down = {}
        love.keyboard = {
            isDown = function(...)
                for _, k in ipairs({ ... }) do
                    if down[k] then
                        return true
                    end
                end
                return false
            end,
        }
        -- Off the ball: holding Space produces jockey stance (jockey_timer > 0).
        local m = Match.new()
        m.state.owner = nil
        m.state.pickup_cd = 5 -- nobody picks the ball up during this test
        local me = m.state.players[m.state.controlled]
        down.space = true
        m:update(1 / 60) -- hold one frame
        t.is_true(me.jockey_timer > 0, "holding Space off the ball engages jockey stance")
        -- _space_held_prev is set; release now → poke fires next update.
        -- The poke manifests as tackle_timer > 0 on the controlled player.
        me.tackle_cd = 0 -- ensure the poke isn't blocked by cooldown
        me.slide_timer = 0
        down.space = false
        m:update(1 / 60) -- release
        t.is_true(me.tackle_timer > 0, "releasing Space off the ball fires the poke")
        love.keyboard = saved
    end)

    t.it("Space never produces a poke while carrying (it charges the shot)", function()
        local saved = love.keyboard
        local down = {}
        love.keyboard = {
            isDown = function(...)
                for _, k in ipairs({ ... }) do
                    if down[k] then
                        return true
                    end
                end
                return false
            end,
        }
        local m = Match.new() -- carrying at kickoff
        down.space = true
        m:update(1 / 60) -- hold while carrying
        down.space = false
        local me = m.state.players[m.state.controlled]
        local tackle_before = me.tackle_timer
        m:update(1 / 60) -- release while still carrying
        t.is_true(
            me.tackle_timer == tackle_before,
            "Space release while carrying does not fire a poke"
        )
        love.keyboard = saved
    end)
end)

t.describe("match screen lob latch (tier 2)", function()
    -- Drive the polled inputs with a stubbed keyboard.
    local function with_keys(fn)
        local saved = love.keyboard
        local down = {}
        love.keyboard = {
            isDown = function(...)
                for _, k in ipairs({ ... }) do
                    if down[k] then
                        return true
                    end
                end
                return false
            end,
        }
        local ok, err = pcall(fn, down)
        love.keyboard = saved
        assert(ok, err)
    end

    t.it("L held during a charged pass lofts it even if L lifts a frame early", function()
        with_keys(function(down)
            local m = Match.new() -- carrying at kickoff
            down.k, down.l = true, true
            m:update(1 / 60) -- charging the pass with L held
            m:update(1 / 60)
            down.l = false
            m:update(1 / 60) -- L released a beat before K...
            down.k = false
            m:update(1 / 60) -- ...K release fires the pass
            t.is_true(m.state.owner ~= m.state.controlled, "the pass released")
            t.is_true(m.state.ball_vz > 0, "and it was lofted: the latch held L for us")
        end)
    end)

    t.it("holding K charges the pass range for an outfielder", function()
        with_keys(function(down)
            local m = Match.new()
            down.k = true
            for _ = 1, 30 do -- half a second of holding K
                m:update(1 / 60)
            end
            t.is_true(m.state.pass_charge > 0.5, "the pass range charged up")
        end)
    end)
end)
