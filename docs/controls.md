# Controls

## Match (current)

| Action | Keys |
|--------|------|
| Move   | Arrow keys or WASD |
| Shoot  | Space or J |
| Shoot (charge) | Space or J (hold to charge, release to fire) |
| Pass   | K |
| Tackle | Left Shift or X |
| Juke / Dodge | C |
| Switch player | Tab or Q |
| Toggle bloom | B (debug) |
| Quit   | Esc |

- **Shooting** aims at the goal; hold up/down while shooting to place the ball into a corner.
  Hold the shoot key to **charge** a harder shot; holding a left/right direction at release
  **curves** it.
- **Tackle** is context-aware: standing still you make a quick **standing poke**; while moving
  you commit a **slide tackle** whose speed scales with your current pace. Slides reach further
  and knock the carrier off balance, but lock you in with a longer recovery.
- **Juke** is a quick sidestep with brief tackle immunity — beat a defender or escape a challenge.
- **Switch** hands control to the home outfielder **nearest the ball** (not a fixed rotation),
  so when defending it always picks the player you actually want.
- Players have **bodies**: they block and bump each other, and a slide that connects shoves and
  briefly stuns the player it hits.

Movement is continuous (read each frame as a direction vector). Shooting is a discrete,
edge-triggered event (queued on key press, consumed on the next simulation step), so taps don't
get lost between frames.

## Menus (pre-match flow)

Mouse click to select formations/tactics and advance (Squad → Formation → Tactic → Match).

## Planned

- Keyboard navigation for menus
