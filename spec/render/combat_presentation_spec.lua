local Vec2 = require("core.vec2")
local combat_presentation = require("game.presentation.combat")
local player_pose = require("game.presentation.player_pose")
local pitch = require("game.render.pitch")
local player_renderer = require("game.render.player_renderer")
local combat = require("sim.combat")
local match = require("sim.match")
local teams = require("data.teams")
local t = require("spec.support.runner")

local function stub_graphics()
    local graphics = {}
    local function noop() end
    for _, name in ipairs({
        "setColor",
        "setLineWidth",
        "setBlendMode",
        "setShader",
        "line",
        "circle",
        "ellipse",
        "arc",
        "polygon",
        "rectangle",
        "push",
        "pop",
        "translate",
        "rotate",
    }) do
        graphics[name] = noop
    end
    return graphics
end

---@param fn fun()
local function with_graphics(fn)
    local saved = love.graphics
    love.graphics = stub_graphics()
    local ok, err = pcall(fn)
    love.graphics = saved
    t.is_true(ok, "combat presentation draw error: " .. tostring(err))
end

t.describe("combat procedural renderer", function()
    t.it("draws all family telegraphs, a projectile, and the crowded ten-player fixture", function()
        with_graphics(function()
            local state = match.new({
                home = teams.nebula,
                away = teams.orion,
                field = { w = 960, h = 540 },
            })
            local combat_state = combat.new_state(state)
            local configured = {}
            for index, runtime in ipairs(combat_state.players) do
                if runtime.family_id and not configured[runtime.family_id] then
                    configured[runtime.family_id] = true
                    if runtime.family_id == "guard" then
                        runtime.phase = "guard"
                    elseif runtime.family_id == "ranged" then
                        runtime.phase = "aim"
                    else
                        runtime.phase = runtime.family_id == "unarmed" and "windup" or "active"
                        runtime.phase_ticks = 2
                    end
                end
            end
            combat_state.projectiles[1] = {
                family_id = "ranged",
                source_index = 4,
                source_sequence = 3,
                pos = Vec2.new(480, 270),
                dir = Vec2.new(1, 0),
                remaining_ticks = 40,
            }
            pitch.draw(state, { w = 1280, h = 720 }, {
                home_color = teams.nebula.color,
                away_color = teams.orion.color,
                combat = combat_presentation.model(state, combat_state),
            })
        end)
    end)

    t.it("draws all six procedural equipment proxies through compatible poses", function()
        with_graphics(function()
            local fixtures = {
                { "toy_spring_gloves", "unarmed", "combat_active" },
                { "medieval_heater_shield", "guard", "combat_guard" },
                { "medieval_tournament_sword", "light_melee", "combat_windup" },
                { "scifi_energy_blade", "light_melee", "combat_active" },
                { "toy_foam_sword", "light_melee", "combat_recovery" },
                { "scifi_pulse_blaster", "ranged", "combat_aim" },
            }
            for _, fixture in ipairs(fixtures) do
                local combat_sample = {
                    player_index = 2,
                    player_id = "fixture",
                    family_id = fixture[2],
                    family_name = fixture[2],
                    equipment_presentation_id = fixture[1],
                    equipment_name = fixture[1],
                    equipment_attachment = "right_hand",
                    phase = fixture[3] == "combat_recovery" and "recovery"
                        or (fixture[3] == "combat_aim" and "aim")
                        or (fixture[3] == "combat_guard" and "guard")
                        or (fixture[3] == "combat_windup" and "windup")
                        or "active",
                    phase_progress = 0.5,
                    phase_ticks = 3,
                    cooldown_ticks = 8,
                    cooldown_fraction = 0.5,
                    readiness = "committed",
                    forced_ticks = 0,
                    immunity_ticks = 0,
                    position = Vec2.new(100, 100),
                    direction = Vec2.new(1, 0),
                }
                player_renderer.draw(200, 300, 12, { 0.2, 0.8, 1 }, nil, {
                    facing = Vec2.new(1, 0),
                    is_keeper = false,
                    controlled = true,
                    species_shape = "round",
                    species_color = { 1, 0.7, 0.2 },
                    team = "home",
                    combat = combat_sample,
                    pose = {
                        id = fixture[3],
                        priority = player_pose.PRIORITY[fixture[3]],
                        source = "combat",
                    },
                })
            end
        end)
    end)

    t.it("draws distinct forced-state silhouettes without renderer-owned outcomes", function()
        with_graphics(function()
            for _, id in ipairs({ "combat_stagger", "combat_knockback" }) do
                player_renderer.draw(200, 300, 12, { 0.2, 0.8, 1 }, nil, {
                    facing = Vec2.new(1, 0),
                    is_keeper = false,
                    controlled = false,
                    team = "away",
                    pose = {
                        id = id,
                        priority = player_pose.PRIORITY[id],
                        source = "combat",
                    },
                })
            end
        end)
    end)
end)
