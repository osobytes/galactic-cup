local t = require("spec.support.runner")
local match = require("sim.match")
local teams = require("data.teams")
local tactics = require("data.tactics")
local Vec2 = require("core.vec2")

local function new_match()
    return match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
end

---@param o table?
---@return MatchInput
local function input(o)
    o = o or {}
    return {
        move = o.move or Vec2.new(0, 0),
        shoot = o.shoot or false,
        shoot_held = o.shoot_held or false,
        pass = o.pass or false,
        pass_held = o.pass_held or false,
        switch = o.switch or false,
        dash = o.dash or false,
        dodge = o.dodge or false,
        lob = o.lob or false,
        sprint = o.sprint or false,
    }
end

local NO_INPUT = input()

t.describe("match.new", function()
    t.it("kicks off with 10 players and the home side in possession", function()
        local s = new_match()
        t.eq(#s.players, 10)
        t.is_true(s.owner == s.controlled, "controlled player should start with the ball")
        t.eq(s.score.home, 0)
        t.eq(s.score.away, 0)
        t.is_true(s.players[s.controlled].team == "home")
        t.is_true(not s.players[s.controlled].is_keeper)
    end)
end)

t.describe("match.step timer", function()
    t.it("counts down and ends at full time", function()
        local s = new_match()
        match.step(s, 10, NO_INPUT)
        t.near(s.time_left, 110, 1e-6)
        t.is_true(not s.finished)
        match.step(s, 200, NO_INPUT)
        t.is_true(s.finished)
        t.eq(s.time_left, 0)
    end)
end)

t.describe("match.step shooting & passing", function()
    t.it("shooting releases the ball toward the goal", function()
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(1, 0)
        match.step(s, 0.016, input({ shoot = true }))
        t.is_true(s.owner == nil)
        t.is_true(s.ball_vel.x > 0, "home shoots toward the right goal")
    end)

    t.it("aiming up sends the shot to the top corner", function()
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(0, -1)
        match.step(s, 0.016, input({ shoot = true }))
        t.is_true(s.owner == nil)
        t.is_true(s.ball_vel.x > 0, "still goal-ward")
        t.is_true(s.ball_vel.y < 0, "and toward the top corner")
    end)

    t.it("passing sends the ball toward a teammate in the aim direction", function()
        local s = new_match()
        local owner = s.players[s.controlled]
        local mate
        for i, p in ipairs(s.players) do
            if p.team == "home" and i ~= s.controlled then
                mate = p
                break
            end
        end
        owner.facing = mate.pos:sub(owner.pos):normalized()
        match.step(s, 0.016, input({ pass = true }))
        t.is_true(s.owner == nil, "ball should be released on a pass")
        t.near(s.ball_vel:length(), 320, 0.5, "pass speed")
    end)
end)

t.describe("match.step charge shot", function()
    ---@param charge number
    ---@return number
    local function shot_speed(charge)
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(1, 0)
        s.charge = charge
        match.step(s, 0.016, input({ shoot = true }))
        return s.ball_vel:length()
    end

    t.it("a full charge shoots meaningfully harder than a tap", function()
        t.is_true(shot_speed(1) > shot_speed(0) * 1.5)
    end)

    t.it("holding shoot builds charge", function()
        local s = new_match()
        match.step(s, 0.1, input({ shoot_held = true }))
        t.is_true(s.charge > 0)
    end)
end)

t.describe("match.step juke", function()
    t.it("a dodging carrier is immune to tackles", function()
        local s = new_match()
        local me = s.players[s.controlled]
        local foe
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                foe = p
                break
            end
        end
        foe.pos = Vec2.new(me.pos.x + 8, me.pos.y)
        foe.dash_cd = 0
        me.dodge_timer = 1.0
        match.step(s, 0.016, input())
        t.is_true(s.owner == s.controlled, "dodging carrier keeps the ball")
    end)
end)

t.describe("match.step tackling", function()
    local function carrier_setup()
        local s = new_match()
        local away_idx
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                away_idx = i
                break
            end
        end
        s.owner = away_idx
        -- Challenges reach for the ball, so put it at the carrier's feet.
        local c = s.players[away_idx]
        s.ball = c.pos:add(c.facing:scale(18))
        -- Park the carrier's teammates out of passing range so it can't bail
        -- out of the challenge with a pressure pass.
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper and i ~= away_idx then
                p.pos = Vec2.new(40, 380 + i * 15)
            end
        end
        return s, away_idx, c
    end

    t.it("a standing tackle (slow) knocks the ball loose", function()
        local s, away_idx, carrier = carrier_setup()
        local me = s.players[s.controlled]
        -- stand on the BALL side (in front of the carrier), inside poke reach
        me.pos = Vec2.new(carrier.pos.x - 26, carrier.pos.y)
        me.vel = Vec2.new(0, 0) -- standing -> standing poke
        match.step(s, 0.016, input({ dash = true }))
        t.is_true(s.owner ~= away_idx, "carrier loses possession to the standing tackle")
    end)

    t.it("a slide (sprinting) wins the ball from further away and stuns the carrier", function()
        local s, away_idx, carrier = carrier_setup()
        local me = s.players[s.controlled]
        -- approach the BALL side (in front of the carrier), sprinting into a slide
        me.pos = Vec2.new(carrier.pos.x - 32, carrier.pos.y)
        me.vel = Vec2.new(200, 0)
        me.sprinting = true -- sprint + tackle = slide
        match.step(s, 0.016, input({ dash = true, move = Vec2.new(1, 0), sprint = true }))
        t.is_true(s.owner ~= away_idx, "slide wins the ball at extended reach")
        t.is_true(carrier.stun_timer > 0, "the slid-through carrier is knocked off balance")
    end)

    t.it("a carrier shields the ball from a challenge behind them", function()
        local s, away_idx, carrier = carrier_setup()
        carrier.facing = Vec2.new(-1, 0) -- ball sticks a step toward -x
        s.ball = carrier.pos:add(Vec2.new(-18, 0))
        local defender
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                defender = i
                break
            end
        end
        s.players[defender].pos = Vec2.new(carrier.pos.x + 20, carrier.pos.y) -- on their back
        s.players[defender].dash_cd = 0
        s.players[s.controlled].pos = Vec2.new(60, 60) -- human well away
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, away_idx, "the shielded ball stays with the carrier")
        t.is_true(s.players[defender].dash_cd > 0, "the failed poke still goes on cooldown")
    end)

    t.it("the same challenge from the ball side wins it", function()
        local s, away_idx, carrier = carrier_setup()
        carrier.facing = Vec2.new(-1, 0)
        s.ball = carrier.pos:add(Vec2.new(-18, 0))
        local defender
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                defender = i
                break
            end
        end
        s.players[defender].pos = Vec2.new(carrier.pos.x - 20, carrier.pos.y) -- goal side, on the ball
        s.players[defender].dash_cd = 0
        s.players[s.controlled].pos = Vec2.new(60, 60)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.owner ~= away_idx, "a front-on challenge dislodges the ball")
    end)

    t.it("the human can poke the ball loose from behind at contact range", function()
        local s, away_idx, carrier = carrier_setup()
        local me = s.players[s.controlled]
        me.pos = Vec2.new(carrier.pos.x + 24, carrier.pos.y) -- on the carrier's back
        me.vel = Vec2.new(0, 0)
        -- Chase while poking: the carrier dribbles away during the frame.
        match.step(s, 0.016, input({ dash = true, move = Vec2.new(-1, 0) }))
        t.is_true(s.owner ~= away_idx, "a contact-range poke wins even from behind")
    end)

    t.it("a jogging (non-sprint) tackle is a poke, not a slide", function()
        local s = new_match()
        local me = s.players[s.controlled]
        me.vel = Vec2.new(-150, 0) -- moving, but not sprinting
        match.step(s, 0.001, input({ dash = true, move = Vec2.new(-1, 0) }))
        t.is_true(me.slide_timer <= 0, "no committed slide without sprint")
        t.is_true(me.tackle_timer > 0, "a standing poke instead")
    end)

    t.it("slide speed scales with current velocity", function()
        local function slide_vel(speed)
            local s = new_match()
            local me = s.players[s.controlled]
            me.vel = Vec2.new(speed, 0)
            me.facing = Vec2.new(1, 0)
            me.sprinting = true
            match.step(s, 0.001, input({ dash = true, move = Vec2.new(1, 0), sprint = true }))
            return me.slide_vel
        end
        t.is_true(slide_vel(300) > slide_vel(150), "a faster run produces a faster slide")
    end)

    t.it("a stunned defender cannot tackle", function()
        local s, away_idx, carrier = carrier_setup()
        local me = s.players[s.controlled]
        me.pos = Vec2.new(carrier.pos.x + 8, carrier.pos.y)
        me.vel = Vec2.new(0, 0)
        me.stun_timer = 1.0
        match.step(s, 0.016, input({ dash = true }))
        t.is_true(s.owner == away_idx, "a stunned player can't win the ball")
    end)
end)

