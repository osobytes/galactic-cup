# Controls

## Match (current)

| Action | Keys |
|--------|------|
| Move   | Arrow keys or WASD |
| Shoot  | Space or J |
| Quit   | Esc |

Movement is continuous (read each frame as a direction vector). Shooting is a discrete,
edge-triggered event (queued on key press, consumed on the next simulation step), so taps don't
get lost between frames.

## Planned

- Pass (later: nearest teammate in aim direction)
- Dash / tackle
- Switch active player
