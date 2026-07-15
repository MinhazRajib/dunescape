(* Board parsing and validation: turns a [Levels.spec] into an initial game
   state, failing loudly (with coordinates) on malformed boards. *)

open Types

let tile_of_char_exn ~pos = function
  | '#' -> Solid
  | '.' -> Empty
  | '~' -> Dune dune_hp
  | '%' -> Fake_dune 0
  | 'o' -> Water
  | 'X' -> Cactus
  | '1' .. '4' as ch -> Teleport (Char.code ch - Char.code '0')
  | '>' -> One_way Right
  | '<' -> One_way Left
  | '^' -> One_way Up
  | 'v' -> One_way Down
  | ':' -> Crumble
  | 'q' -> Quicksand
  | 'O' -> Push_rock
  | '?' -> False_exit
  | 'E' -> Exit
  | 'S' | 's' | 'V' | 'P' -> Empty (* entities stand on sand *)
  | ch ->
    let r, c = pos in
    failwith (Printf.sprintf "bad char %C at row %d col %d" ch r c)

let sign_of_int x = compare x 0

(* Straight back-and-forth patrol cycle between [a] and [b] (inclusive):
   a..b then back to one short of a, e.g. a b-line of 4 cells cycles 6. *)
let patrol_route_exn (ar, ac) (br, bc) =
  if ar <> br && ac <> bc then
    failwith
      (Printf.sprintf "patrol (%d,%d)-(%d,%d) is not a straight line" ar ac br
         bc);
  let cells =
    if ar = br then
      let s = sign_of_int (bc - ac) in
      List.init (abs (bc - ac) + 1) (fun i -> (ar, ac + (i * s)))
    else
      let s = sign_of_int (br - ar) in
      List.init (abs (br - ar) + 1) (fun i -> (ar + (i * s), ac))
  in
  match cells with
  | [] | [ _ ] -> failwith "patrol too short"
  | _ ->
    let there = cells in
    let back = List.tl (List.rev (List.tl cells)) in
    Array.of_list (there @ back)

let parse_exn (spec : Levels.spec) =
  if Array.length spec.ascii <> rows then
    failwith
      (Printf.sprintf "%s: expected %d rows, got %d" spec.name rows
         (Array.length spec.ascii));
  Array.iteri
    (fun r line ->
      if String.length line <> cols then
        failwith
          (Printf.sprintf "%s: row %d has %d chars, expected %d" spec.name r
             (String.length line) cols))
    spec.ascii;
  let grid = Array.make_matrix rows cols Empty in
  let spawn = ref None in
  let exits = ref 0 in
  let scorpions = ref [] in
  let vipers = ref [] in
  let powerups = ref [] in
  let teleports = Hashtbl.create 4 in
  for r = 0 to rows - 1 do
    for c = 0 to cols - 1 do
      let ch = spec.ascii.(r).[c] in
      (match ch with
       | 'S' ->
         if !spawn <> None then failwith (spec.name ^ ": two spawns");
         spawn := Some (r, c)
       | 's' -> scorpions := (r, c) :: !scorpions
       | 'V' -> vipers := (r, c) :: !vipers
       | 'P' -> powerups := (r, c) :: !powerups
       | 'E' -> incr exits
       | '1' .. '4' ->
         let id = Char.code ch - Char.code '0' in
         Hashtbl.replace teleports id
           (1 + try Hashtbl.find teleports id with Not_found -> 0)
       | _ -> ());
      grid.(r).(c) <- tile_of_char_exn ~pos:(r, c) ch
    done
  done;
  if !exits <> 1 then
    failwith (Printf.sprintf "%s: %d exits, expected 1" spec.name !exits);
  Hashtbl.iter
    (fun id n ->
      if n <> 2 then
        failwith
          (Printf.sprintf "%s: teleport %d appears %d times, expected 2"
             spec.name id n))
    teleports;
  let spawn =
    match !spawn with
    | Some s -> s
    | None -> failwith (spec.name ^ ": no spawn")
  in
  let enemies =
    List.map
      (fun cell ->
        match List.assoc_opt cell spec.patrols with
        | None ->
          failwith
            (Printf.sprintf "%s: scorpion at (%d,%d) has no patrol" spec.name
               (fst cell) (snd cell))
        | Some far ->
          { kind = Scorpion; cell; st = Patrol;
            route = patrol_route_exn cell far; ri = 0 })
      !scorpions
    @ List.map
        (fun cell -> { kind = Viper; cell; st = Patrol; route = [||]; ri = 0 })
        !vipers
  in
  (* Playtest rule: the oasis unlocks only when EVERY drop is collected. *)
  let total_water =
    Array.fold_left
      (fun acc row ->
        Array.fold_left (fun a t -> if t = Water then a + 1 else a) acc row)
      0 grid
  in
  ignore spec.threshold;
  let voids =
    List.map
      (fun side ->
        match side with
        | Left -> (Left, 0)
        | Right -> (Right, cols - 1)
        | Up -> (Up, 0)
        | Down -> (Down, rows - 1))
      spec.voids
  in
  { grid; camel = spawn; facing = Right; water = 0;
    threshold = total_water; moves = 0; enemies; powerups = !powerups;
    power_left = 0; voids; twist = spec.twist; status = Alive }

(* ASCII snapshot of a live state — the solver's trace output. *)
let to_ascii gs =
  let buf = Buffer.create 512 in
  for r = 0 to rows - 1 do
    for c = 0 to cols - 1 do
      let ch =
        if gs.camel = (r, c) then '@'
        else if is_voided gs.voids (r, c) then '&'
        else
          match List.find_opt (fun e -> e.cell = (r, c)) gs.enemies with
          | Some { kind = Scorpion; st = Chase; _ } -> '!'
          | Some { kind = Scorpion; _ } -> 's'
          | Some { kind = Viper; _ } -> 'V'
          | None ->
            if List.mem (r, c) gs.powerups then 'P'
            else (
              match gs.grid.(r).(c) with
              | Empty -> '.'
              | Solid -> '#'
              | Dune _ -> '~'
              | Fake_dune _ -> '%'
              | Water -> 'o'
              | Cactus -> 'X'
              | Teleport id -> Char.chr (Char.code '0' + id)
              | One_way Right -> '>'
              | One_way Left -> '<'
              | One_way Up -> '^'
              | One_way Down -> 'v'
              | Crumble -> ':'
              | Quicksand -> 'q'
              | Pit -> '_'
              | Push_rock -> 'O'
              | False_exit -> '?'
              | Exit -> 'E')
      in
      Buffer.add_char buf ch
    done;
    Buffer.add_char buf '\n'
  done;
  Buffer.contents buf