t.describe("match.step switching", function()
    t.it("hands control to the home outfielder nearest the ball", function()
        local s = new_match()
        local before = s.controlled
        -- Park a loose ball next to a specific teammate.
        local target
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= before then
                target = i
            end
        end
        s.owner = nil
        s.pickup_cd = 1
        s.ball = Vec2.new(s.players[target].pos.x + 30, s.players[target].pos.y)
        match.step(s, 0.016, input({ switch = true }))
        t.eq(s.controlled, target, "switch picks the player closest to the ball")
        t.is_true(s.players[s.controlled].team == "home")
        t.is_true(not s.players[s.controlled].is_keeper)
    end)
end)

t.describe("match tactics", function()
    ---@param s MatchState
    ---@return number
    local function mean_home_outfield_x(s)
        local sum, n = 0, 0
        for _, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper then
                sum = sum + p.anchor.x
                n = n + 1
            end
        end
        return sum / n
    end

    t.it("press high pushes the home shape higher up the pitch", function()
        local balanced = new_match()
        local high = match.new({
            home = teams.nebula,
            away = teams.orion,
            field = { w = 960, h = 540 },
            tactic = tactics.press_high,
        })
        t.is_true(mean_home_outfield_x(high) > mean_home_outfield_x(balanced))
    end)

    t.it("counter attack drops the home shape deeper", function()
        local balanced = new_match()
        local counter = match.new({
            home = teams.nebula,
            away = teams.orion,
            field = { w = 960, h = 540 },
            tactic = tactics.counter,
        })
        t.is_true(mean_home_outfield_x(counter) < mean_home_outfield_x(balanced))
    end)

    t.it("press high assigns two home pressers", function()
        local high = match.new({
            home = teams.nebula,
            away = teams.orion,
            field = { w = 960, h = 540 },
            tactic = tactics.press_high,
        })
        t.eq(high.press.home, 2)
    end)
end)

t.describe("match.step scoring", function()
    t.it("a ball wholly crossing the right goal line scores for home", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 1 -- keep anyone from collecting it
        s.ball = Vec2.new(s.field.w - 5, s.field.h / 2)
        s.ball_vel = Vec2.new(400, 0)
        for _ = 1, 10 do
            match.step(s, 0.016, NO_INPUT)
            if s.score.home > 0 then
                break
            end
        end
        t.eq(s.score.home, 1)
        t.eq(s.score.away, 0)
    end)

    t.it("a ball ON the line is not yet a goal (must wholly cross)", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 1
        -- Ball centre right on the goal line, barely moving: still in play.
        s.ball = Vec2.new(s.field.w, s.field.h / 2)
        s.ball_vel = Vec2.new(1, 0)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.score.home, 0, "on the line is not across the line")
    end)
end)

t.describe("match.step keeper", function()
    local function keeper_of(s, team)
        for i, p in ipairs(s.players) do
            if p.team == team and p.is_keeper then
                return i, p
            end
        end
    end

    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("catches a shot hit straight at it", function()
        local s = new_match()
        local ki, k = keeper_of(s, "away")
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(945, 270) -- between the ball and the goal
        s.ball = Vec2.new(925, 270)
        s.ball_vel = Vec2.new(100, 0) -- crosses the keeper's line right at it
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, ki, "keeper should hold the catch")
        t.near(s.ball_vel:length(), 0, 1e-6)
        t.eq(s.score.home, 0, "a catch concedes nothing")
        t.is_true(has_event(s, "catch"), "expected a catch event")
    end)

    t.it("parries a shot to its side it can reach but not gather", function()
        local s = new_match()
        local _, k = keeper_of(s, "away")
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(935, 300)
        s.ball = Vec2.new(890, 250)
        s.ball_vel = Vec2.new(380, 0) -- crosses to the keeper's side, fast: reachable, not catchable
        -- The save commits at once but completes when the ball ARRIVES at the
        -- diving keeper — play the flight out.
        local parried = false
        for _ = 1, 30 do
            match.step(s, 0.016, NO_INPUT)
            parried = parried or has_event(s, "parry")
            if parried then
                break
            end
        end
        t.is_true(parried, "expected a parry event")
        t.is_true(s.owner == nil, "a parry does not gain possession")
        t.is_true(s.ball_vel.x < 0, "ball is deflected back away from the goal")
        t.eq(s.score.home, 0)
    end)

    t.it("a saved shot flies its whole trajectory into the glove (no teleport)", function()
        local s = new_match()
        local _, k = keeper_of(s, "away")
        k.pos = Vec2.new(938, 270)
        s.owner = nil
        s.pickup_cd = 0.3 -- as if just released by the shooter
        s.ball = Vec2.new(738, 270) -- 200px out, straight at the keeper
        s.ball_vel = Vec2.new(500, 0)
        local caught_at, max_jump = nil, 0
        local prev = s.ball
        for f = 1, 60 do
            match.step(s, 1 / 60, NO_INPUT)
            max_jump = math.max(max_jump, prev:dist(s.ball))
            prev = s.ball
            if has_event(s, "catch") then
                caught_at = f
                break
            end
        end
        t.is_true(caught_at ~= nil, "the straight shot is caught")
        t.is_true(caught_at >= 12, "the ball spent real frames in flight (no zone snap)")
        t.is_true(max_jump < 60, "no single frame teleported the ball")
    end)

    t.it("is beaten when the shot crosses out of dive reach", function()
        local s = new_match()
        local _, k = keeper_of(s, "away")
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(945, 120) -- stuck high; can't reach a central shot in time
        s.ball = Vec2.new(880, 270)
        s.ball_vel = Vec2.new(520, 0)
        local saved = false
        for _ = 1, 30 do
            match.step(s, 0.016, NO_INPUT)
            if has_event(s, "catch") or has_event(s, "parry") then
                saved = true
            end
            if s.score.home > 0 then
                break
            end
        end
        t.eq(s.score.home, 1, "an unreachable shot scores")
        t.is_true(not saved, "keeper made no save")
    end)

    t.it("holds a gathered ball safe from a challenging striker", function()
        local s = new_match()
        local ki, k = keeper_of(s, "away")
        s.owner = ki
        k.hold_timer = 1 -- still holding (won't distribute this step)
        -- An AI striker right on top of the keeper, ready to challenge.
        local striker
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                striker = p
                break
            end
        end
        striker.pos = Vec2.new(k.pos.x + 10, k.pos.y)
        striker.dash_cd = 0
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, ki, "the keeper keeps the gathered ball")
        t.is_true(not has_event(s, "tackle"), "a keeper in possession can't be tackled")
    end)

    t.it("distributes to a teammate instead of hoofing it", function()
        local s = new_match()
        local ki, k = keeper_of(s, "home")
        for _, p in ipairs(s.players) do
            if p.team == "away" then
                p.pos = Vec2.new(950, 40) -- clear every outlet of pressure
            end
        end
        s.owner = ki
        k.hold_timer = 0 -- hold already elapsed: distribute this step
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.owner == nil, "the keeper releases the ball")
        -- A paced short throw (arrives with a touch left), not a long clear.
        local speed = s.ball_vel:length()
        t.is_true(speed >= 320 and speed <= 620, "throw pace is a pass, not a hoof")
        t.is_true(has_event(s, "pass"), "expected a pass event")
        t.is_true(not has_event(s, "shot"), "should not hoof it upfield")
    end)
end)

