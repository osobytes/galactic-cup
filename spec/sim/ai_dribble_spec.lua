local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local Vec2 = require("core.vec2")

---@type MatchInput
local NO_INPUT = {
    move = Vec2.new(0, 0),
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

---@return MatchState, integer, integer
local function scenario()
    local s = match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        human_controlled = false,
        seed = 17,
    })
    local carrier = 2
    local defender = 7
    s.owner = carrier
    local p = s.players[carrier]
    p.pos = Vec2.new(260, 270)
    p.facing = Vec2.new(1, 0)
    p.run_vel = Vec2.new(0, 0)
    s.ball = p.pos:add(Vec2.new(18, 0))
    for i, q in ipairs(s.players) do
        if i ~= carrier then
            q.pos = q.team == "home" and Vec2.new(80, 40 + i * 35) or Vec2.new(820, 40 + i * 35)
            q.anchor = q.pos
        end
    end
    return s, carrier, defender
end

t.describe("team AI dribble intent", function()
    t.it("sprints into genuine open space and produces a knock-on touch", function()
        local s, carrier = scenario()
        local touched = false
        for _ = 1, 45 do
            match.step(s, 1 / 60, NO_INPUT)
            t.is_true(s.owner == carrier, "open-space carry remains controlled")
            for _, e in ipairs(s.events) do
                touched = touched or (e.kind == "touch" and e.player == s.players[carrier].id)
            end
        end
        t.is_true(s.players[carrier].sprinting, "the AI spends stamina when runway is clear")
        t.is_true(touched, "sprint pace enters the risky kick-and-chase branch")
    end)

    t.it("stays in close control when a defender blocks the runway", function()
        local s, carrier, defender = scenario()
        s.players[defender].pos = Vec2.new(320, 270)
        match.step(s, 1 / 60, NO_INPUT)
        t.is_true(not s.players[carrier].sprinting, "nearby pressure suppresses the knock-on")
    end)

    t.it("jukes away from a committed defender", function()
        local s, carrier, defender = scenario()
        local p = s.players[carrier]
        local threat = s.players[defender]
        p.settle_timer = 1 -- isolate the juke; do not immediately pass after it
        threat.pos = Vec2.new(300, 280)
        threat.tackle_timer = 0.2
        match.step(s, 1 / 60, NO_INPUT)
        t.eq(s.owner, carrier, "juke immunity preserves possession through the poke")
        t.is_true(p.dodge_timer > 0, "AI entered the real juke state")
        local emitted = false
        for _, e in ipairs(s.events) do
            emitted = emitted or (e.kind == "juke" and e.player == p.id)
        end
        t.is_true(emitted, "telemetry can see the decision")
        t.is_true(p.dodge_dir.y < 0, "sidestep goes away from the defender's side")
    end)
end)
