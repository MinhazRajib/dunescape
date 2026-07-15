(* Core types and tuning constants for DuneScape.
   The game state [gs] is immutable: [Slide.step] returns a fresh state.
   This makes undo, restart and the BFS solver trivial. *)

type dir = Up | Down | Left | Right

type tile =
  | Empty
  | Solid                    (* unbreakable rock; stops slides *)
  | Dune of int              (* breakable: runway >= break_runway breaks it
                                instantly; each weak bump chips 1 hp *)
  | Fake_dune of int         (* herring: never breaks; int counts bumps taken *)
  | Water                    (* collect; does NOT stop the slide *)
  | Cactus                   (* instant death *)
  | Teleport of int          (* paired by id; warp + keep sliding *)
  | One_way of dir           (* enter only while moving in [dir]; seals on exit *)
  | Crumble                  (* safe once; becomes Pit when you leave it *)
  | Pit                      (* collapsed crumble: blocks slides *)
  | Quicksand                (* safe to slide OVER; deadly to STOP on *)
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

type death_reason = Pricked | Stung | Gazed | Voided | Sunk

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
  voids : (dir * int) list;  (* advancing walls: (side it comes FROM, front).
                                Left,p eats cols <= p;  Right,p eats cols >= p;
                                Up,p eats rows <= p;    Down,p eats rows >= p *)
  twist : bool;              (* stopping on the unlocked exit twists instead of winning *)
  status : status;
}

(* Events describe everything that happened during one turn, in order.
   The renderer replays them as the camel animates along the path. *)
type event =
  | Bumped of (int * int) * bool (* cell, [true] = fake dune revealed itself *)
  | Chipped of (int * int) * int (* dune damaged by a weak bump; hits left *)
  | Rock_sunk of (int * int)     (* push rock swallowed by quicksand *)
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

(* Is (r,c) consumed by any advancing wall? *)
let is_voided voids (r, c) =
  List.exists
    (fun (side, p) ->
      match side with
      | Left -> c <= p
      | Right -> c >= p
      | Up -> r <= p
      | Down -> r >= p)
    voids

(* ---- Tuning constants (README section 20, retuned after playtest) ---- *)

let break_runway = 3       (* tiles of runway needed to shatter a Dune *)
let dune_hp = 3            (* weak bumps needed to chip a dune apart *)
let scorpion_detect = 5    (* manhattan radius that flips Patrol -> Chase *)
let scorpion_escape = 8    (* radius beyond which a chaser gives up *)
let viper_range = 6        (* line-of-sight reach in tiles *)
let oasis_power_moves = 6  (* protected turns, counting the pickup turn *)

(* Real-time pacing (the world no longer waits for you): *)
let scorpion_tick_s = 0.45   (* seconds per scorpion step while calm *)
let scorpion_chase_tick_s = 0.30 (* ...and while chasing *)
let application_tick_s = 1.8 (* seconds per row/column the application eats *)