t.describe("match.step off-ball AI", function()
    -- indices: home 1..5 (keeper 1), away 6..10 (keeper 6)
    local AWAY_CARRIER = 7

    local function pos_of(s)
        local p = {}
        for i, pl in ipairs(s.players) do
            p[i] = pl.pos
        end
        return p
    end

    -- Home defenders (non-keeper, non-controlled) that received a target.
    local function home_targets(s, targets)
        local list = {}
        for i, pl in ipairs(s.players) do
            if pl.team == "home" and not pl.is_keeper and targets[i] then
                list[#list + 1] = i
            end
        end
        return list
    end

    -- Replicate the internal closest-to-carrier ordering for role identification.
    local function defender_order(s, p)
        local order = {}
        for i, pl in ipairs(s.players) do
            if pl.team == "home" and not pl.is_keeper and i ~= s.controlled then
                order[#order + 1] = i
            end
        end
        table.sort(order, function(a, b)
            local da, db = p[a]:dist(p[AWAY_CARRIER]), p[b]:dist(p[AWAY_CARRIER])
            if da ~= db then
                return da < db
            end
            return a < b
        end)
        return order
    end

    local function defending_state(scheme)
        local s = new_match()
        if scheme then
            s.marking.home.scheme = scheme
        end
        s.owner = AWAY_CARRIER
        s.players[AWAY_CARRIER].pos = Vec2.new(480, 270)
        s.ball = Vec2.new(480, 270)
        -- Spread the away side to its open-play anchors: kickoff clamps them
        -- to their own half, which would bunch every marker's man (and so the
        -- marker targets) right next to the carrier at the halfway line.
        for i, p in ipairs(s.players) do
            if p.team == "away" and i ~= AWAY_CARRIER then
                p.pos = Vec2.new(p.anchor.x, p.anchor.y)
            end
        end
        return s
    end

    t.it("sends exactly one presser to the carrier", function()
        local s = defending_state()
        local targets = match._offball_targets(s, pos_of(s))
        local carrier = s.players[AWAY_CARRIER].pos
        local near = 0
        for _, i in ipairs(home_targets(s, targets)) do
            if targets[i]:dist(carrier) <= 24 + 25 then
                near = near + 1
            end
        end
        t.eq(near, 1, "exactly one defender presses; the rest hold shape")
    end)

    t.it("positions the cover goal-side between carrier and own goal", function()
        local s = defending_state()
        local p = pos_of(s)
        local cover = defender_order(s, p)[2]
        local targets = match._offball_targets(s, p)
        t.is_true(cover ~= nil, "a cover defender exists")
        t.is_true(
            targets[cover].x > 5 and targets[cover].x < 480,
            "cover sits between own goal and the carrier"
        )
    end)

    t.it("shifts the defensive block toward the ball (zonal)", function()
        local s = defending_state("zonal")
        s.players[AWAY_CARRIER].pos = Vec2.new(480, 30) -- ball high near the top
        s.ball = Vec2.new(480, 30)
        local p = pos_of(s)
        local rest = defender_order(s, p)[3] -- a zone-holding defender
        local targets = match._offball_targets(s, p)
        t.is_true(rest ~= nil, "a zonal defender exists")
        t.is_true(
            targets[rest].y < s.players[rest].anchor.y,
            "the block slides up toward the high ball"
        )
    end)

    t.it("man-marks an opponent on the goal side", function()
        local s = defending_state("man")
        local targets = match._offball_targets(s, pos_of(s))
        local found = false
        for def, opp in pairs(s.marks.home) do
            found = true
            t.is_true(
                targets[def].x <= s.players[opp].pos.x + 1,
                "marker stands goal-side (lower x) of its man"
            )
        end
        t.is_true(found, "man scheme produced at least one mark")
    end)

    t.it("only man/hybrid schemes create marking assignments", function()
        local function marks_count(scheme)
            local s = defending_state(scheme)
            match._offball_targets(s, pos_of(s))
            local n = 0
            for _ in pairs(s.marks.home) do
                n = n + 1
            end
            return n
        end
        t.eq(marks_count("zonal"), 0)
        t.is_true(marks_count("man") >= 1, "man scheme assigns marks")
        t.is_true(marks_count("hybrid") >= 1, "hybrid scheme assigns marks")
    end)

    t.it("off-ball attackers leave their anchor to support the carrier", function()
        local s = new_match()
        local owner_idx
        for i, pl in ipairs(s.players) do
            if pl.team == "home" and not pl.is_keeper and i ~= s.controlled then
                owner_idx = i
                break
            end
        end
        s.owner = owner_idx
        s.players[owner_idx].pos = Vec2.new(500, 270)
        s.ball = Vec2.new(500, 270)
        local targets = match._offball_targets(s, pos_of(s))
        local moved = false
        for i, pl in ipairs(s.players) do
            if pl.team == "home" and not pl.is_keeper and targets[i] then
                if targets[i]:dist(pl.anchor) > 1 then
                    moved = true
                end
            end
        end
        t.is_true(moved, "an off-ball attacker repositioned off its anchor to support")
    end)
end)

t.describe("match player collisions", function()
    t.it("pushes overlapping players apart to at least their combined radius", function()
        local s =
            match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        local a, b = s.players[2], s.players[3]
        a.pos = Vec2.new(200, 500) -- empty corner, away from other players
        b.pos = Vec2.new(210, 500) -- 10px apart, radii 12+12=24 -> overlapping
        match._resolve_collisions(s)
        t.is_true(a.pos:dist(b.pos) >= 23.9, "bodies separated to ~combined radius")
    end)

    t.it("a sliding player barges through and stuns the one it hits", function()
        local s =
            match.new({ home = teams.nebula, away = teams.orion, field = { w = 960, h = 540 } })
        local slider, victim = s.players[2], s.players[8] -- home vs away
        slider.pos = Vec2.new(200, 500)
        slider.slide_timer = 0.3
        victim.pos = Vec2.new(210, 500)
        victim.stun_timer = 0
        match._resolve_collisions(s)
        t.is_true(victim.stun_timer > 0, "the player hit by the slide is knocked off balance")
    end)
end)

t.describe("match.step keeper claim", function()
    local function keeper_of(s, team)
        for i, p in ipairs(s.players) do
            if p.team == team and p.is_keeper then
                return i, p
            end
        end
    end

    t.it("comes off its line to claim a slow loose ball in the box", function()
        local s = new_match()
        local ki, k = keeper_of(s, "home")
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(40, 270) -- on its line
        s.ball = Vec2.new(70, 270) -- loose, just inside the box
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 0.016, NO_INPUT)
        -- either it stepped out toward the ball, or already gathered it
        t.is_true(s.owner == ki or s.players[ki].pos.x > 40, "keeper claims / advances on the ball")
    end)

    t.it("gathers a loose ball it reaches in its box", function()
        local s = new_match()
        local ki, k = keeper_of(s, "home")
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(60, 270)
        s.ball = Vec2.new(80, 270) -- within the extended claim radius (30)
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, ki, "keeper picks up the loose ball in its box")
    end)

    t.it("does not leave its line for a ball outside the box", function()
        local s = new_match()
        local ki, k = keeper_of(s, "home")
        s.owner = nil
        s.pickup_cd = 1 -- nobody collects this step
        k.pos = Vec2.new(40, 270)
        s.ball = Vec2.new(480, 270) -- midfield, well outside the box
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.players[ki].pos.x < 70, "keeper holds its line, doesn't chase midfield")
    end)
end)

t.describe("match.step keeper box dominance", function()
    local function keeper_of(s, team)
        for i, p in ipairs(s.players) do
            if p.team == team and p.is_keeper then
                return i, p
            end
        end
    end
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end
    local function away_outfielders(s)
        local out = {}
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                out[#out + 1] = i
            end
        end
        return out
    end

    t.it("keeper wins a contested loose ball in its own box", function()
        local s = new_match()
        local ki, k = keeper_of(s, "home")
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(40, 270)
        s.players[away_outfielders(s)[1]].pos = Vec2.new(75, 270) -- attacker a step closer
        s.ball = Vec2.new(60, 270) -- loose in the home box
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, ki, "keeper claims the ball in its box over the closer attacker")
    end)

    t.it("fires a claim event when the keeper gathers in its box", function()
        local s = new_match()
        local _, k = keeper_of(s, "home")
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(60, 270)
        s.ball = Vec2.new(80, 270)
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "claim"), "a box gather emits a claim event")
    end)

    t.it("does NOT get priority outside its box (closer attacker wins)", function()
        local s = new_match()
        local ki, k = keeper_of(s, "home")
        local att = away_outfielders(s)[1]
        s.owner = nil
        s.pickup_cd = 0
        k.pos = Vec2.new(175, 270) -- ball at x=180 is outside the box (depth > 160)
        s.players[att].pos = Vec2.new(182, 270) -- strictly closer to the ball
        s.ball = Vec2.new(180, 270)
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, att, "outside the box the nearer attacker wins")
    end)

    t.it("long-clears when every distribution outlet is marked", function()
        local s = new_match()
        local ki, k = keeper_of(s, "home")
        -- pin an opponent onto each home outfielder so no safe outlet exists
        local outs = away_outfielders(s)
        local home_out = {}
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper then
                home_out[#home_out + 1] = i
            end
        end
        for n = 1, math.min(#outs, #home_out) do
            s.players[outs[n]].pos =
                Vec2.new(s.players[home_out[n]].pos.x, s.players[home_out[n]].pos.y)
        end
        s.owner = ki
        k.hold_timer = 0
        match.step(s, 0.001, NO_INPUT)
        t.is_true(s.owner == nil, "keeper releases the ball")
        t.is_true(s.ball_vel.x > 0, "it is cleared upfield, not passed sideways into pressure")
        t.is_true(not has_event(s, "pass"), "a clearance is not a safe pass")
    end)
end)

t.describe("match ball height (z)", function()
    local function loose(z, vz, vx)
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 5 -- keep anyone from collecting during the flight
        s.ball = Vec2.new(480, 270)
        s.ball_vel = Vec2.new(vx or 0, 0)
        s.ball_z = z
        s.ball_vz = vz
        return s
    end

    t.it("a lofted ball rises, slows under gravity, then comes back down", function()
        local s = loose(0, 300, 0)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.ball_z > 0, "it left the ground")
        t.near(s.ball_vz, 300 - 900 * 0.016, 1e-6, "gravity decremented vertical speed")
        for _ = 1, 80 do
            match.step(s, 0.016, NO_INPUT)
            t.is_true(s.ball_z >= 0, "height never goes negative")
        end
    end)

    t.it("rebounds off the ground keeping its horizontal pace", function()
        local s = loose(2, -300, 200)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.ball_vz > 0, "bounced back up")
        t.is_true(s.ball_vel.x > 150, "kept most of its horizontal speed through the bounce")
    end)

    t.it("settles instead of micro-bouncing forever", function()
        local s = loose(0.1, -40, 0)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.ball_z, 0)
        t.eq(s.ball_vz, 0)
    end)

    t.it("possession grounds the ball (z and vz reset)", function()
        local s = new_match()
        s.ball_z = 50
        s.ball_vz = 200
        s.owner = s.controlled
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.ball_z, 0)
        t.eq(s.ball_vz, 0)
    end)
