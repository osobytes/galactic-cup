# Controls

## Match (current)

| Action | Keys |
|--------|------|
| Move   | Arrow keys or WASD |
| Shoot  | Space or J |
| Shoot (charge) | Space or J (hold to charge, release to fire) |
| Pass   | K |
| Dash / Tackle | Left Shift or X |
| Juke / Dodge | C |
| Switch player | Tab or Q |
| Toggle bloom | B (debug) |
| Quit   | Esc |

- **Shooting** aims at the goal; hold up/down while shooting to place the ball into a corner.
  Hold the shoot key to **charge** a harder shot; holding a left/right direction at release
  **curves** it.
- **Dash** is a forward speed burst; dashing into a ball-carrier **tackles** them.
- **Juke** is a quick sidestep with brief tackle immunity — beat a defender or escape a challenge.

Movement is continuous (read each frame as a direction vector). Shooting is a discrete,
edge-triggered event (queued on key press, consumed on the next simulation step), so taps don't
get lost between frames.

## Menus (pre-match flow)

Mouse click to select formations/tactics and advance (Squad → Formation → Tactic → Match).

## Planned

- Dash / tackle
- Keyboard navigation for menus
