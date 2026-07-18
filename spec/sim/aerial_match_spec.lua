local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local Vec2 = require("core.vec2")

---@param overrides table?
---@return MatchInput
local function input(overrides)
    overrides = overrides or {}
    return {
        move = overrides.move or Vec2.new(0, 0),
        shoot = false,
        shoot_held = false,
        pass = false,
        pass_held = false,
        switch = false,
        dash = false,
        dodge = false,
        lob = overrides.lob or false,
        sprint = false,
        jockey = false,
        aerial_strike = overrides.aerial_strike or false,
        aerial_acrobatic = overrides.aerial_acrobatic or false,
    }
end

---@param seed integer
---@return MatchState
local function new_match(seed)
    return match.new({
        home = teams.nebula,
        away = teams.orion,
        field = { w = 960, h = 540 },
        seed = seed,
    })
end

---@param s MatchState
---@param ball_z number
---@param behind boolean?
local function setup_contact(s, ball_z, behind)
    local receiver = s.players[s.controlled]
    receiver.pos = Vec2.new(500, 270)
    receiver.run_vel = Vec2.new(0, 0)
    receiver.vel = Vec2.new(0, 0)
    receiver.facing = Vec2.new(1, 0)
    receiver.receive_timer = 1
    receiver.header_cd = 0
    receiver.aerial_recovery = 0
    for i, player in ipairs(s.players) do
        if i ~= s.controlled then
            player.pos = Vec2.new((player.team == "home") and 80 or 880, 30 + i * 42)
        end
    end
    s.owner = nil
    s.pickup_cd = 0
    s.aerial_lock = 0
    local offset = (behind == false) and 18 or (behind and -6 or 6)
    s.ball = receiver.pos:add(Vec2.new(offset, 0))
    s.ball_vel = Vec2.new(0, 0)
    s.ball_z = ball_z
    s.ball_vz = -50
end

---@param s MatchState
---@param kind string
---@return MatchEvent?
local function event_of(s, kind)
    for _, event in ipairs(s.events) do
        if event.kind == kind then
            return event
        end
    end
    return nil
end

---@param ball_z number
---@param wanted AerialOutcome
---@return MatchState
local function reception_with_outcome(ball_z, wanted)
    for seed = 1, 200 do
        local s = new_match(seed)
        setup_contact(s, ball_z)
        match.step(s, 1 / 60, input())
        local event = event_of(s, "reception")
        if event and event.outcome == wanted then
            return s
        end
    end
    error("no seeded reception outcome: " .. wanted)
end

t.describe("match aerial reception and acrobatic finishing", function()
    t.it("chest-controls a lob toward the feet without strike input", function()
        local s = reception_with_outcome(56, "clean")
        local event = assert(event_of(s, "reception"))
        t.eq(event.style, "chest_control")
        t.eq(s.owner, nil, "the chest touch redirects the real ball before foot possession")
        t.is_true(s.ball_vz < 0, "the chest cushions the ball downward")
        t.is_true(s.players[s.controlled].receive_timer > 0, "receiver follows the second touch")

        for _ = 1, 60 do
            match.step(s, 1 / 60, input())
            if s.owner then
                break
            end
        end
        t.eq(s.owner, s.controlled, "the redirected ball is gathered at the feet")
    end)

    t.it("uses an extended leg for a lower aerial reception", function()
        local s = reception_with_outcome(30, "clean")
        local event = assert(event_of(s, "reception"))
        t.eq(event.style, "leg_control")
    end)

    t.it("keeps a heavy reception loose and contestable", function()
        local s = reception_with_outcome(56, "heavy")
        local event = assert(event_of(s, "reception"))
        t.eq(event.outcome, "heavy")
        t.eq(s.owner, nil)
        t.is_true(s.ball_vel:length() > 0)
    end)

    t.it("produces a jumping volley below the header band", function()
        local s = new_match(12)
        setup_contact(s, 43)
        match.step(s, 1 / 60, input({ aerial_strike = true }))
        local event = assert(event_of(s, "volley"))
        t.is_true(event.jumping)
        t.is_true(s.players[s.controlled].aerial_jump > 0)
    end)

    t.it("produces a jumping header above standing reach", function()
        local s = new_match(12)
        setup_contact(s, 90)
        match.step(s, 1 / 60, input({ aerial_strike = true }))
        local event = assert(event_of(s, "header"))
        t.is_true(event.jumping)
        t.is_true(s.players[s.controlled].aerial_jump > 0)
    end)

    t.it("attempts a bicycle for an overhead ball and commits to recovery", function()
        local s = new_match(12)
        setup_contact(s, 60, true)
        match.step(
            s,
            1 / 60,
            input({
                lob = true,
                aerial_strike = true,
                aerial_acrobatic = true,
            })
        )
        local event = assert(event_of(s, "bicycle"))
        t.eq(event.style, "bicycle")
        t.is_true(event.jumping)
        t.is_true(s.players[s.controlled].aerial_recovery > 0.5)
    end)

    t.it("falls back to a conventional strike when bicycle geometry is invalid", function()
        local s = new_match(12)
        setup_contact(s, 60, false)
        match.step(
            s,
            1 / 60,
            input({
                lob = true,
                aerial_strike = true,
                aerial_acrobatic = true,
            })
        )
        t.eq(event_of(s, "bicycle"), nil)
        t.is_true(event_of(s, "header") ~= nil or event_of(s, "volley") ~= nil)
    end)
end)
