(* The slide resolver — the heart of DuneScape (README sections 5, 6, 17).

   [step gs dir] resolves one full turn:
     1. the camel slides until something stops it (resolving breaks, pickups,
        teleports, one-way doors, pushes and deaths along the way);
     2. if the camel actually moved, the world ticks: enemies each step once,
        then the void (if active) advances one column.

   Design decisions (all deliberate, tuned for puzzle design):
   - Runway RESETS to 0 after breaking a dune: momentum is spent, so a pair of
     back-to-back dunes is an unbreakable barrier unless there is a gap.
   - Teleports preserve runway (portals conserve momentum).
   - A one-way door can only be ENTERED while moving in its arrow direction,
     and it seals (becomes Solid) when the camel LEAVES its cell.
   - Crumble tiles become Pit when the camel LEAVES them, so you may rest on
     one safely for a turn.
   - Water / Exit / False_exit are pass-through: you win only by STOPPING on
     the unlocked exit (the overshoot mechanic).
   - Pushing a rock spends all momentum: the rock slides to its own stopper
     and the camel stops in the rock's original cell.
   - Viper line-of-sight is computed against the LIVE grid, so breaking a dune
     mid-slide can expose you to a gaze on that very slide.
   - A press that moves the camel zero tiles (a bump) does NOT advance the
     world: no enemy steps, no void advance, no move counted.  Waiting is not
     a resource; timing gates must be solved by routing. *)

open Types

exception Died_mid_slide of death_reason * (int * int)

let is_opaque = function
  | Empty | Water | Crumble | Pit -> false
  | _ -> true

(* All cells strictly between [a] and [b] (same row or column) see-through. *)
let is_clear_between grid (r1, c1) (r2, c2) =
  if r1 = r2 then begin
    let lo = min c1 c2 + 1 and hi = max c1 c2 - 1 in
    let clear = ref true in
    for c = lo to hi do
      if is_opaque grid.(r1).(c) then clear := false
    done;
    !clear
  end
  else begin
    let lo = min r1 r2 + 1 and hi = max r1 r2 - 1 in
    let clear = ref true in
    for r = lo to hi do
      if is_opaque grid.(r).(c1) then clear := false
    done;
    !clear
  end

let is_in_viper_los grid enemies (r, c) =
  List.exists
    (fun e ->
      e.kind = Viper
      &&
      let vr, vc = e.cell in
      (r, c) <> (vr, vc)
      && ((r = vr && abs (c - vc) <= viper_range)
          || (c = vc && abs (r - vr) <= viper_range))
      && is_clear_between grid (vr, vc) (r, c))
    enemies

(* Every cell currently watched by a viper; used by the renderer to paint the
   lethal sightlines so the player can read them. *)
let viper_los_cells grid enemies =
  let cells = ref [] in
  List.iter
    (fun e ->
      if e.kind = Viper then
        List.iter
          (fun d ->
            let dr, dc = delta d in
            let rec go (r, c) n =
              let r', c' = r + dr, c + dc in
              if n <= viper_range && is_in_bounds r' c'
                 && not (is_opaque grid.(r').(c'))
              then begin
                cells := (r', c') :: !cells;
                go (r', c') (n + 1)
              end
            in
            go e.cell 1)
          [ Up; Down; Left; Right ])
    enemies;
  !cells

(* ---- Enemy movement (one step per player move) ---- *)

let is_enemy_walkable grid occupied (r, c) =
  is_in_bounds r c
  && (match grid.(r).(c) with Empty | Water | Crumble -> true | _ -> false)
  && not (List.mem (r, c) occupied)

let sign x = compare x 0

(* One greedy step from [cell] toward [target]: try the axis with the larger
   gap first, fall back to the other; stay put if both are blocked. *)
let step_toward grid occupied cell target =
  let r, c = cell and tr, tc = target in
  let dr = sign (tr - r) and dc = sign (tc - c) in
  let cands =
    if abs (tr - r) >= abs (tc - c) then [ (r + dr, c); (r, c + dc) ]
    else [ (r, c + dc); (r + dr, c) ]
  in
  let cands = List.filter (fun cell' -> cell' <> cell) cands in
  match List.find_opt (is_enemy_walkable grid occupied) cands with
  | Some cell' -> cell'
  | None -> cell

(* One step that maximises distance from [target] (used while fleeing). *)
let step_away grid occupied cell target =
  let r, c = cell in
  let options =
    [ (r - 1, c); (r + 1, c); (r, c - 1); (r, c + 1) ]
    |> List.filter (is_enemy_walkable grid occupied)
    |> List.sort (fun a b ->
           compare (manhattan b target) (manhattan a target))
  in
  match options with
  | best :: _ when manhattan best target > manhattan cell target -> best
  | _ -> cell

