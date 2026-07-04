# Controls

## Match (current)

Two contextual action keys + sprint. The same key does the natural thing for the moment.

| Action | Keys |
|--------|------|
| Move   | Arrow keys or WASD |
| **Act** — shoot (with ball) / tackle (without) | Space |
| **Play** — pass (with ball) / switch player (without) | K |
| Sprint | Shift (hold) |
| Lob / chip modifier | L (hold) |
| Juke / Dodge | C |
| Rematch (after full time) | R or Enter |
| Toggle bloom | B (debug) |
| Quit   | Esc |

- **Shooting** (Space with the ball) aims at the goal; hold up/down to place it into a corner.
  Hold Space to **charge** a harder shot; holding left/right at release **curves** it.
- **Tackling** (Space without the ball) has one rule: normally it's a quick **standing poke**;
  while **sprinting** it's a committed **slide tackle** whose speed scales with your pace.
  Slides reach further and knock the carrier off balance, but lock you in with a longer
  recovery — *sprint + Space* is the big play, and it can miss.
- **Sprint** (hold Shift) burns a **stamina meter** (shown above the help text when not full);
  it refills whenever you're not sprinting, and the **stamina** stat sets how big the tank is.
  An empty tank means no boost until it meaningfully recovers.
- **Switching** (K without the ball) hands control to the home outfielder **nearest the ball**;
  winning the ball auto-switches control to the winner.
- **Keeping the ball**: challenges reach for the *ball*, not your body — it sticks a step ahead
  of your facing, so turning between a defender and the ball **shields** it. Defenders commit
  to their pokes and go on cooldown when they miss: keep moving, turn away, juke, or burst with
  sprint to make them whiff. At kickoff the other team must stand off (centre-circle distance).
- **Juke** is a quick sidestep with brief tackle immunity — beat a defender or escape a challenge.
- Players have **bodies**: they block and bump each other, and a slide that connects shoves and
  briefly stuns the player it hits.
- Fast shots and driven passes **ricochet off bodies** — a defender in the lane blocks the shot,
  so shoot around them, chip over them (L), or pass for a better angle. Slow balls are trapped,
  not deflected, and lobs sail over heads.
- **Finishing**: charge and aim for a corner to beat the keeper; a plain corner shot gets
  parried up and away, and anything straight at the keeper is caught. AI strikers work the same
  way — the space you give them becomes shot power, so close shooters down.

Movement is continuous (read each frame as a direction vector). Shooting is a discrete,
edge-triggered event (queued on key press, consumed on the next simulation step), so taps don't
get lost between frames.

## Menus (pre-match flow)

Mouse click to select formations/tactics and advance (Squad → Formation → Tactic → Match).

## Planned

- Keyboard navigation for menus