end)

t.describe("match height gates", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("a ball in the air flies over heads and is not collected", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 0
        -- park a teammate right under the ball
        local p = s.players[2]
        p.pos = Vec2.new(480, 270)
        s.ball = Vec2.new(480, 270)
        s.ball_vel = Vec2.new(0, 0)
        s.ball_z = 40 -- above GROUND_GRAB_HEIGHT
        s.ball_vz = 0
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.owner == nil, "nobody collects an overhead ball")
    end)

    t.it("the same ball on the ground IS collected", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 0
        s.players[2].pos = Vec2.new(480, 270)
        s.ball = Vec2.new(480, 270)
        s.ball_vel = Vec2.new(0, 0)
        s.ball_z = 0
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.owner ~= nil, "a grounded ball is collected")
    end)

    t.it("a shot over the crossbar is not a goal; under the bar scores", function()
        local function shoot_at_line(z)
            local s = new_match()
            s.owner = nil
            s.pickup_cd = 1
            s.ball = Vec2.new(s.field.w - 5, s.field.h / 2)
            s.ball_vel = Vec2.new(400, 0)
            s.ball_z = z
            s.ball_vz = 60 -- hold height through the short flight to the line
            for _ = 1, 10 do
                match.step(s, 0.016, NO_INPUT)
                if s.score.home > 0 then
                    break
                end
            end
            return s.score.home
        end
        t.eq(shoot_at_line(80), 0, "over the bar: no goal")
        t.eq(shoot_at_line(10), 1, "under the bar: goal")
    end)

    t.it("a keeper does not save a ball above its aerial reach", function()
        local s = new_match()
        local ki
        for i, p in ipairs(s.players) do
            if p.team == "away" and p.is_keeper then
                ki = i
                s.players[i].pos = Vec2.new(945, 270)
            end
        end
        s.owner = nil
        s.pickup_cd = 0
        s.ball = Vec2.new(925, 270)
        s.ball_vel = Vec2.new(100, 0)
        s.ball_z = 80 -- well above the keeper's aerial reach as it crosses the line
        s.ball_vz = 100 -- still rising, so it stays high over the keeper
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.owner ~= ki, "the high ball sails over the keeper")
        t.is_true(not has_event(s, "catch"), "no catch on a ball over the keeper")
    end)
end)

t.describe("match lobs and chips", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("a chip shot leaves the ground", function()
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(1, 0)
        match.step(s, 0.016, input({ shoot = true, lob = true }))
        t.is_true(s.owner == nil, "shot released")
        t.is_true(s.ball_vz > 0, "the chip launches upward")
        match.step(s, 0.016, NO_INPUT)
        t.is_true(s.ball_z > 0, "and the ball is airborne next frame")
    end)

    t.it("a driven shot stays on the ground", function()
        local s = new_match()
        s.players[s.controlled].facing = Vec2.new(1, 0)
        match.step(s, 0.016, input({ shoot = true }))
        t.eq(s.ball_vz, 0, "no loft on a normal shot")
    end)

    t.it("the keeper lobs over a defender on its throwing lane and lands near a mate", function()
        local s = new_match()
        local ki, mate
        for i, p in ipairs(s.players) do
            if p.team == "home" and p.is_keeper then
                ki = i
            end
        end
        local k = s.players[ki]
        k.pos = Vec2.new(40, 270)
        -- The ONLY open outlet is mate (idx 5), and its lane is blocked -> the keeper
        -- must lob over the blocker. Mark the other home outfielders so they aren't
        -- viable outlets (forcing the lob rather than a clear ground pass elsewhere).
        mate = s.players[5]
        mate.pos = Vec2.new(300, 270)
        s.players[2].pos = Vec2.new(200, 150)
        s.players[3].pos = Vec2.new(200, 400)
        s.players[4].pos = Vec2.new(450, 270)
        s.players[6].pos = Vec2.new(170, 270) -- blocks the keeper->mate lane (f=0.5)
        s.players[7].pos = Vec2.new(208, 150) -- marks home 2
        s.players[8].pos = Vec2.new(208, 400) -- marks home 3
        s.players[9].pos = Vec2.new(458, 270) -- marks home 4
        s.players[10].pos = Vec2.new(950, 40)
        s.owner = ki
        k.hold_timer = 0
        match.step(s, 0.001, NO_INPUT)
        t.is_true(s.owner == nil, "keeper released the ball")
        t.is_true(s.ball_vz > 0, "it was lobbed over the camped defender")
        t.is_true(has_event(s, "pass"), "still counts as a distribution pass")
    end)
end)

t.describe("match keeper respect (hard retreat)", function()
    t.it("opponents keep clear of a keeper holding the ball", function()
        local s = new_match()
        local ki
        for i, p in ipairs(s.players) do
            if p.team == "home" and p.is_keeper then
                ki = i
            end
        end
        s.owner = ki
        s.players[ki].pos = Vec2.new(40, 270)
        -- an away outfielder camped right on the keeper
        local att = 7
        s.players[att].pos = Vec2.new(55, 270)
        local targets = match._offball_targets(
            s,
            (function()
                local p = {}
                for i, pl in ipairs(s.players) do
                    p[i] = pl.pos
                end
                return p
            end)()
        )
        t.is_true(targets[att] ~= nil, "the opponent has a target")
        t.is_true(
            targets[att]:dist(s.players[ki].pos) >= 69.9,
            "its target is pushed outside the keeper's respect ring"
        )
    end)
end)

t.describe("match auto-switch control", function()
    t.it("control follows the home player who wins the ball", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 0
        local target
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                target = i
                break
            end
        end
        s.players[target].pos = Vec2.new(300, 270) -- clear space in the home half
        s.ball = Vec2.new(300, 270)
        s.ball_vel = Vec2.new(0, 0)
        s.ball_z = 0
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, target, "that player gathered the ball")
        t.eq(s.controlled, target, "control auto-switched to the ball winner")
    end)

    t.it("hands control to the HOME keeper while it holds the ball", function()
        local s = new_match()
        local ki
        for i, p in ipairs(s.players) do
            if p.team == "home" and p.is_keeper then
                ki = i
            end
        end
        s.owner = nil
        s.pickup_cd = 0
        s.players[ki].pos = Vec2.new(60, 270)
        s.ball = Vec2.new(75, 270) -- in the home keeper's box
        s.ball_vel = Vec2.new(0, 0)
        s.ball_z = 0
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, ki, "keeper claimed it")
        t.eq(s.controlled, ki, "the human takes the keeper to pick the distribution")
        t.is_true(s.players[ki].hold_timer > 2, "with a generous six-second-rule budget")
    end)
end)

t.describe("match.step keeper vs close-range shots", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("saves a shot released moments ago (inside the shooter's pickup lockout)", function()
        local s = new_match()
        local ki, k
        for i, p in ipairs(s.players) do
            if p.team == "away" and p.is_keeper then
                ki, k = i, p
            end
        end
        k.pos = Vec2.new(938, 270)
        s.owner = nil
        s.pickup_cd = 0.3 -- the shot was just released: shooter can't re-collect...
        s.ball = Vec2.new(908, 270)
        s.ball_vel = Vec2.new(600, 0) -- ...but the keeper must still react to it
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "catch") or has_event(s, "parry"), "the keeper made a save")
        t.eq(s.score.home, 0, "a close-range shot is not an automatic goal")
    end)

    t.it("smothers a carrier who brings the ball into its box", function()
        local s = new_match()
        local carrier
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                carrier = i
                break
            end
        end
        local c = s.players[carrier]
        c.pos = Vec2.new(60, 270)
        c.facing = Vec2.new(-1, 0)
        s.players[1].pos = Vec2.new(24, 270) -- home keeper on its line
        s.owner = carrier
        s.ball = Vec2.new(42, 270) -- at the carrier's feet, in the keeper's box
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, 1, "the keeper takes the ball off the carrier's feet")
        t.is_true(s.players[1].hold_timer > 0, "and holds it in hand")
    end)

    t.it("rushes a carrier in its box instead of holding the line", function()
        local s = new_match()
        local carrier
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                carrier = i
                break
            end
        end
        s.players[carrier].pos = Vec2.new(140, 240)
        s.owner = carrier
        s.ball = Vec2.new(122, 240)
        local k = s.players[1]
        k.pos = Vec2.new(24, 270)
        local before = k.pos:dist(s.ball)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(k.pos:dist(s.ball) < before, "the keeper closes down the carrier")
    end)
end)

