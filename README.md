# 🐫 DuneScape

A **turn-based pixel-art desert sliding puzzle** in OCaml, rendered by lovingly
abusing the OCaml `Graphics` module. You are a camel: press a direction and you
glide until something stops you. No reflex, no timing — every move is a
commitment you cannot take back mid-slide.

Collect water, unlock the oasis, and land on it — past the cacti, the one-way
doors, the false exits, the fake-breakable dunes, the clockwork scorpions and
the vipers' lethal sightlines. And when you finally reach the oasis at the end…
the desert has one last trick waiting.

*(Full design document: `DuneScape_README.md`.)*

## Build & run

```bash
opam install graphics        # once; Linux may need: sudo apt install libx11-dev
dune build
dune exec bin/main.exe       # needs an X display
```

### On a headless box (no X display)

`dune exec bin/main.exe` will fail with `Graphic_failure("Cannot open display …")`.
Use the bundled launcher, which runs the game on a virtual display and serves
it to your browser:

```bash
./play.sh                    # needs: sudo apt install xvfb x11vnc novnc websockify
# then open http://localhost:6080/vnc.html and click Connect
./play.sh stop               # tear down
```

In VS Code remote sessions port 6080 is forwarded automatically (see the
PORTS panel). Keyboard input goes straight through — WASD away.

Dev helpers:

```bash
dune exec bin/main.exe -- --level 2    # jump straight into a level (0-based)
dune exec test/solver.exe              # prove every level solvable (BFS)
dune exec test/solver.exe -- 1 --trace # replay level 1's shortest solution
dune runtest                           # CI check: all levels must be solvable
```

## Controls

| Key | Action |
|-----|--------|
| **W A S D** | Slide (one committed move — you can't stop mid-slide) |
| **Z** | Undo last move |
| **R** | Restart level (instant) |
| **Esc** | Level select / back |
| **Enter** | Confirm |

## How it's put together

```
src/   pure game logic (library `game`) — no graphics
  types.ml    tiles, enemies, immutable game state, tuning constants
  levels.ml   the four boards as ASCII + metadata
  board.ml    parser/validator, ASCII debug dumps
  slide.ml    THE slide resolver: one keypress -> new state + events + path
test/
  solver.ml   BFS over Slide.step: proves solvability, prints shortest
              solutions, replays them as ASCII traces (wired to `dune runtest`)
bin/   rendering & shell (executable `main`)
  palette.ml  day / dusk palettes        font.ml    5x7 chunky pixel font
  sprites.ml  pixel-art sprite grids     fx.ml      particles, shake, glitch
  render.ml   tiles, HUD, screens       main.ml    turn loop, animations, twist
```

Because `Slide.step` is a pure function over an immutable state, undo is a
stack of old states, restart is re-parsing the level, and the solver can
exhaustively search the real game — every shipped level is machine-proven
solvable, in the exact engine the player runs.

## Design decisions worth knowing

- **Bumping a wall does not advance the world** — you cannot stall to cheese
  enemy patrol timing; gates are solved by routing.
- **Breaking a dune needs 3 tiles of runway and spends your momentum** —
  back-to-back dunes are an unbreakable pair, and every break removes a
  stopper you might have needed.
- **Water, exits and mirages never stop your slide** — you win by *stopping*
  on the oasis, which is its own puzzle.
- **One-way doors seal behind you; crumble tiles become pits when you leave
  them** — pits then *stop* slides, which clever players can exploit.
- **Viper sightlines are rendered** (red pips) — the information is fair;
  the mistakes are yours.
