(* Level data. Boards are 20x13 ASCII, validated by [Board.parse_exn].

   Legend:
     '#' solid rock        '.' empty sand      '~' breakable dune
     '%' fake dune         'o' water drop      'X' cactus
     '1'..'4' teleport pairs                   '>' '<' '^' 'v' one-way door
     ':' crumble tile      'O' push rock       '?' false exit (mirage)
     'E' exit (oasis)      'S' camel spawn
     's' scorpion (patrol given in [patrols])  'V' viper (static)
     'P' oasis power *)

type spec = {
  name : string;
  intro : string;
  ascii : string array;
  threshold : int;
  patrols : ((int * int) * (int * int)) list;
      (* scorpion spawn cell -> far end of its back-and-forth patrol line *)
  twist : bool; (* stopping on the unlocked exit triggers the twist *)
  void_start : int; (* -1 = no void; otherwise initial voided column *)
}

let level_1 =
  {
    name = "THE OASIS TRAIL";
    intro = "SLIDE UNTIL SOMETHING STOPS YOU.";
    threshold = 3;
    patrols = [];
    twist = false;
    void_start = -1;
    ascii =
      [|
        "####################";
        "#S...o....#....o...#";
        "#.........#..##....#";
        "#..#...#..#...#..#.#";
        "#..#...#..v...#..#.#";
        "#..#o..#..#..##..#.#";
        "#..#...#..#..#E..#.#";
        "#..#####..#..###.#.#";
        "#.........#......#.#";
        "#..X...............#";
        "#..........~...#...#";
        "#.o........#...#..X#";
        "####################";
      |];
  }

let level_2 =
  {
    name = "THE DEEP DESERT";
    intro = "THE DESERT LIES.";
    threshold = 4;
    patrols = [ ((3, 7), (3, 4)) ];
    twist = false;
    void_start = -1;
    ascii =
      [|
        "####################";
        "#S.....#....o..#..?#";
        "#......#..#....#...#";
        "#..#...s..#..#.....#";
        "#..#......#..#..####";
        "#..###v###.......o.#";
        "#..#.....#..V......#";
        "#..#.oo..#.....#...#";
        "#..#.....#..#..#...#";
        "#..#####.#..#..##v##";
        "#....P...#..#....E.#";
        "#........#..o......#";
        "####################";
      |];
  }

let level_3 =
  {
    name = "THE RECKONING";
    intro = "TRUST NOTHING.";
    threshold = 4;
    patrols = [ ((6, 4), (6, 8)) ];
    twist = true;
    void_start = -1;
    ascii =
      [|
        "####################";
        "#S...o...%.....o...#";
        "#..#.....#..#......#";
        "#..#..#..~..#..:...#";
        "#..#..#.....#..#...#";
        "#..o..#..#..#..#.o.#";
        "#.....#..#..V..#...#";
        "#..#..#..#.....#...#";
        "#..#..~..#..#..~...#";
        "#..#..#..#..#..#...#";
        "#..:..#..O..#..#.E.#";
        "#.....#.....#......#";
        "####################";
      |];
  }

(* The finale (README section 13, Option A): the oasis was a mirage.  The void
   advances one column after every move; out-plan it and stop on the true
   exit.  Fully turn-based — a race of foresight, not fingers. *)
let level_void =
  {
    name = "THE CLOSING VOID";
    intro = "THE DESERT ISN'T DONE WITH YOU...";
    threshold = 0;
    patrols = [];
    twist = false;
    void_start = 0;
    ascii =
      (* A comb maze: wall columns with alternating top/bottom gaps force a
         committed D/R/U zigzag eastward while the void eats the columns
         behind you.  Two dunes give mid-run breaks (runway 4 upward); the
         exit is landed by the L-then-D finish at the top-right. *)
      [|
        "####################";
        "#.S.#.....#..o..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#.~#..#..#..#E~#";
        "#...#..#..#..#..##.#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#....o.#.....#.....#";
        "####################";
      |];
  }

let all = [| level_1; level_2; level_3; level_void |]

(* Index in [all] of the hidden finale (reached via the Level-3 twist). *)
let void_index = 3