t.describe("match.step kickoff positioning", function()
    local function assert_own_halves(s)
        local half = s.field.w / 2
        for _, p in ipairs(s.players) do
            if p.team == "home" then
                t.is_true(p.pos.x <= half, p.id .. " starts in the home half")
            else
                t.is_true(p.pos.x >= half, p.id .. " starts in the away half")
            end
        end
    end

    t.it("every player starts in their own half at the opening kickoff", function()
        assert_own_halves(new_match())
    end)

    t.it("both teams restart in their own halves after a goal", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 1
        s.ball = Vec2.new(s.field.w - 5, s.field.h / 2)
        s.ball_vel = Vec2.new(400, 0)
        for _ = 1, 10 do
            match.step(s, 0.016, NO_INPUT)
            if s.score.home > 0 then
                break
            end
        end
        t.eq(s.score.home, 1)
        assert_own_halves(s)
    end)
end)

t.describe("match.step kickoff rules", function()
    t.it("the conceding team kicks off after a goal", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 1
        s.ball = Vec2.new(s.field.w - 5, s.field.h / 2)
        s.ball_vel = Vec2.new(400, 0)
        for _ = 1, 10 do
            match.step(s, 0.016, NO_INPUT)
            if s.score.home > 0 then
                break
            end
        end
        t.eq(s.score.home, 1)
        t.is_true(s.owner ~= nil, "kickoff possession is assigned")
        t.eq(s.players[s.owner].team, "away", "the team that conceded restarts play")
        t.is_true(not s.players[s.owner].is_keeper)
        t.eq(s.players[s.controlled].team, "home", "the human still controls a home player")
        t.is_true(not s.players[s.controlled].is_keeper)
    end)
end)

t.describe("match.step pass quality", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    -- Controlled passer at (300,270) facing +x with one teammate ahead at `tpos`;
    -- every other outfielder parked behind, all opponents far away.
    local function pass_setup(tpos)
        local s = new_match()
        local passer = s.controlled
        local mate
        s.players[passer].pos = Vec2.new(300, 270)
        s.players[passer].facing = Vec2.new(1, 0)
        local backy = 100
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= passer then
                if not mate then
                    mate = i
                    p.pos = Vec2.new(tpos.x, tpos.y)
                else
                    p.pos = Vec2.new(100, backy)
                    backy = backy + 120
                end
            elseif p.team == "away" then
                p.pos = Vec2.new(940, 40)
            end
        end
        s.owner = passer
        s.ball = s.players[passer].pos:add(Vec2.new(18, 0))
        return s, passer, mate
    end

    t.it("a long pass is driven hard enough to actually arrive", function()
        local s, _, mate = pass_setup(Vec2.new(700, 270))
        match.step(s, 0.016, input({ pass = true }))
        t.is_true(has_event(s, "pass"))
        t.is_true(s.players[mate].receive_timer > 0, "the receiver runs onto it")
        t.is_true(s.ball_vel:length() > 450, "a 400px pass is driven, not rolled")
        for _ = 1, 150 do
            match.step(s, 1 / 60, NO_INPUT)
            if s.owner then
                break
            end
        end
        t.eq(s.owner, mate, "the receiver collects the pass")
    end)

    t.it("falls back to the nearest teammate when nobody is in the aim cone", function()
        local s = new_match()
        local passer = s.controlled
        s.players[passer].pos = Vec2.new(800, 270)
        s.players[passer].facing = Vec2.new(1, 0) -- aiming at open space
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= passer then
                p.pos = Vec2.new(500, p.pos.y) -- everyone behind the passer
            end
        end
        s.owner = passer
        s.ball = s.players[passer].pos:add(Vec2.new(18, 0))
        match.step(s, 0.016, input({ pass = true }))
        t.is_true(has_event(s, "pass"), "the pass button always finds someone")
        t.is_true(s.ball_vel.x < 0, "played back to the nearest teammate")
    end)

    t.it("an AI carrier under pressure passes to an open teammate", function()
        local s = new_match()
        local carrier, mate
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                if not carrier then
                    carrier = i
                elseif not mate then
                    mate = i
                end
            end
        end
        s.players[carrier].pos = Vec2.new(600, 270)
        s.players[mate].pos = Vec2.new(450, 200) -- open, ahead (away attacks -x)
        -- A home defender close enough to pressure but not to steal.
        local defender
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                defender = i
                break
            end
        end
        s.players[defender].pos = Vec2.new(655, 270)
        s.players[s.controlled].pos = Vec2.new(200, 100)
        s.owner = carrier
        s.ball = Vec2.new(582, 270)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "pass"), "the pressured carrier moves the ball on")
        local receiver
        for i, p in ipairs(s.players) do
            if p.team == "away" and p.receive_timer > 0 then
                receiver = i
            end
        end
        t.is_true(receiver ~= nil and receiver ~= carrier, "an away teammate runs onto it")
        t.is_true(mate ~= nil) -- (setup sanity)
    end)
end)

t.describe("match.step keeper floated throw (tier 2)", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("floats a throw over the traffic when outlets are marked but not swarmed", function()
        local s = new_match()
        local k = s.players[1] -- home keeper
        k.pos = Vec2.new(40, 270)
        -- Every outlet has a marker 40px away: not SAFE (60) but receivable (>=30).
        s.players[2].pos = Vec2.new(250, 150)
        s.players[3].pos = Vec2.new(250, 390)
        s.players[4].pos = Vec2.new(420, 270)
        s.players[5].pos = Vec2.new(560, 200)
        s.players[7].pos = Vec2.new(290, 150)
        s.players[8].pos = Vec2.new(290, 390)
        s.players[9].pos = Vec2.new(460, 270)
        s.players[10].pos = Vec2.new(600, 200)
        s.players[6].pos = Vec2.new(938, 270) -- away keeper home
        s.owner = 1
        s.ball = Vec2.new(40, 270)
        k.hold_timer = 0
        match.step(s, 0.001, NO_INPUT)
        t.is_true(s.owner == nil, "keeper releases the ball")
        t.is_true(has_event(s, "pass"), "it is a distribution, not a clearance")
        t.is_true(s.ball_vz > 0, "and it is floated over the opponents")
    end)
end)

t.describe("match.step pass interception awareness", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("the pass button prefers a teammate whose lane cannot be cut", function()
        local s = new_match()
        local passer = s.controlled
        s.players[passer].pos = Vec2.new(300, 270)
        s.players[passer].facing = Vec2.new(1, 0)
        -- mate1: nearest in the cone, but an away body camps its lane late in the
        -- flight. mate2: a touch further, in the cone, and safely off that lane.
        local mate1, mate2
        local backy = 100
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= passer then
                if not mate1 then
                    mate1 = i
                    p.pos = Vec2.new(440, 270)
                elseif not mate2 then
                    mate2 = i
                    p.pos = Vec2.new(420, 400)
                else
                    p.pos = Vec2.new(100, backy) -- behind: outside the aim cone
                    backy = backy + 120
                end
            end
        end
        local interceptor
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                if not interceptor then
                    interceptor = i
                    p.pos = Vec2.new(420, 270) -- sits on the passer->mate1 lane
                else
                    p.pos = Vec2.new(940, 40) -- everyone else far away
                end
            end
        end
        s.owner = passer
        s.ball = s.players[passer].pos:add(Vec2.new(18, 0))
        match.step(s, 0.016, input({ pass = true }))
        t.is_true(has_event(s, "pass"), "a pass is released")
        t.is_true(interceptor ~= nil) -- (setup sanity)
        t.is_true(
            s.players[mate2].receive_timer > 0,
            "the ball goes to the mate whose lane cannot be cut"
        )
    end)

    t.it("a pressured AI carrier lobs the pass a chaser would cut out", function()
        local s = new_match()
        -- Away carrier under pressure with one eligible outlet; a home defender
        -- stands 26px off the ground lane (statically clear, POSSESS_DIST is 22)
        -- but close enough to step onto the rolling ball.
        local away_out = {}
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                away_out[#away_out + 1] = i
            end
        end
        local carrier, outlet = away_out[1], away_out[2]
        s.players[carrier].pos = Vec2.new(600, 270)
        s.players[outlet].pos = Vec2.new(440, 270)
        s.players[away_out[3]].pos = Vec2.new(820, 200)
        s.players[away_out[4]].pos = Vec2.new(820, 340)
        local home_out = {}
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                home_out[#home_out + 1] = i
            end
        end
        s.players[home_out[1]].pos = Vec2.new(655, 270) -- pressures the carrier
        s.players[home_out[2]].pos = Vec2.new(520, 296) -- lurks 26px off the lane
        s.players[home_out[3]].pos = Vec2.new(824, 200) -- pins an away spare
        s.players[s.controlled].pos = Vec2.new(824, 340) -- pins the other spare
        s.owner = carrier
        s.ball = Vec2.new(582, 270)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "pass"), "the pressured carrier moves the ball on")
        t.is_true(s.players[outlet].receive_timer > 0, "to the eligible outlet")
        t.is_true(s.ball_vz > 0, "floated over the would-be interceptor, not rolled")
    end)

    t.it("the keeper floats its distribution over a chaser who could cut it", function()
        local s = new_match()
        local k = s.players[1] -- home keeper
        k.pos = Vec2.new(40, 270)
        -- Outlet 2 is the only viable target: its marker is 104px away (safe) and
        -- its lane is statically clear, but that marker sits 30px off the lane —
        -- near enough to cut a rolling ball. Every other outlet is pinned.
        s.players[2].pos = Vec2.new(240, 270)
        s.players[3].pos = Vec2.new(300, 100)
        s.players[4].pos = Vec2.new(300, 440)
        s.players[5].pos = Vec2.new(600, 270)
        s.players[7].pos = Vec2.new(140, 300) -- the chaser off the keeper->2 lane
        s.players[8].pos = Vec2.new(302, 100) -- pins home 3
        s.players[9].pos = Vec2.new(302, 440) -- pins home 4
        s.players[10].pos = Vec2.new(602, 270) -- pins home 5
        s.players[6].pos = Vec2.new(938, 270) -- away keeper home
        s.owner = 1
        s.ball = Vec2.new(40, 270)
        k.hold_timer = 0
        match.step(s, 0.001, NO_INPUT)
        t.is_true(s.owner == nil, "keeper releases the ball")
        t.is_true(has_event(s, "pass"), "it is a distribution, not a clearance")
        t.is_true(s.players[2].receive_timer > 0, "aimed at the open outlet")
        t.is_true(s.ball_vz > 0, "floated over the chaser instead of rolled past it")
    end)
end)

