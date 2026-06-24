# Controls

## Match (current)

| Action | Keys |
|--------|------|
| Move   | Arrow keys or WASD |
| Shoot  | Space or J |
| Pass   | K |
| Dash / Tackle | Left Shift or X |
| Switch player | Tab or Q |
| Toggle bloom | B (debug) |
| Quit   | Esc |

Shooting aims at the goal; hold a vertical direction (up/down) while shooting to place
the ball into a corner. Dash is a speed burst; dashing into a ball-carrier tackles them.

Movement is continuous (read each frame as a direction vector). Shooting is a discrete,
edge-triggered event (queued on key press, consumed on the next simulation step), so taps don't
get lost between frames.

## Menus (pre-match flow)

Mouse click to select formations/tactics and advance (Squad → Formation → Tactic → Match).

## Planned

- Dash / tackle
- Keyboard navigation for menus
