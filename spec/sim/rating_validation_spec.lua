local t = require("spec.support.runner")
local headless = require("sim.headless")
local validation = require("sim.rating_validation")

t.describe("rating validation", function()
    t.it("plays fair home-proxy legs on common seeds and reports the curve", function()
        local original_run_match = headless.run_match
        local calls = {}
        local ranks = {
            rating_prospects = 1,
            rating_developing = 2,
            rating_balanced = 3,
            rating_contenders = 4,
            rating_elite = 5,
        }
        headless.run_match = function(opts)
            calls[#calls + 1] = opts
            local home_rank = assert(ranks[opts.home.id])
            local away_rank = assert(ranks[opts.away.id])
            local winner = home_rank > away_rank and "home" or "away"
            return {
                seed = opts.seed,
                metrics = {},
                desirability = {},
                score = winner == "home" and { home = 1, away = 0 } or { home = 0, away = 1 },
                winner = winner,
            }
        end

        -- Preserve the real harness module and restore it even if validation fails.
        local ok, result = pcall(validation.run, 2)
        headless.run_match = original_run_match
        t.is_true(ok, tostring(result))
        ---@cast result RatingValidationResult

        t.eq(#result.squads, 5)
        t.eq(#result.pairs, 10)
        t.eq(#calls, 40, "10 pairs x 2 seeds x 2 orientations")
        for i = 1, #calls, 2 do
            local first, second = calls[i], calls[i + 1]
            t.eq(first.seed, second.seed, "both orientations use the same seed")
            t.eq(first.home.id, second.away.id, "home and away are swapped")
            t.eq(first.away.id, second.home.id, "home and away are swapped")
            t.eq(first.bot, "home")
            t.eq(second.bot, "home")
        end
        t.eq(result.wins, 40)
        t.eq(result.draws, 0)
        t.eq(result.losses, 0)
        t.eq(result.win_rate, 1)
        t.eq(result.score_share, 1)
        t.eq(result.above_half_pairs, 10)

        local report = validation.report(result)
        t.is_true(report:find("relative bot%-proxy result") ~= nil)
        t.is_true(report:find("curve steepness %(OLS score share%)") ~= nil)
    end)
end)
