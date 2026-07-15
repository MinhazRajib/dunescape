(* Level data. Boards are 20x13 ASCII, validated by [Board.parse_exn].

   Legend:
     '#' solid rock        '.' empty sand      '~' breakable dune (3 hp)
     '%' fake dune         'o' water drop      'X' cactus
     '1'..'4' teleport pairs                   '>' '<' '^' 'v' one-way door
     ':' crumble tile      'q' quicksand       'O' push rock
     '?' false exit        'E' exit / gate     'S' camel spawn
     's' scorpion (patrol in [patrols])        'V' viper (static)
     'P' oasis power

   The exit unlocks only when EVERY water drop has been collected.
   [voids] lists the sides an advancing wall comes from (the finale's
   job application).  [next] chains levels: winning loads that index;
   [next = None] on a void level means victory. *)

type spec = {
  name : string;
  intro : string;
  ascii : string array;
  threshold : int; (* legacy; the parser recomputes it as ALL water *)
  patrols : ((int * int) * (int * int)) list;
  twist : bool;
  voids : Types.dir list;
  next : int option;
}

let level_1 =
  {
    name = "THE OASIS TRAIL";
    intro = "SLIDE UNTIL SOMETHING STOPS YOU.";
    threshold = 0;
    patrols = [];
    twist = false;
    voids = [];
    next = Some 1;
    ascii =
      [|
        "####################";
        "#S...o....##########";
        "#..#..#...####..####";
        "#...##....####v.####";
        "#...##....####.o####";
        "#.#....#..####..####";
        "#.#...........E....#";
        "#.....#.X###.##.##.#";
        "#.#.............X..#";
        "#..#.......#.......#";
        "#...#...o....~o.#.##";
        "#......#..#........#";
        "####################";
      |];
  }

let level_2 =
  {
    name = "THE DEEP DESERT";
    intro = "THE DESERT LIES.";
    threshold = 0;
    patrols = [ ((8, 12), (11, 12)) ];
    twist = false;
    voids = [];
    next = Some 2;
    ascii =
      (* The viper carves a plus of death; the dune at (5,6) is its western
         cover.  The bait water at (5,8) sits INSIDE the gaze — the oasis
         power at (2,8) is collected mid-dive down col 8, protecting that
         very slide.  The mirage now sits at the end of the mandatory
         row-11 run.  Every drop is required. *)
      [|
        "####################";
        "#S...o...#.......###";
        "#.......P.#.....#E.#";
        "#..##..............#";
        "#..................#";
        "#o....~.o.V..#.....#";
        "#.................^#";
        "#...##....#........#";
        "#...........s......#";
        "#..................#";
        "#..................#";
        "#....o....o.......?#";
        "####################";
      |];
  }

let level_3 =
  {
    name = "THE RECKONING";
    intro = "TRUST NOTHING.";
    threshold = 0;
    patrols = [ ((9, 8), (11, 8)); ((6, 16), (10, 16)) ];
    twist = true;
    voids = [];
    next = None;
    ascii =
      (* Two scorpions now: the col-8 gate and an east watchman over the
         crumble endgame.  The col-13 wall has two breakable dunes: the
         north one rockets you into a cactus, the south one is the way in. *)
      [|
        "####################";
        "#So#....#....~..X..#";
        "#............#q....#";
        "#.........#..#.#...#";
        "#............#...:.#";
        "#o...........#...E.#";
        "#......~..V#.#..s..#";
        "#............#.....#";
        "##....%...#..#.....#";
        "#.....o.s....~.....#";
        "#............#.....#";
        "#....o....o.%#..:..#";
        "####################";
      |];
  }

(* ---- THE APPLICATION ----
   The oasis was a mirage.  What advances across the desert is a job
   application, one ruled line at a time.  No water out here — just escape.
   Four pages; the gate on each leads deeper.  On the last page you must
   reach the very center of the map. *)

let page_1 =
  {
    name = "PAGE 1: PERSONAL INFORMATION";
    intro = "IT'S COMING FROM THE LEFT. RUN.";
    threshold = 0;
    patrols = [];
    twist = false;
    voids = [ Types.Left ];
    next = Some 4;
    ascii =
      (* A comb of lanes with one chip-mandatory dune on the middle row:
         three bumps to crack it while the paper closes in. *)
      [|
        "####################";
        "#.S....#..#.....#..#";
        "#...#..#..#q.#..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#.##..#.#.#.#";
        "#...#..#...~.#...E##";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#..#..#..#..#..#";
        "#...#q....#..#..#..#";
        "####################";
      |];
  }

let page_2 =
  {
    name = "PAGE 2: EMPLOYMENT HISTORY";
    intro = "NOW IT'S COMING FROM BOTH SIDES.";
    threshold = 0;
    patrols = [];
    twist = false;
    voids = [ Types.Left; Types.Right ];
    next = Some 5;
    ascii =
      (* Symmetric squeeze: climb the center spine while both margins close.
         The teleport pair swaps you between the doomed flanks. *)
      [|
        "####################";
        "#.......#E.........#";
        "#..q...........q...#";
        "#...##........###..#";
        "#........#.........#";
        "#.....#......#.....#";
        "#..1......#......1.#";
        "#.....#......#.....#";
        "#........#.........#";
        "#....#.........#...#";
        "#..................#";
        "#q.......S........q#";
        "####################";
      |];
  }

let page_3 =
  {
    name = "PAGE 3: REFERENCES";
    intro = "IT RISES FROM BELOW.";
    threshold = 0;
    patrols = [];
    twist = false;
    voids = [ Types.Down ];
    next = Some 6;
    ascii =
      (* Climb through offset slots in three shelf walls while the paper
         rises.  The long panicked skid right ends in quicksand. *)
      [|
        "####################";
        "#...............#E.#";
        "#..................#";
        "####.####.####.###.#";
        "#..................#";
        "#..................#";
        "#.###.####.####.####";
        "#...............#..#";
        "#..................#";
        "###.####.####.####.#";
        "#...#.............q#";
        "#.S................#";
        "####################";
      |];
  }

let page_4 =
  {
    name = "PAGE 4: SIGN HERE.";
    intro = "REACH THE CENTER. DO NOT SIGN.";
    threshold = 0;
    patrols = [];
    twist = false;
    voids = [ Types.Up ];
    next = None;
    ascii =
      (* The final line descends from the top; the only safe cell in the
         desert is its exact center. *)
      [|
        "####################";
        "#..................#";
        "#..................#";
        "#..................#";
        "#..................#";
        "#........##........#";
        "#.......#E.........#";
        "#.....#............#";
        "#..........#..q....#";
        "#........#.........#";
        "#....#.............#";
        "#........S.........#";
        "####################";
      |];
  }

let all = [| level_1; level_2; level_3; page_1; page_2; page_3; page_4 |]

(* Index the Level-3 twist jumps to (start of the application chain). *)
let finale_index = 3

(* How many cards the level-select screen shows (3 levels + the hidden one). *)
let card_count = 4
