# Vision

Galaticup is a 2D **intergalactic arcade soccer manager RPG**.

It blends:

- **Manager immersion** (squad, formation, tactics) — starts tiny, deepens toward a full
  management sim over time (see `docs/design/manager-mode.md`).
- **Arcade readability** (short, exaggerated, controllable matches) — Mario Strikers energy.
- **RPG growth** (stats, traits, XP, level-ups, morale) — players are *characters*.
- **Fictional universe** (alien species, planets, weird arenas) — freedom from licensing,
  excuse for exaggerated mechanics.

## North-star principle

> Manager choices visibly change what happens on the pitch.

A faster player moves faster; a stronger player shoots harder; a formation changes shape; a
tactic changes behavior. The link between the management layer and the match layer is the whole
game — it exists from day one (see M1).

## What this is NOT (yet)

No real teams/players, no 11v11, no contracts/transfers, no league simulation, no story mode,
no realistic physics. We build the *loop* first, then deepen it.

## Design constraints

- Readable over realistic. If a player stands still you should still know team, facing,
  selection, position, possession, fatigue, active trait.
- Content is data (players/teams/tactics/traits/arenas), mechanism is code. See AGENTS.md §8.
- Match graphics are code-driven shapes first; AI portraits/icons only on manager screens later.
