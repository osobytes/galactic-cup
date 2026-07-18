local contract = require("game.match_contract")
local hit = require("game.ui.hit")
local result_screen = require("game.screens.result")
local t = require("spec.support.runner")

local VP = { w = 960, h = 540 }

---@param home_score integer
---@param away_score integer
---@param stats TeamResultStats?
---@return ProductMatchResult
local function make_result(home_score, away_score, stats)
    return assert(contract.new_result({
        home_team_id = "nebula",
        away_team_id = "orion",
        home_score = home_score,
        away_score = away_score,
        home_stats = stats,
        away_stats = stats,
    }))
end

t.describe("product result screen", function()
    t.it("presents win, loss, and draw outcomes explicitly", function()
        local cases = {
            { 2, 1, "NEBULA FC WIN" },
            { 0, 3, "ORION MINERS WIN" },
            { 0, 0, "HONORS EVEN" },
        }
        for _, case in ipairs(cases) do
            local state = result_screen.new_state(VP, {
                result = make_result(case[1], case[2]),
            })
            local outcome = assert(hit.find(result_screen.layout(state), "outcome"))
            t.eq(outcome.text, case[3])
        end
    end)

    t.it("degrades missing metrics and zero-event fixtures without inventing values", function()
        local missing = result_screen.layout(result_screen.new_state(VP, {
            result = make_result(0, 0),
        }))
        t.is_true(assert(assert(hit.find(missing, "stats")).text):match("—") ~= nil)

        local zero = result_screen.layout(result_screen.new_state(VP, {
            result = make_result(0, 0, {
                shots = 0,
                possession = 0,
                saves = 0,
                pass_completion = 0,
            }),
        }))
        local text = assert(assert(hit.find(zero, "stats")).text)
        t.is_true(text:match("SHOTS%s+0") ~= nil)
        t.is_true(text:match("0%%") ~= nil)
    end)
end)