t.describe("match.step loose-ball pursuit", function()
    t.it("chasers lead a rolling ball instead of trailing it", function()
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 1
        s.ball = Vec2.new(700, 400) -- open space: no player is standing on it
        s.ball_vel = Vec2.new(200, 0) -- rolling toward the away goal
        local pos = {}
        for i, pl in ipairs(s.players) do
            pos[i] = pl.pos
        end
        local targets = match._offball_targets(s, pos)
        -- The away press-set chaser (nearest away outfielder to the ball).
        local chaser, best_d
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                local d = p.pos:dist(s.ball)
                if not best_d or d < best_d then
                    best_d, chaser = d, i
                end
            end
        end
        t.is_true(targets[chaser] ~= nil, "the chaser has a target")
        t.is_true(targets[chaser].x > s.ball.x, "it aims ahead of the ball along its path")
        t.near(targets[chaser].y, s.ball.y, 1e-6, "the lead stays on the ball's line")
    end)
end)

t.describe("match shot blocking", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    ---@return MatchState
    local function loose_ball(x, vx, z)
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 1 -- keep collection out of the picture unless a test wants it
        s.ball = Vec2.new(x, 270)
        s.ball_vel = Vec2.new(vx, 0)
        s.ball_z = z or 0
        s.ball_vz = 0
        return s
    end

    -- Clear everyone off the midfield corridor, then park one away outfielder
    -- as a wall at (500, 270) so it is the only body the ball can meet.
    local function with_wall(s)
        local slot, wall = 0, nil
        for _, p in ipairs(s.players) do
            p.pos = Vec2.new(60 + slot * 50, 40)
            slot = slot + 1
            if not wall and p.team == "away" and not p.is_keeper then
                wall = p
                p.pos = Vec2.new(500, 270)
            end
        end
        return wall
    end

    t.it("a driven ball ricochets off a body in its path", function()
        local s = loose_ball(490, 450, 0)
        with_wall(s)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "block"), "the body blocked it")
        t.is_true(s.ball_vel.x < 0, "the ball came back off the body")
        t.is_true(s.ball_vel:length() < 450, "a block soaks pace")
    end)

    t.it("a lofted ball sails over the body", function()
        local s = loose_ball(490, 450, 40)
        s.ball_vz = 50 -- still rising through the frame
        with_wall(s)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(not has_event(s, "block"), "no block on a ball over head height")
        t.is_true(s.ball_vel.x > 0, "it kept flying")
    end)

    t.it("a ball moving away from a body is never blocked (own release)", function()
        local s = loose_ball(505, 450, 0) -- overlapping the wall but outbound
        with_wall(s)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(not has_event(s, "block"), "an outbound ball never re-blocks")
        t.is_true(s.ball_vel.x > 0)
    end)

    t.it("a slow ball is collected at the body, not bounced", function()
        local s = loose_ball(492, 200, 0)
        with_wall(s)
        s.pickup_cd = 0
        match.step(s, 0.016, NO_INPUT)
        t.is_true(not has_event(s, "block"), "slow balls are trapped, not deflected")
        t.is_true(s.owner ~= nil, "the body wins the ball instead")
    end)
end)

t.describe("match keeper save tuning", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    -- Fire a corner-aimed shot at the away keeper from 800,270 and play it out.
    local function corner_shot(speed)
        local s = new_match()
        local k
        for _, p in ipairs(s.players) do
            if p.team == "away" and p.is_keeper then
                k = p
            end
        end
        k.pos = Vec2.new(938, 270)
        -- Clear every outfielder off the shot lane so only the keeper matters.
        local slot = 0
        for _, p in ipairs(s.players) do
            if not p.is_keeper then
                p.pos = Vec2.new(100 + slot * 40, 60)
                slot = slot + 1
            end
        end
        s.owner = nil
        s.pickup_cd = 0.3 -- as if just released
        s.ball = Vec2.new(800, 270)
        s.ball_vel = Vec2.new(950, 317):sub(s.ball):normalized():scale(speed)
        local caught, parried = false, false
        for _ = 1, 40 do
            match.step(s, 1 / 60, NO_INPUT)
            caught = caught or has_event(s, "catch")
            parried = parried or has_event(s, "parry")
            if s.score.home > 0 then
                break
            end
        end
        return s.score.home, caught, parried
    end

    t.it("an uncharged corner shot is kept out", function()
        local goals, caught, parried = corner_shot(500)
        t.eq(goals, 0, "no clean goal from a plain corner shot")
        t.is_true(caught or parried, "the keeper got something on it")
    end)

    t.it("a fully charged corner shot beats the keeper", function()
        local goals = corner_shot(1000)
        t.eq(goals, 1, "a charged corner shot scores")
    end)
end)

t.describe("match AI shooting", function()
    -- An away carrier in range of the home goal; `defender_at` optionally parks
    -- a home outfielder near it. Returns the released shot speed.
    local function ai_shot_speed(defender_dist)
        local s = new_match()
        local carrier
        local slot = 0
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper then
                p.pos = Vec2.new(700 + slot * 40, 60) -- clear the home half
                slot = slot + 1
            elseif p.team == "away" and not p.is_keeper and not carrier then
                carrier = i
                p.pos = Vec2.new(200, 270)
                p.facing = Vec2.new(-1, 0)
            end
        end
        if defender_dist then
            for i, p in ipairs(s.players) do
                if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                    p.pos = Vec2.new(200 + defender_dist, 270)
                    break
                end
            end
        end
        s.owner = carrier
        s.ball = Vec2.new(182, 270)
        match.step(s, 0.016, NO_INPUT)
        return s.ball_vel:length()
    end

    t.it("a striker in space shoots much harder than one closed down", function()
        local open = ai_shot_speed(nil)
        local closed = ai_shot_speed(30)
        t.is_true(open > closed * 1.5, "space converts into shot power")
    end)
end)

t.describe("match possession feel", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("an AI receiver settles the ball before passing under pressure", function()
        local s = new_match()
        -- A loose ball at an away outfielder's feet with a home defender pressing.
        local recv, presser
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                recv = recv or i
            elseif p.team == "home" and not p.is_keeper and i ~= s.controlled then
                presser = presser or i
            end
        end
        s.players[recv].pos = Vec2.new(600, 270)
        s.players[presser].pos = Vec2.new(650, 270) -- pressured (< 70) but out of poke range
        s.players[s.controlled].pos = Vec2.new(100, 60)
        s.owner = nil
        s.pickup_cd = 0
        s.ball = Vec2.new(600, 270)
        s.ball_vel = Vec2.new(60, 0) -- rolling: collection reads as a touch
        local touched_at, passed_at
        for f = 1, 90 do
            match.step(s, 1 / 60, NO_INPUT)
            if not touched_at and s.owner == recv then
                touched_at = f
            end
            if touched_at and not passed_at and has_event(s, "pass") then
                passed_at = f
            end
        end
        t.is_true(touched_at ~= nil, "the receiver takes the ball")
        t.is_true(passed_at ~= nil, "and eventually moves it on")
        t.is_true(passed_at - touched_at >= 15, "but only after a settling touch (~0.3s+)")
    end)

    t.it("a whiffed AI poke stumbles the defender", function()
        local s = new_match()
        local carrier, defender
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                carrier = carrier or i
            elseif p.team == "home" and not p.is_keeper and i ~= s.controlled then
                defender = defender or i
            end
        end
        local c = s.players[carrier]
        c.facing = Vec2.new(-1, 0)
        s.owner = carrier
        s.ball = c.pos:add(Vec2.new(-18, 0))
        -- Park the carrier's teammates out of range so it can't pass out.
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper and i ~= carrier then
                p.pos = Vec2.new(40, 380 + i * 15)
            end
        end
        -- On the carrier's back: ball shielded, poke commits but comes up short.
        s.players[defender].pos = Vec2.new(c.pos.x + 20, c.pos.y)
        s.players[defender].dash_cd = 0
        s.players[s.controlled].pos = Vec2.new(60, 60)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, carrier, "the shielded carrier keeps it")
        t.is_true(s.players[defender].stun_timer > 0, "the whiffing defender stumbles")
    end)