let step_scorpion grid occupied camel ~is_protected e =
  if is_protected then { e with cell = step_away grid occupied e.cell camel }
  else
    let dist = manhattan e.cell camel in
    let chasing =
      match e.st with
      | Patrol -> dist <= scorpion_detect
      | Chase -> dist <= scorpion_escape
    in
    if chasing then
      { e with cell = step_toward grid occupied e.cell camel; st = Chase }
    else if Array.length e.route = 0 then { e with st = Patrol }
    else if e.cell = e.route.(e.ri) then begin
      (* On-route: advance to the next waypoint of the cycle. *)
      let ri = (e.ri + 1) mod Array.length e.route in
      let dest = e.route.(ri) in
      if is_enemy_walkable grid occupied dest then
        { e with cell = dest; ri; st = Patrol }
      else { e with st = Patrol }
    end
    else
      (* Off-route (was chasing): walk back to the patrol. *)
      { e with cell = step_toward grid occupied e.cell e.route.(e.ri);
               st = Patrol }

let step_enemies grid enemies camel ~is_protected =
  let rec go moved = function
    | [] -> List.rev moved
    | e :: rest ->
      let occupied =
        List.map (fun x -> x.cell) moved @ List.map (fun x -> x.cell) rest
      in
      let e' =
        match e.kind with
        | Viper -> e
        | Scorpion -> step_scorpion grid occupied camel ~is_protected e
      in
      go (e' :: moved) rest
  in
  go [] enemies

(* ---- The resolver ---- *)

let find_teleport_pair grid id origin =
  let found = ref None in
  Array.iteri
    (fun r row ->
      Array.iteri
        (fun c t ->
          if t = Teleport id && (r, c) <> origin then found := Some (r, c))
        row)
    grid;
  !found

(* [step gs dir] -> (new state, events in order, path of cells traversed).
   The path always starts with the camel's cell; length 1 means no movement. *)
let step gs dir =
  if gs.status <> Alive then (gs, [], [ gs.camel ])
  else begin
    let grid = Array.map Array.copy gs.grid in
    let events = ref [] in
    let emit e = events := e :: !events in
    let enemies = ref gs.enemies in
    let powerups = ref gs.powerups in
    let water = ref gs.water in
    let has_power = ref (gs.power_left > 0) in
    let picked_power = ref false in
    let dr, dc = delta dir in
    let path = ref [ gs.camel ] in

    (* Leaving a cell mid-slide: crumbles collapse, one-ways seal. *)
    let on_leave (r, c) =
      match grid.(r).(c) with
      | Crumble ->
        grid.(r).(c) <- Pit;
        emit (Crumbled (r, c))
      | One_way _ ->
        grid.(r).(c) <- Solid;
        emit (Sealed (r, c))
      | _ -> ()
    in

    (* Entering a cell: hazards first, then pickups. *)
    let enter_cell (r, c) =
      path := (r, c) :: !path;
      if gs.void_col >= 0 && c <= gs.void_col then
        raise (Died_mid_slide (Voided, (r, c)));
      (match List.find_opt (fun e -> e.cell = (r, c)) !enemies with
       | Some e ->
         if !has_power then begin
           enemies := List.filter (fun e' -> not (e' == e)) !enemies;
           emit (Ate_enemy (r, c))
         end
         else
           raise (Died_mid_slide (Stung, (r, c)))
       | None -> ());
      if (not !has_power) && is_in_viper_los grid !enemies (r, c) then
        raise (Died_mid_slide (Gazed, (r, c)));
      (match grid.(r).(c) with
       | Water ->
         grid.(r).(c) <- Empty;
         incr water;
         emit (Collected (r, c))
       | _ -> ());
      if List.mem (r, c) !powerups then begin
        powerups := List.filter (fun p -> p <> (r, c)) !powerups;
        has_power := true;
        picked_power := true;
        emit (Got_power (r, c))
      end
    in

    let rec walk (r, c) runway steps =
      if steps > 300 then (r, c) (* teleport-loop guard *)
      else
        let nr, nc = r + dr, c + dc in
        if not (is_in_bounds nr nc) then (r, c)
        else
          match grid.(nr).(nc) with
          | Solid | Pit -> (r, c)
          | One_way d when d <> dir -> (r, c)
          | Fake_dune ->
            (* The tell: only players who EARNED the break see it refuse. *)
            emit (Bumped ((nr, nc), runway >= break_runway));
            (r, c)
          | Dune when runway < break_runway ->
            emit (Bumped ((nr, nc), false));
            (r, c)
          | Dune ->
            grid.(nr).(nc) <- Empty;
            emit (Broke (nr, nc));
            on_leave (r, c);
            enter_cell (nr, nc);
            walk (nr, nc) 0 (steps + 1) (* breaking spends momentum *)
          | Cactus ->
            path := (nr, nc) :: !path;
            raise (Died_mid_slide (Pricked, (nr, nc)))
          | Push_rock ->
            let rec roll (rr, rc) =
              let r2, c2 = rr + dr, rc + dc in
              if is_in_bounds r2 c2
                 && (match grid.(r2).(c2) with
                     | Empty | Water | Crumble -> true
                     | _ -> false)
                 && not (List.exists (fun e -> e.cell = (r2, c2)) !enemies)
                 && not (gs.void_col >= 0 && c2 <= gs.void_col)
              then roll (r2, c2)
              else (rr, rc)
            in
            let dest = roll (nr, nc) in
            if dest = (nr, nc) then (r, c) (* rock can't budge: a wall *)
            else begin
              grid.(nr).(nc) <- Empty;
              (let r2, c2 = dest in
               grid.(r2).(c2) <- Push_rock);
              emit (Pushed ((nr, nc), dest));
              on_leave (r, c);
              enter_cell (nr, nc);
              (nr, nc) (* momentum spent shoving *)
            end
          | Teleport id -> begin
            on_leave (r, c);
            enter_cell (nr, nc);
            match find_teleport_pair grid id (nr, nc) with
            | Some (pr, pc) ->
              emit (Teleported ((nr, nc), (pr, pc)));
              enter_cell (pr, pc);
              walk (pr, pc) (runway + 1) (steps + 1)
            | None -> walk (nr, nc) (runway + 1) (steps + 1)
          end
          | Empty | Water | Crumble | One_way _ | False_exit | Exit ->
            on_leave (r, c);
            enter_cell (nr, nc);
            walk (nr, nc) (runway + 1) (steps + 1)
    in

    let outcome =
      try Ok (walk gs.camel 0 0)
      with Died_mid_slide (reason, cell) -> Error (reason, cell)
    in
    let finish_events () = List.rev !events in
    let path_list () = List.rev !path in
    match outcome with
    | Error (reason, cell) ->
      emit (Died (reason, cell));
      ( { gs with status = Dead reason; camel = cell; facing = dir },
        finish_events (), path_list () )
    | Ok final ->
      if final = gs.camel then
        (* A bump: feedback only, the world does not tick. *)
        ({ gs with facing = dir }, finish_events (), path_list ())
      else begin
        (* Stop-cell resolution. *)
        let fr, fc = final in
        let won = ref false and twisted = ref false in
        (match grid.(fr).(fc) with
         | Exit ->
           if !water >= gs.threshold then
             if gs.twist then begin
               twisted := true;
               emit Twist_triggered
             end
             else begin
               won := true;
               emit Level_won
             end
           else emit (Exit_locked final)
         | False_exit -> emit (Mirage final)
         | _ -> ());
        let base =
          { gs with grid; camel = final; facing = dir; water = !water;
                    enemies = !enemies; powerups = !powerups;
                    moves = gs.moves + 1 }
        in
        if !won then ({ base with status = Won }, finish_events (), path_list ())
        else if !twisted then
          ({ base with status = Twisted }, finish_events (), path_list ())
        else begin
          (* World tick: enemies step... *)
          let is_protected = !has_power in
          let enemies' = step_enemies grid !enemies final ~is_protected in
          let touching, clear =
            List.partition (fun e -> e.cell = final) enemies'
          in
          let died = ref None in
          let enemies' =
            if touching = [] then enemies'
            else if is_protected then begin
              List.iter (fun e -> emit (Ate_enemy e.cell)) touching;
              clear
            end
            else begin
              died := Some Stung;
              enemies'
            end
          in
          if !died = None && (not is_protected)
             && is_in_viper_los grid enemies' final
          then died := Some Gazed;
          (* ...then the void advances. *)
          let void_col =
            if gs.void_col >= 0 then gs.void_col + void_step_per_move
            else gs.void_col
          in
          let enemies' =
            if void_col >= 0 then
              List.filter (fun e -> snd e.cell > void_col) enemies'
            else enemies'
          in
          if !died = None && void_col >= 0 && fc <= void_col then
            died := Some Voided;
          let power_left =
            let p = if !picked_power then oasis_power_moves else gs.power_left in
            max 0 (p - 1)
          in
          match !died with
          | Some reason ->
            emit (Died (reason, final));
            ( { base with enemies = enemies'; void_col; power_left;
                          status = Dead reason },
              finish_events (), path_list () )
          | None ->
            ( { base with enemies = enemies'; void_col; power_left },
              finish_events (), path_list () )
        end
      end
  end

(* True if some direction actually moves the camel (used for the
   "STRANDED — press R" hint). *)
let has_any_move gs =
  List.exists
    (fun d ->
      let _, _, path = step gs d in
      List.length path > 1)
    [ Up; Down; Left; Right ]
