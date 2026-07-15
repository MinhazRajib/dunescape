(* Core types and tuning constants for DuneScape.
   The game state [gs] is immutable: [Slide.step] returns a fresh state.
   This makes undo, restart and the BFS solver trivial. *)

type dir = Up | Down | Left | Right

type tile =
  | Empty
  | Solid                    (* unbreakable rock; stops slides *)
  | Dune                     (* breakable if hit with runway >= break_runway *)
  | Fake_dune                (* herring: looks like Dune, never breaks *)
  | Water                    (* collect; does NOT stop the slide *)
  | Cactus                   (* instant death *)
  | Teleport of int          (* paired by id; warp + keep sliding *)
  | One_way of dir           (* enter only while moving in [dir]; seals on exit *)
  | Crumble                  (* safe once; becomes Pit when you leave it *)
  | Pit                      (* collapsed crumble: blocks slides *)
  | Push_rock                (* shoved ahead to its own stopper *)
  | False_exit               (* mirage: looks like the oasis, does nothing *)
  | Exit                     (* win by STOPPING on it with enough water *)

type ekind = Scorpion | Viper

type estate = Patrol | Chase

type enemy = {
  kind : ekind;
  cell : int * int;          (* row, col *)
  st : estate;
  route : (int * int) array; (* patrol cycle; [||] = static *)
  ri : int;                  (* index in route of current patrol target *)
}

type death_reason = Pricked | Stung | Gazed | Voided

type status = Alive | Dead of death_reason | Won | Twisted

type gs = {
  grid : tile array array;   (* grid.(row).(col); rows top -> bottom *)
  camel : int * int;
  facing : dir;
  water : int;
  threshold : int;           (* water needed to unlock the exit *)
  moves : int;
  enemies : enemy list;
  powerups : (int * int) list; (* cells holding Oasis Power *)
  power_left : int;          (* oasis-power turns remaining (0 = none) *)
  void_col : int;            (* rightmost voided column; -1 = void inactive *)
  twist : bool;              (* stopping on the unlocked exit twists instead of winning *)
  status : status;
}

(* Events describe everything that happened during one turn, in order.
   The renderer replays them as the camel animates along the path. *)
type event =
  | Bumped of (int * int) * bool (* cell, [true] = fake dune revealed itself *)
  | Broke of (int * int)
  | Collected of (int * int)
  | Got_power of (int * int)
  | Teleported of (int * int) * (int * int)
  | Sealed of (int * int)
  | Crumbled of (int * int)
  | Pushed of (int * int) * (int * int)
  | Ate_enemy of (int * int)
  | Mirage of (int * int)
  | Exit_locked of (int * int)
  | Died of death_reason * (int * int)
  | Level_won
  | Twist_triggered

(* ---- Board dimensions ---- *)

let rows = 13
let cols = 20

let is_in_bounds r c = r >= 0 && r < rows && c >= 0 && c < cols

let delta = function
  | Up -> (-1, 0)
  | Down -> (1, 0)
  | Left -> (0, -1)
  | Right -> (0, 1)

let manhattan (r1, c1) (r2, c2) = abs (r1 - r2) + abs (c1 - c2)

(* ---- Tuning constants (README section 20) ---- *)

let break_runway = 3       (* tiles of runway needed to shatter a Dune *)
let scorpion_detect = 3    (* manhattan radius that flips Patrol -> Chase *)
let scorpion_escape = 5    (* radius beyond which a chaser gives up *)
let viper_range = 6        (* line-of-sight reach in tiles *)
let oasis_power_moves = 6  (* protected turns, counting the pickup turn *)
let void_step_per_move = 1 (* columns the void advances each move *)
