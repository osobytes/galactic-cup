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
  to their pokes, go on cooldown when they miss, and **stumble** after lunging past a shielded
  ball — bait the poke, then break away. At kickoff the other team must stand off
  (centre-circle distance). But shielding is **active**: the presser hunts the ball itself and
  will work around your body, and a defender leaning on you shoves you off your spot — standing
  still is never safe, keep turning or move.
- **You control your keeper**: when your keeper gathers the ball, control switches to it.
  **K** (hold to charge) throws — the longer you hold, the further along your aim it picks a
  teammate; **Space** (hold to charge) is a **punt** off the foot, clearing high toward
  mid/front field as far as you charge it. You can walk it around inside your box; after ~5
  seconds the keeper distributes on its own (six-second rule).
- **Crosses**: a lofted pass (hold L + K) from wide in the attacking third becomes a **cross**
  aimed at your teammate in the box — AI wingers swing them in too.
- **Aerial play**: an airborne ball at head height can be met first-time — press **Space**
  under it. Above the waist it's a **header** (safe, placed); lower it's a **volley** — much
  harder, but with a real chance of skying it. The arena is a **cage**: a skied ball bounces
  off the ceiling and rains back into play. AI attackers head crosses at goal; AI defenders
  head danger clear.
- **The keeper is protected**: while a keeper holds the ball, everyone backs well off its ring
  (laws of the game — a keeper in possession can't be challenged), and markers drop off the
  outlets to guard the passing lanes instead of standing on the receiver's boots. Read the
  throw and step into the lane, or press the receiver's first touch.
- **Winning the ball**: your poke has generous reach and a forgiving window. Approach from the
  ball side for the extended reach — but at body-contact range your poke works from ANY angle
  (a toe through the legs), so chasing a carrier down is always winnable. When the opponent
  wins the ball, control auto-switches to your best-placed defender. AI players need a **settling touch** (~a third of a
  second) after receiving before they can pick a pressured pass — press them on the touch and
  the ball is winnable. Passes released into an adjacent defender get dinked over them; a ball
  dropping onto its receiver can't be walled off, only flat drilled balls can.
- **Juke** is a quick sidestep with brief tackle immunity — beat a defender or escape a challenge.
- Players have **bodies**: they block and bump each other, and a slide that connects shoves and
  briefly stuns the player it hits.
- Fast shots and driven passes **ricochet off bodies** — a defender in the lane blocks the shot,
  so shoot around them, chip over them (L), or pass for a better angle. Slow balls are trapped,
  not deflected, and lobs sail over heads.
- **Finishing**: charge and aim for a corner to beat the keeper. Whether a reached save is
  **held or parried** is a dice roll weighted by shot pace and the keeper's handling — soft,
  central shots stick in the gloves almost every time; hot or full-stretch balls usually get
  pushed away (rebounds!), and a charged rocket straight at the keeper is a genuine coin flip.
  AI strikers work the same way — the space you give them becomes shot power, so close
  shooters down.

Movement is continuous (read each frame as a direction vector) and **momentum-based**: players
accelerate to top speed over ~0.25 s and decelerate to a stop over ~0.18 s. Sprinting commits
you to your current direction — reversing while at full speed takes an arc, not an instant pivot.
Your **facing** follows your actual velocity so you can still aim while braking (the ball sticks
to wherever you're pointing, not where you're running).
Shooting is a discrete, edge-triggered event (queued on key press, consumed on the next
simulation step), so taps don't get lost between frames.

## Menus (pre-match flow)

Mouse click to select formations/tactics and advance (Squad → Formation → Tactic → Match).

## Planned

- Keyboard navigation for menus
