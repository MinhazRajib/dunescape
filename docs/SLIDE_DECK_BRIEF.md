# DuneScape — slide deck brief

*Source material for a slide deck. One section ≈ one slide.*

## 1. The pitch

**DuneScape** — *ALL TRADES ARE FINAL.*
A pixel-art desert puzzle game built in OCaml in a single day. You are a
camel who slides until something stops you. Every keypress is a committed
trade: no take-backs mid-slide. Think before you move — because the desert
no longer waits for you to think.

## 2. The inspiration

Based on **Tomb of the Mask**'s slide-until-you-hit-a-wall movement, crossed
with classic Pokémon ice puzzles — but the action was stripped out and
replaced with *decision-making*: where you stop is decided by the board, not
your reflexes. Playtesting then pulled it back toward tension: your **moves**
stay turn-based, but the **world** went real-time. The result is a hybrid:
chess where the clock bites.

## 3. The core loop

1. Read the board (enemies and the void move while you read)
2. Press a direction — the camel slides until stopped
3. Collect **every** water drop to unlock the oasis
4. **Land exactly on it** to win (it's pass-through — overshooting is the
   signature mistake)
5. Die readable deaths, restart instantly (R), undo freely (Z), get smarter

## 4. The mechanics (the trap vocabulary)

- **Dunes** — break instantly with a 3-tile running start, or chip through
  with 3 slow bumps while something hunts you
- **Fake dunes** — identical twins that never crack; the lie reveals itself
  only when you've earned the truth
- **Quicksand** — safe to slide over, fatal to stop on; sink a pushed rock
  into it to neutralize it
- **One-way doors** seal behind you; **crumble tiles** become pits when you
  leave them — and pits are new stoppers the clever player *engineers*
- **Teleports** conserve momentum; **mirage exits** look more inviting than
  the real one
- **Stranding**: one wrong committed move can lock you out of victory — the
  game's favorite way to teach

## 5. The enemies

- **Scorpions** — patrol in real time on a wall-clock, smell you at range 5,
  and chase *faster than they patrol*
- **Vipers** — static, but their sightlines (rendered as red pips) kill
  anything that enters; their cover is a dune you are *tempted* to break
- **Oasis Power** — 6 moves of invincibility; eat the enemies, Pac-Man style

## 6. The twist

Solve the third level and the "oasis" glitches out —
*THE DESERT ISN'T DONE WITH YOU...* — revealing **the closing void**: a
churning wall gliding continuously across the desert. Four depths, and it
compounds: from the left → both sides → plus below → plus above, until the
only safe cell in the desert is its exact **center**.

## 7. Tech stack

- **OCaml** (~3,000 lines), built with **dune**, rendered with the ancient
  stdlib `Graphics` module — every sprite, particle, gradient and the 5×7
  pixel font is hand-built from `fill_rect` and `fill_ellipse`
- **Pure functional engine**: one function `step : state → direction →
  state × events` — which makes **undo** a stack of old states, **restart**
  a re-parse, and enables the killer feature ↓
- **A BFS solver machine-proves every board is beatable** (`dune runtest`)
  — levels ship with their shortest solutions as proofs, in the exact
  engine the player runs
- Levels are ASCII art in source; the parser validates them loudly
- Headless-friendly: plays in a browser via Xvfb + noVNC on any box

## 8. Design choices (and who made them)

- **Bumping a wall doesn't count as waiting** — you can't stall; timing
  gates are solved by routing (designer choice)
- **Every hazard is readable before it kills**: sightline pips, cracked
  dunes, sunken quicksand, a gliding void edge that lands exactly when it
  kills (fairness rule)
- **Playtester choices drove the big pivots**: real-time enemies, the
  continuously-gliding void, collect-ALL-water, chip-breaking dunes with
  explicit feedback, camel footprint trails, cumulative void fronts —
  all from user feedback in a single session
- Deaths are jokes, not punishments: *"THE CACTUS. OF COURSE."*

## 9. What's next

- **`harder-levels` branch** (in progress, agent-built): a *sweeping* viper
  gaze that rotates in real time, two-viper crossing zones, and all seven
  boards redesigned for higher minimum-move counts
- Sound, speedrun timer, death-count leaderboard
- A level editor — the ASCII format is already human-writable
- More trap vocabulary: sandstorm winds that bend slides, collapsing bridges

## 10. The numbers

- 1 day, ~3,000 lines of OCaml, 13+ commits
- 7 boards, every one machine-proven solvable
- Fastest possible perfect run: **58 moves** (13+8+16 desert, 18+6+5+5 void)
- Deaths required to learn that: yours will vary
