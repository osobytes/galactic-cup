# Vision

Galactic Cup is a 2D **intergalactic arcade soccer game with a manager's point of
view**.

Its core promise is:

> **Pick the five. Set the shape. Play the plan.**

You make a few fast, legible decisions before kickoff, then personally execute
them in a short 5v5 match. The management layer is valuable only when it makes
the next match more interesting.

## North star

> Manager choices visibly change what happens on the pitch.

A faster player moves faster. A stronger player hits harder. A different five
changes the available tradeoffs. A formation changes team shape. A tactic
changes off-ball behavior. The player should be able to point at the
consequence within one match.

## Identity

- **Arcade readability:** short, exaggerated, controllable matches.
- **Fast management:** one meaningful setup beat, not recurring busywork.
- **Players as characters:** names, species, roles, stats, and recognizable
  silhouettes.
- **Intergalactic sports broadcast:** strange athletes and arenas presented
  with the confidence of a televised competition.
- **Engineering as part of the craft:** deterministic pure simulation,
  data-driven content, strict types, tests, and measurable balance.

## Near-term product

The active target is the open-source showcase in
`docs/showcase_release.md`: one polished fixture from title screen to result,
with a real squad choice, three formations, three tactics, complete
onboarding/input, and public release packaging.

This is meant to stand on its own. It is not a loading screen for a future
career mode.

## Long-term direction

If the showcase is fun and players ask for more, Galactic Cup can deepen in this
order:

1. More teams and a short competition.
2. Player growth with visible one-match consequences.
3. Species skills and arena conditions, capped for readability.
4. A lightweight season and only then deeper manager systems.

Future research remains private until an idea is focused enough to become a
public proposal. The list above is a direction, not a shipping commitment.

## Design constraints

- Readable over realistic.
- Boot-to-kickoff should be fast; setup should not outlast the match.
- At most two attribute-modifying layers may be active in a match.
- Content is data; mechanisms are code.
- Match graphics remain code-driven and scalable.
- `sim/` and `data/` stay independent from LÖVE.
- New breadth waits until the current loop is complete and publicly
  presentable.