end)

t.describe("match pressure on a static carrier", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("a carrier who never moves gets challenged, not ignored", function()
        local s = new_match() -- human holds the ball at kickoff
        local challenged, lost = false, false
        for _ = 1, 300 do -- 5 seconds of standing still
            match.step(s, 1 / 60, NO_INPUT)
            challenged = challenged or has_event(s, "tackle")
            lost = lost or (s.owner ~= nil and s.players[s.owner].team == "away") or s.owner == nil
        end
        t.is_true(challenged or lost, "the defense pressures a statue instead of freezing")
    end)

    t.it("a defender leaning on the carrier shoves them off their spot", function()
        local s = new_match()
        local me = s.players[s.controlled]
        local start = me.pos
        -- Overlap an away defender onto the carrier and let collisions resolve.
        for _, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                p.pos = Vec2.new(me.pos.x + 10, me.pos.y)
                break
            end
        end
        match.step(s, 1 / 60, NO_INPUT)
        t.is_true(me.pos:dist(start) > 3, "the carrier is displaced by the lean")
    end)
end)

t.describe("match keeper build-up space", function()
    t.it("opponents back right off and mark lanes, not the outlet's boots", function()
        local s = new_match()
        s.owner = 1 -- home keeper holds throughout
        s.players[1].pos = Vec2.new(40, 270)
        s.players[1].hold_timer = 2
        s.ball = Vec2.new(40, 270)
        local outlet = s.players[2]
        outlet.pos = Vec2.new(220, 200)
        local marker = s.players[8]
        marker.pos = Vec2.new(236, 200) -- starts tight on the outlet
        s.players[7].pos = Vec2.new(70, 270) -- camped on the keeper
        for _ = 1, 60 do
            s.controlled = 1
            match.step(s, 1 / 60, NO_INPUT)
            s.controlled = 1
        end
        for _, p in ipairs(s.players) do
            if p.team == "away" then
                t.is_true(
                    p.pos:dist(s.players[1].pos) >= 119,
                    p.id .. " backs off the keeper's ring"
                )
            end
        end
        t.is_true(marker.pos:dist(outlet.pos) >= 38, "the marker stands off, marking the lane")
    end)
end)

t.describe("match auto-switch on turnover", function()
    t.it("control jumps to the best-placed defender when the opponent wins it", function()
        local s = new_match()
        local away_idx, defender
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                away_idx = away_idx or i
            elseif p.team == "home" and not p.is_keeper and i ~= s.controlled then
                defender = defender or i
            end
        end
        s.players[away_idx].pos = Vec2.new(600, 270)
        s.players[defender].pos = Vec2.new(560, 270) -- closest home defender
        s.players[s.controlled].pos = Vec2.new(100, 100) -- current control far away
        s.owner = nil
        s.pickup_cd = 0
        s.ball = Vec2.new(600, 270)
        s.ball_vel = Vec2.new(0, 0)
        match.step(s, 0.016, NO_INPUT)
        t.eq(s.owner, away_idx, "the away player collects")
        t.eq(s.controlled, defender, "control moves to the nearest home defender")
    end)
end)

t.describe("match keeper respect ring (physical)", function()
    t.it("the controlled player cannot camp a keeper holding the ball", function()
        local s = new_match()
        local ki
        for i, p in ipairs(s.players) do
            if p.team == "away" and p.is_keeper then
                ki = i
            end
        end
        s.owner = ki
        s.players[ki].hold_timer = 2 -- holding throughout
        local me = s.players[s.controlled]
        me.pos = Vec2.new(s.players[ki].pos.x - 10, s.players[ki].pos.y)
        match.step(s, 1 / 60, NO_INPUT)
        t.is_true(
            me.pos:dist(s.players[ki].pos) >= 69,
            "the human is pushed out to the respect ring"
        )
    end)
end)

t.describe("match human keeper control", function()
    local function home_keeper_holding(s)
        s.owner = 1
        s.controlled = 1
        s.players[1].pos = Vec2.new(40, 270)
        s.players[1].facing = Vec2.new(1, 0)
        s.players[1].hold_timer = 5
        s.ball = Vec2.new(46, 270)
    end

    t.it("a longer-held punt is hit harder and lofted", function()
        local function punt(charge)
            local s = new_match()
            home_keeper_holding(s)
            s.charge = charge
            match.step(s, 0.016, input({ shoot = true }))
            return s
        end
        local weak, strong = punt(0), punt(1)
        t.is_true(weak.owner == nil and strong.owner == nil, "the punt releases the ball")
        t.is_true(strong.ball_vz > 0, "punts are lofted clearances")
        t.is_true(
            strong.ball_vel:length() > weak.ball_vel:length(),
            "holding longer sends it further"
        )
    end)

    t.it("the charged throw range picks the far teammate along the aim", function()
        local function throw_receiver(charge)
            local s = new_match()
            home_keeper_holding(s)
            s.players[2].pos = Vec2.new(200, 270) -- short option on the aim line
            s.players[3].pos = Vec2.new(480, 270) -- long option on the aim line
            s.players[4].pos = Vec2.new(120, 60)
            s.players[5].pos = Vec2.new(120, 480)
            s.pass_charge = charge
            match.step(s, 0.016, input({ pass = true }))
            for i, pl in ipairs(s.players) do
                if pl.receive_timer > 0 then
                    return i, s
                end
            end
        end
        local near_i = throw_receiver(0)
        local far_i, s2 = throw_receiver(1)
        t.eq(near_i, 2, "a tap throw goes short")
        t.eq(far_i, 3, "a charged throw picks out the long option")
        t.is_true(s2.controlled ~= 1, "control returns to an outfielder after the release")
    end)
end)

t.describe("match aerial play", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    -- A loose airborne ball at `z` dropping onto player index `idx`.
    local function dropping_ball_on(s, idx, z)
        s.owner = nil
        s.pickup_cd = 0
        local p = s.players[idx]
        s.ball = Vec2.new(p.pos.x + 6, p.pos.y)
        s.ball_vel = Vec2.new(0, 0)
        s.ball_z = z
        s.ball_vz = -50
    end

    t.it("an AI attacker heads a dropping ball at goal", function()
        local s = new_match()
        local att
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                att = i
                break
            end
        end
        s.players[att].pos = Vec2.new(160, 270) -- in front of the home goal
        for i, p in ipairs(s.players) do
            if p.team == "home" then
                s.players[i].pos = Vec2.new(700, 60 + i * 40) -- clear of the drop
            end
        end
        dropping_ball_on(s, att, 45)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "header"), "the striker meets it")
        t.is_true(s.ball_vel.x < 0, "headed toward the home goal")
    end)

    t.it("a defender in its own third heads danger clear", function()
        local s = new_match()
        local def
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= s.controlled then
                def = i
                break
            end
        end
        s.players[def].pos = Vec2.new(100, 270) -- deep in the home third
        s.players[s.controlled].pos = Vec2.new(700, 100)
        for i, p in ipairs(s.players) do
            if p.team == "away" then
                s.players[i].pos = Vec2.new(820, 60 + i * 40)
            end
        end
        dropping_ball_on(s, def, 50)
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "header"), "the defender attacks the ball")
        t.is_true(s.ball_vel.x > 0, "cleared upfield")
        t.is_true(s.ball_vz > 0, "and high")
    end)

    t.it("volleys are riskier: some seeds sky it and the cage returns it", function()
        local skied, clean
        for seed = 1, 60 do
            local s = match.new({
                home = teams.nebula,
                away = teams.orion,
                field = { w = 960, h = 540 },
                seed = seed,
            })
            local att
            for i, p in ipairs(s.players) do
                if p.team == "away" and not p.is_keeper then
                    att = i
                    break
                end
            end
            s.players[att].pos = Vec2.new(160, 270)
            for i, p in ipairs(s.players) do
                if p.team == "home" then
                    s.players[i].pos = Vec2.new(700, 60 + i * 40)
                end
            end
            dropping_ball_on(s, att, 25) -- volley height
            match.step(s, 0.016, NO_INPUT)
            if has_event(s, "volley") then
                if s.ball_vz > 400 then
                    skied = skied or s
                else
                    clean = clean or s
                end
            end
        end
        t.is_true(skied ~= nil, "some volleys get skied")
        t.is_true(clean ~= nil, "and some are hit clean")
        -- The skied one: the cage ceiling caps it and brings it back down.
        local max_z = 0
        for _ = 1, 180 do
            match.step(skied, 1 / 60, NO_INPUT)
            max_z = math.max(max_z, skied.ball_z)
        end
        t.is_true(max_z <= 170, "the cage ceiling caps the flight")
        t.is_true(skied.ball_z < 60, "and the ball comes back down into play")
    end)
