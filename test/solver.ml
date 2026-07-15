(* BFS solver / level validator for DuneScape.

   Because [Slide.step] is a pure function over an immutable state, we can
   exhaustively search the reachable state space of every level:

     solver.exe            solve all levels, print shortest solutions
     solver.exe N          solve level N (0-based)
     solver.exe N --trace  solve level N and replay the solution as ASCII
     solver.exe --check    validate + solve everything; exit 1 on failure
                           (wired to `dune runtest`)

   Success for a twist level (level 3) is reaching [Twisted]; for the others
   it is [Won]. *)

open Game
open Types

let dir_char = function Up -> 'U' | Down -> 'D' | Left -> 'L' | Right -> 'R'

(* State fingerprint: everything that affects future evolution.  [moves] and
   [facing] are excluded (cosmetic); enemy routes are static per level so we
   fingerprint only (cell, st, ri). *)
let key gs =
  Marshal.to_string
    ( gs.grid, gs.camel, gs.water, gs.power_left, gs.powerups, gs.void_col,
      List.map (fun e -> (e.cell, e.st, e.ri)) gs.enemies )
    []

type result = {
  solvable : bool;
  solution : dir list; (* shortest, if solvable *)
  explored : int;
  stranded_states : int; (* reachable alive states with no legal move *)
}

let solve ?(max_states = 2_000_000) spec =
  let initial = Board.parse_exn spec in
  let success gs =
    match gs.status with
    | Won -> not spec.twist
    | Twisted -> spec.twist
    | _ -> false
  in
  let seen = Hashtbl.create 4096 in
  let parent = Hashtbl.create 4096 in
  let q = Queue.create () in
  let k0 = key initial in
  Hashtbl.replace seen k0 ();
  Queue.push (initial, k0) q;
  let explored = ref 0 in
  let stranded = ref 0 in
  let goal = ref None in
  (try
     while not (Queue.is_empty q) do
       let gs, k = Queue.pop q in
       incr explored;
       if !explored > max_states then raise Exit;
       let moved_any = ref false in
       List.iter
         (fun d ->
           if !goal = None then begin
             let gs', _, path = Slide.step gs d in
             if List.length path > 1 then begin
               moved_any := true;
               if success gs' then begin
                 let k' = key gs' in
                 Hashtbl.replace parent k' (k, d);
                 goal := Some k'
               end
               else if gs'.status = Alive then begin
                 let k' = key gs' in
                 if not (Hashtbl.mem seen k') then begin
                   Hashtbl.replace seen k' ();
                   Hashtbl.replace parent k' (k, d);
                   Queue.push (gs', k') q
                 end
               end
             end
           end)
         [ Up; Down; Left; Right ];
       if not !moved_any then incr stranded;
       if !goal <> None then raise Exit
     done
   with Exit -> ());
  let solution =
    match !goal with
    | None -> []
    | Some k ->
      let rec back k acc =
        match Hashtbl.find_opt parent k with
        | None -> acc
        | Some (pk, d) -> back pk (d :: acc)
      in
      back k []
  in
  { solvable = !goal <> None; solution; explored = !explored;
    stranded_states = !stranded }

let solution_string sol =
  String.concat "" (List.map (fun d -> String.make 1 (dir_char d)) sol)

let replay spec sol =
  let gs = ref (Board.parse_exn spec) in
  Printf.printf "-- start --\n%s\n" (Board.to_ascii !gs);
  List.iteri
    (fun i d ->
      let gs', events, _ = Slide.step !gs d in
      gs := gs';
      Printf.printf "-- move %d: %c  (water %d/%d, power %d)\n" (i + 1)
        (dir_char d) gs'.water gs'.threshold gs'.power_left;
      List.iter
        (fun e ->
          let s =
            match e with
            | Bumped ((r, c), fake) ->
              Printf.sprintf "bumped(%d,%d)%s" r c (if fake then " FAKE!" else "")
            | Broke (r, c) -> Printf.sprintf "broke(%d,%d)" r c
            | Collected (r, c) -> Printf.sprintf "water(%d,%d)" r c
            | Got_power (r, c) -> Printf.sprintf "POWER(%d,%d)" r c
            | Teleported ((a, b), (x, y)) ->
              Printf.sprintf "warp(%d,%d)->(%d,%d)" a b x y
            | Sealed (r, c) -> Printf.sprintf "sealed(%d,%d)" r c
            | Crumbled (r, c) -> Printf.sprintf "crumbled(%d,%d)" r c
            | Pushed ((a, b), (x, y)) ->
              Printf.sprintf "pushed(%d,%d)->(%d,%d)" a b x y
            | Ate_enemy (r, c) -> Printf.sprintf "ATE(%d,%d)" r c
            | Mirage (r, c) -> Printf.sprintf "MIRAGE(%d,%d)" r c
            | Exit_locked (r, c) -> Printf.sprintf "locked(%d,%d)" r c
            | Died (_, (r, c)) -> Printf.sprintf "DIED(%d,%d)" r c
            | Level_won -> "WON"
            | Twist_triggered -> "TWIST"
          in
          Printf.printf "   %s\n" s)
        events;
      Printf.printf "%s\n" (Board.to_ascii !gs))
    sol

let report ?(trace = false) i =
  let spec = Levels.all.(i) in
  let res = solve spec in
  Printf.printf "level %d %-18s : %s" i spec.name
    (if res.solvable then
       Printf.sprintf "solvable in %d moves  [%s]  (states %d, stranded %d)\n"
         (List.length res.solution)
         (solution_string res.solution)
         res.explored res.stranded_states
     else
       Printf.sprintf "UNSOLVABLE  (states %d, stranded %d)\n" res.explored
         res.stranded_states);
  if trace && res.solvable then replay spec res.solution;
  res.solvable

let dirs_of_string s =
  List.filter_map
    (function
      | 'U' | 'u' -> Some Up
      | 'D' | 'd' -> Some Down
      | 'L' | 'l' -> Some Left
      | 'R' | 'r' -> Some Right
      | _ -> None)
    (List.init (String.length s) (String.get s))

let () =
  let args = Array.to_list Sys.argv in
  match args with
  | [ _ ] | [ _; "--check" ] ->
    let ok = ref true in
    Array.iteri (fun i _ -> if not (report i) then ok := false) Levels.all;
    if not !ok then exit 1
  | [ _; n; "--play"; moves ] ->
    (* replay an arbitrary move string with a full trace *)
    replay Levels.all.(int_of_string n) (dirs_of_string moves)
  | _ :: n :: rest ->
    let trace = List.mem "--trace" rest in
    ignore (report ~trace (int_of_string n))
  | [] -> assert false
