# DuneScape — demo-day notes

## Launching

```bash
cd maze && dune exec bin/main.exe
```

Window is 960x720. WASD to slide, Z undo, R restart, Esc menu, Enter confirm.

## Suggested 5-minute demo script

1. **Title screen** — let the camel walk across the parallax dunes for a beat.
2. **Level 1, The Oasis Trail** — press D immediately: the camel slides across
   a water drop (doesn't stop!) and thumps into a wall. That's the whole game
   in one keystroke. Show the overshoot: mid-level, the obvious slide toward
   the oasis glides straight *past* it.
3. **Die once on purpose** (any cactus) — instant reset, snarky message.
   Death is the learning loop, not a punishment.
4. **Level 2, The Deep Desert** — point out the viper's red sightline pips and
   the dune that is your *cover* (breaking it looks tempting — it kills you on
   that very slide). Land on the first oasis you see: *it's a mirage*.
5. **Level 3, The Reckoning** — the wall of the level has two breakable dunes;
   the tempting one rockets you into a cactus. The exit can only be landed on
   after you convert two crumble tiles into pits and use them as stoppers.
6. **The twist** — solve level 3 and the "oasis" glitches out:
   *THE DESERT ISN'T DONE WITH YOU...* → the Closing Void: the screen-eating
   wall advances one column per move. A race of foresight, not fingers.
7. **Victory screen.**

## Spoilers — machine-verified shortest solutions

| Level | Moves | Solution (WASD ↔ RDLU: R=D, L=A, U=W, D=S) |
|-------|-------|---------------------------------------------|
| 1 The Oasis Trail | 13 | `RDRDLDLULRULD` |
| 2 The Deep Desert | 9  | `RLDRDLRUL` |
| 3 The Reckoning   | 15 | `RDLRLURDLRURDLU` |
| ∅ The Closing Void| 13 | `DRURDRURDRULD` |

Re-derive anytime: `dune exec test/solver.exe -- <n> --trace`.

## If something goes wrong on stage

- `R` fixes every gameplay state; `Esc` → level select re-enters any level.
- All four levels are proven solvable by `dune runtest` (BFS over the actual
  engine). If a level ever regresses, that test fails.
- The game needs an X display; on a headless box:
  `Xvfb :99 & DISPLAY=:99 dune exec bin/main.exe`.

## Deliberate rule choices (vs. the design doc)

- Runway **resets** after breaking a dune → back-to-back dunes are a wall.
- A zero-tile bump does **not** tick the world (no stall-waiting; enemy gates
  are solved by routing, void never advances on a bump).
- One-way doors seal when you *leave* the door tile; crumble tiles become
  pits when you *leave* them — so you may rest on both safely for a turn, and
  pits become new stoppers you can exploit (level 3's exit depends on it).
- The false exit has a subtle heat-wobble; the real exit shimmers pale while
  locked and glows gold-rimmed when unlocked.
