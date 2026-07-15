# 🐫 DuneScape

**ALL TRADES ARE FINAL.**

A pixel-art desert sliding puzzle in OCaml, rendered by lovingly abusing the
OCaml `Graphics` module. You are a camel: press a direction and you glide
until something stops you — no take-backs mid-slide. But the desert no longer
waits for you: scorpions hunt on their own clock, and what comes after the
oasis... never stops moving at all.

## Build & run

```bash
opam install graphics        # once; Linux may need: sudo apt install libx11-dev
dune build
dune exec bin/main.exe       # needs an X display
```

### On a headless box (no X display)

```bash
./play.sh                    # needs: sudo apt install xvfb x11vnc novnc websockify
# then open http://localhost:6080/vnc.html and click Connect
./play.sh stop
```

Dev helpers:

```bash
dune exec bin/main.exe -- --level 3    # jump straight into a level (0-6)
dune exec test/solver.exe              # prove every board solvable (BFS)
dune exec test/solver.exe -- 2 --trace # replay a shortest solution as ASCII
dune exec test/solver.exe -- 2 --play RDLU  # replay any move string
dune runtest                           # CI check: all boards must be solvable
```

## Controls

| Key | Action |
|-----|--------|
| **W A S D** | Slide (one committed move) |
| **Z** | Undo last move |
| **R** | Restart level (instant) |
| **Esc** | Level select / back |
| **Enter** | Confirm |

## The rules of the desert

- **Slides are committed.** You stop when the desert stops you.
- **Water never stops you** — you collect it by sliding across. The oasis
  unlocks only when you've collected **every** drop on the level.
- **Dunes** break instantly if you hit them with a 3-tile running start.
  Too close? Each bump **chips** them — three bumps and they crumble. Cheap,
  but slow... and the world doesn't wait anymore.
- **Fake dunes** never break. They reveal themselves only to those who earned
  the truth.
- **Quicksand** is safe to slide *over* and fatal to *stop* on. A pushed rock
  that lands on it sinks — and packs it solid.
- **One-way doors** seal behind you. **Crumble tiles** become pits when you
  leave them — and pits stop slides, which the clever will exploit.
- **Scorpions** walk in real time and charge when they smell you
  (radius 5; they give up at 8). **Vipers** don't move; their sightlines
  (rendered in red) kill anything that enters.
- **Oasis Power** protects you for 6 moves and lets you eat enemies.
- If you strand yourself, that's yours to own. `R` is right there.

## After the third level

The oasis is not what it seems. What follows is **the closing void** — a
churning wall that glides across the desert in real time, four depths deep,
and it compounds: first it comes from the left, then both sides, then below
joins in, and at the last depth it closes from *everywhere*. Each gate leads
deeper; on the final board the only safe cell in the desert is its exact
**center**.

## How it's put together

```
src/   pure game logic (library `game`) — no graphics
  types.ml    tiles, enemies, state, tuning constants
  levels.ml   all seven boards as ASCII + metadata
  board.ml    parser/validator, ASCII debug dumps
  slide.ml    the slide resolver + real-time world ticks
test/
  solver.ml   BFS proof of solvability for every board (`dune runtest`)
bin/   rendering & shell (executable `main`)
  palette.ml  day / dusk palettes        font.ml    5x7 chunky pixel font
  sprites.ml  pixel-art sprites          fx.ml      particles, shake, glitch
  render.ml   tiles, void, HUD, screens  main.ml    turn loop + world clock
```

Because `Slide.step` is a pure function over an immutable state, undo is a
stack of old states, restart is re-parsing the level, and the solver
exhaustively proves each board beatable in the exact engine you play.
(Real-time hazards — scorpions and the void — are the solver's one
concession: they're dodged with timing, so it verifies the maze beneath them.)