end)

t.describe("match crossing", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    t.it("an AI carrier on the flank crosses to the box", function()
        local s = new_match()
        local carrier, target
        for i, p in ipairs(s.players) do
            if p.team == "away" and not p.is_keeper then
                if not carrier then
                    carrier = i
                elseif not target then
                    target = i
                end
            end
        end
        s.players[carrier].pos = Vec2.new(300, 100) -- wide, attacking third (away attacks -x)
        s.players[target].pos = Vec2.new(150, 250) -- in the box
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper then
                s.players[i].pos = Vec2.new(820, 60 + i * 30) -- nobody pressuring
            end
        end
        s.owner = carrier
        s.ball = s.players[carrier].pos:add(Vec2.new(-18, 0))
        match.step(s, 0.016, NO_INPUT)
        t.is_true(has_event(s, "pass"), "the winger delivers it")
        t.is_true(s.ball_vz > 0, "a cross is lofted")
        t.is_true(s.players[target].receive_timer > 0, "aimed at the man in the box")
    end)

    t.it("a human lofted pass from wide targets the box runner", function()
        local s = new_match()
        local passer = s.controlled
        s.players[passer].pos = Vec2.new(750, 100) -- wide right, attacking third
        s.players[passer].facing = Vec2.new(1, 0)
        local cone_mate, box_mate
        for i, p in ipairs(s.players) do
            if p.team == "home" and not p.is_keeper and i ~= passer then
                if not cone_mate then
                    cone_mate = i
                    p.pos = Vec2.new(860, 100) -- straight along the aim
                elseif not box_mate then
                    box_mate = i
                    p.pos = Vec2.new(830, 270) -- in the box
                else
                    p.pos = Vec2.new(200, 60 + i * 40)
                end
            end
        end
        for i, p in ipairs(s.players) do
            if p.team == "away" then
                s.players[i].pos = Vec2.new(120, 40 + i * 30)
            end
        end
        s.owner = passer
        s.ball = s.players[passer].pos:add(Vec2.new(18, 0))
        match.step(s, 0.016, input({ pass = true, lob = true }))
        t.is_true(s.players[box_mate].receive_timer > 0, "the cross picks the box, not the cone")
        t.is_true(s.ball_vz > 0, "and sails high")
    end)
end)

t.describe("match save grab-vs-parry odds", function()
    local function has_event(s, kind)
        for _, e in ipairs(s.events) do
            if e.kind == kind then
                return true
            end
        end
        return false
    end

    -- Fire the same shot at the away keeper under one seed; report the outcome.
    ---@return "catch"|"parry"|"goal"|nil
    local function shot_outcome(seed, speed, dy)
        local s = match.new({
            home = teams.nebula,
            away = teams.orion,
            field = { w = 960, h = 540 },
            seed = seed,
        })
        local k
        for _, p in ipairs(s.players) do
            if p.team == "away" and p.is_keeper then
                k = p
            end
        end
        k.pos = Vec2.new(938, 270)
        local slot = 0
        for _, p in ipairs(s.players) do
            if not p.is_keeper then
                p.pos = Vec2.new(60 + slot * 40, 40) -- everyone clear of the lane
                slot = slot + 1
            end
        end
        s.owner = nil
        s.pickup_cd = 0.3
        s.ball = Vec2.new(750, 270)
        s.ball_vel = Vec2.new(950, 270 + dy):sub(s.ball):normalized():scale(speed)
        for _ = 1, 90 do
            match.step(s, 1 / 60, NO_INPUT)
            if has_event(s, "catch") then
                return "catch"
            end
            if has_event(s, "parry") then
                return "parry"
            end
            if s.score.home > 0 then
                return "goal"
            end
        end
        return nil
    end

    local function tally(speed, dy, n)
        local c = { catch = 0, parry = 0, goal = 0 }
        for seed = 1, n do
            local o = shot_outcome(seed, speed, dy)
            if o then
                c[o] = c[o] + 1
            end
        end
        return c
    end

    t.it("a soft, central shot sticks in the gloves nearly every time", function()
        local c = tally(420, 0, 40)
        local total = c.catch + c.parry
        t.eq(c.goal, 0, "a soft central shot never scores")
        t.is_true(total >= 39, "the keeper always deals with it")
        t.is_true(c.catch >= total * 0.85, "held, not parried: " .. c.catch .. "/" .. total)
    end)

    t.it("a hard shot toward the corner is mostly pushed away", function()
        local c = tally(700, 40, 40)
        local total = c.catch + c.parry
        t.eq(c.goal, 0, "still kept out")
        t.is_true(total >= 39)
        t.is_true(c.parry >= total * 0.7, "mostly parried: " .. c.parry .. "/" .. total)
    end)

    t.it("the same seed always reproduces the same outcome", function()
        local a = shot_outcome(7, 700, 30)
        local b = shot_outcome(7, 700, 30)
        t.eq(a, b, "seeded matches are deterministic")
    end)
end)

t.describe("match sprint", function()
    -- Run the controlled player along the bottom wing with the loose ball parked
    -- far away (top-left), so nothing interferes with the straight-line run.
    ---@param frames integer
    ---@param inputs table
    ---@param setup fun(s: MatchState, me: MatchPlayer)?
    local function run(frames, inputs, setup)
        local s = new_match()
        s.owner = nil
        s.pickup_cd = 60
        s.ball = Vec2.new(100, 60)
        local me = s.players[s.controlled]
        me.pos = Vec2.new(150, 480)
        if setup then
            setup(s, me)
        end
        local x0 = me.pos.x
        for _ = 1, frames do
            match.step(s, 1 / 60, input(inputs))
        end
        return me.pos.x - x0, me
    end

    t.it("sprinting covers more ground and drains the meter", function()
        local walked = run(30, { move = Vec2.new(1, 0) })
        local sprinted, me = run(30, { move = Vec2.new(1, 0), sprint = true })
        t.is_true(sprinted > walked * 1.2, "sprint is meaningfully faster")
        t.is_true(me.sprint_meter < 1, "sprinting drains the meter")
    end)

    t.it("the meter refills while not sprinting", function()
        local _, me = run(60, { move = Vec2.new(1, 0) }, function(_, m)
            m.sprint_meter = 0.5
        end)
        t.is_true(me.sprint_meter > 0.5, "resting refills the tank")
    end)

    t.it("an empty tank gives no boost until it meaningfully recovers", function()
        local walked = run(30, { move = Vec2.new(1, 0) })
        local drained = run(30, { move = Vec2.new(1, 0), sprint = true }, function(_, m)
            m.sprint_meter = 0
        end)
        t.near(drained, walked, 1e-6, "no sprint speed from an empty tank")
    end)
end)

t.describe("match scenario: keeper retains possession under pressure", function()
    -- A scripted "real game" situation: the home keeper has gathered the ball with
    -- a striker pressing and two defenders available as outlets. Played out over 3
    -- seconds, the keeper must keep it for the team and never hand it to the
    -- opponent. Control is parked on the keeper so every outfielder is pure AI.
    t.it("the keeper builds out without losing the ball to the opponent", function()
        local s = new_match()
        s.owner = 1 -- home keeper
        s.players[1].pos = Vec2.new(40, 270)
        s.players[1].hold_timer = 0.9
        s.ball = Vec2.new(40, 270)
        s.players[2].pos = Vec2.new(210, 170) -- home defender (outlet)
        s.players[3].pos = Vec2.new(210, 370) -- home defender (outlet)
        s.players[4].pos = Vec2.new(450, 200)
        s.players[5].pos = Vec2.new(600, 270)
        s.players[7].pos = Vec2.new(62, 270) -- away striker pressing the keeper
        s.players[8].pos = Vec2.new(230, 170) -- away marking a defender
        s.players[9].pos = Vec2.new(500, 270)
        s.players[10].pos = Vec2.new(700, 270)

        -- The guarantee: the keeper's distribution reaches a home outfielder
        -- before the opponent ever touches the ball. (What happens later in
        -- open play — e.g. that outfielder dribbling into a challenge — is the
        -- game, not a build-up failure.)
        local away_before_receive, home_outfielder_owned = false, false
        for _ = 1, 180 do
            s.controlled = 1 -- keep the human out of it; all outfielders are AI
            match.step(s, 1 / 60, NO_INPUT)
            s.controlled = 1
            local o = s.owner
            if o then
                if s.players[o].team == "away" and not home_outfielder_owned then
                    away_before_receive = true
                elseif s.players[o].team == "home" and not s.players[o].is_keeper then
                    home_outfielder_owned = true
                end
            end
        end

        t.is_true(not away_before_receive, "the opponent never intercepts the build-up")
        t.is_true(home_outfielder_owned, "a home outfielder received the keeper's distribution")
    end)
end)
