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

    t.it("Space tackles only when not carrying", function()
        local m = Match.new()
        m.state.owner = nil
        m:event({ kind = "key", key = "space" })
        t.is_true(m._dash, "Space is a tackle off the ball")

        local m2 = Match.new()
        m2:event({ kind = "key", key = "space" })
        t.is_true(not m2._dash, "Space never tackles while carrying (it shoots via hold)")
    end)
end)
