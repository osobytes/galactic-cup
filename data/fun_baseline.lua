-- Fun-signature tripwire baseline. REGENERATE, don't hand-edit:
--   love . --tripwire write
-- ...and only after confirming the drift is intended, re-running
-- `love . --sim 100`, and logging the shift in the drift log of
-- docs/design/fun_metrics.md.
return {
    n = 30,
    fun = 0.343941,
    goals_total = 1.633333,
    shots_per_goal = 27.644231,
    save_rate = 0.876442,
    pass_completion = 0.578242,
    turnovers_per_min = 3.331794,
    possession_balance = 0.427225,
    longest_drought_s = 11.958889,
    decided_late = 0.586640,
    controlled_dribble_close_share = 0.850648,
    controlled_dribble_sprint_share = 0.256659,
    controlled_dribble_juke_share = 0.024709,
    controlled_dribble_touches_per_min = 84.532468,
    controlled_dribble_heavy_losses_per_min = 1.440147,
    ai_dribble_close_share = 0.884362,
    ai_dribble_sprint_share = 0.112062,
    ai_dribble_juke_share = 0.037421,
    ai_dribble_touches_per_min = 77.627430,
    ai_dribble_heavy_losses_per_min = 2.597098,
}
