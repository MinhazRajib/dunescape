(* DuneScape — main loop.

   Your moves are committed slides (Slide.step), but since the playtest the
   WORLD is real-time: scorpions walk on a wall-clock timer and the finale's
   job application advances on its own clock.  The polling loop (~30fps)
   drives both, plus ambient animation. *)

open Game
open Game.Types

type screen = Title | Level_select | In_level | Victory

let screen = ref Title
let level_idx = ref 0
let cur = ref (Board.parse_exn Levels.all.(0))
let undo_stack : gs list ref = ref []
let palette = ref Palette.day
let frame = ref 0
let msg = ref ""
let msg_danger = ref false
let sel = ref 0
let unlocked_finale = ref false
let cleared = Array.make (Array.length Levels.all) false
let deaths = ref 0
let total_moves = ref 0
let intro_timer = ref 0
let trail : ((int * int) * int) list ref = ref []
let last_scorpion_tick = ref 0.
let last_app_tick = ref 0.

(* previous enemy cells + when they stepped, for the glide animation *)
let enemy_prev : (int * int) list ref = ref []
let enemy_moved_at = ref 0.

let present () = Graphics.synchronize ()

let is_dusk i = Levels.all.(i).voids <> [] || i > Levels.finale_index

let load_level ?(quiet = false) i =
  level_idx := i;
  cur := Board.parse_exn Levels.all.(i);
  undo_stack := [];
  trail := [];
  Fx.clear ();
  palette := (if is_dusk i then Palette.dusk else Palette.day);
  last_scorpion_tick := Unix.gettimeofday ();
  last_app_tick := Unix.gettimeofday ();
  enemy_prev := [];
  enemy_moved_at := 0.;
  if not quiet then begin
    msg := Levels.all.(i).intro;
    msg_danger := false;
    intro_timer := 80
  end

(* ---- frame composition ---- *)

let draw_level_frame ~grid ~enemies ~powerups ~voids ~water ~power_left
    ~moves ~camel_px ~facing () =
  let pal = !palette in
  let ox, oy = Fx.shake_offset () in
  let now = Unix.gettimeofday () in
  (* continuous void edge: progress toward the next consumed line *)
  let void_frac =
    if voids = [] || !intro_timer > 0 then 0.
    else
      let tick = Levels.all.(!level_idx).void_tick_s in
      min 0.999 (max 0. ((now -. !last_app_tick) /. tick))
  in
  (* enemy glide progress since their last step *)
  let enemy_t =
    min 1. (max 0. ((now -. !enemy_moved_at) /. enemy_glide_s))
  in
  Fx.draw_gradient ~x:0 ~y:0 ~w:Render.win_w ~h:Render.board_h pal.sky_bot
    pal.sky_top;
  Render.draw_board pal ~grid ~enemies ~powerups ~voids ~void_frac
    ~trail:!trail ~enemy_prev:!enemy_prev ~enemy_t ~water
    ~threshold:!cur.threshold ~frame:!frame ~camel_px ~facing
    ~is_protected:(power_left > 0) ~ox ~oy;
  Render.draw_hud pal ~name:Levels.all.(!level_idx).name ~water
    ~threshold:!cur.threshold ~moves ~power_left ~msg:!msg
    ~msg_danger:!msg_danger ~frame:!frame

let camel_px_of_cell cell =
  let x, y = Render.px_of_cell cell in
  (float_of_int x, float_of_int y)

let draw_idle () =
  let gs = !cur in
  draw_level_frame ~grid:gs.grid ~enemies:gs.enemies ~powerups:gs.powerups
    ~voids:gs.voids ~water:gs.water ~power_left:gs.power_left ~moves:gs.moves
    ~camel_px:(camel_px_of_cell gs.camel) ~facing:gs.facing ();
  if !intro_timer > 0 then begin
    decr intro_timer;
    if !intro_timer = 0 then begin
      (* the world's clocks start when the banner lifts *)
      last_app_tick := Unix.gettimeofday ();
      last_scorpion_tick := Unix.gettimeofday ()
    end;
    Render.draw_panel ~cx:(Render.win_w / 2) ~cy:(Render.board_h / 2) ~w:680
      ~h:120;
    Font.draw_centered ~scale:3 ~cx:(Render.win_w / 2)
      ~y_top:((Render.board_h / 2) + 42)
      (Palette.color_of !palette.gold)
      Levels.all.(!level_idx).name;
    Font.draw_centered ~scale:2 ~cx:(Render.win_w / 2)
      ~y_top:((Render.board_h / 2) - 14)
      (Palette.color_of !palette.ui)
      Levels.all.(!level_idx).intro
  end

(* Ambient sparkle on the unlocked oasis and any power-ups. *)
let ambient () =
  if !screen = In_level && !frame mod 30 = 0 then begin
    let gs = !cur in
    Array.iteri
      (fun r row ->
        Array.iteri
          (fun c t ->
            if t = Exit && gs.water >= gs.threshold then begin
              let x, y = Render.px_of_cell (r, c) in
              Fx.spawn_rise ~n:2 ~x:(x + 24) ~y:(y + 20)
                (Palette.color_of !palette.gold)
            end)
          row)
      gs.grid;
    List.iter
      (fun cell ->
        let x, y = Render.px_of_cell cell in
        Fx.spawn_rise ~n:1 ~x:(x + 24) ~y:(y + 16)
          (Palette.color_of !palette.gold))
      gs.powerups
  end

(* ---- event replay during the slide animation ---- *)

let event_cell = function
  | Bumped (c, _) | Chipped (c, _) | Rock_sunk c | Broke c | Collected c
  | Got_power c | Sealed c | Crumbled c | Ate_enemy c | Mirage c
  | Exit_locked c ->
    Some c
  | Teleported (a, _) -> Some a
  | Pushed (a, _) -> Some a
  | Died (_, c) -> Some c
  | Level_won | Twist_triggered -> None

let burst_at ?(n = 22) cell color =
  let x, y = Render.px_of_cell cell in
  Fx.spawn ~n ~x:(x + 24) ~y:(y + 24) color

(* Applies one event to the cosmetic render copies; returns updated lists. *)
let apply_event_fx rgrid renemies rpowerups e =
  let pal = !palette in
  match e with
  | Broke (r, c) ->
    rgrid.(r).(c) <- Empty;
    burst_at ~n:34 (r, c) (Palette.color_of pal.dune_dark);
    burst_at ~n:10 (r, c) (Palette.color_of pal.sand);
    Fx.add_shake 7.;
    (renemies, rpowerups)
  | Chipped ((r, c), left) ->
    rgrid.(r).(c) <- Dune left;
    burst_at ~n:10 (r, c) (Palette.color_of pal.dune_dark);
    Fx.add_shake 2.;
    msg :=
      Printf.sprintf "CRACKING! %d MORE HIT%s - OR A 3-TILE RUNWAY." left
        (if left = 1 then "" else "S");
    msg_danger := false;
    (renemies, rpowerups)
  | Collected (r, c) ->
    rgrid.(r).(c) <- Empty;
    burst_at ~n:14 (r, c) (Palette.color_of pal.water);
    (renemies, rpowerups)
  | Got_power (r, c) ->
    burst_at ~n:26 (r, c) (Palette.color_of pal.gold);
    (renemies, List.filter (fun p -> p <> (r, c)) rpowerups)
  | Sealed (r, c) ->
    rgrid.(r).(c) <- Solid;
    burst_at ~n:12 (r, c) (Palette.color_of pal.oneway);
    (renemies, rpowerups)
  | Crumbled (r, c) ->
    rgrid.(r).(c) <- Pit;
    burst_at ~n:12 (r, c) (Palette.color_of pal.pit);
    (renemies, rpowerups)
  | Pushed ((r, c), (r2, c2)) ->
    rgrid.(r).(c) <- Empty;
    if rgrid.(r2).(c2) <> Quicksand then rgrid.(r2).(c2) <- Push_rock;
    burst_at ~n:12 (r2, c2) (Palette.color_of pal.sand_dark);
    Fx.add_shake 3.;
    (renemies, rpowerups)
  | Rock_sunk (r, c) ->
    rgrid.(r).(c) <- Empty;
    burst_at ~n:20 (r, c) (Palette.color_of (Palette.scale pal.sand 0.5));
    msg := "THE ROCK PACKED THE QUICKSAND SOLID.";
    msg_danger := false;
    (renemies, rpowerups)
  | Teleported (a, b) ->
    burst_at ~n:16 a (Palette.color_of pal.water);
    burst_at ~n:16 b (Palette.color_of pal.water);
    (renemies, rpowerups)
  | Ate_enemy cell ->
    burst_at ~n:30 cell (Palette.color_of pal.gold);
    (List.filter (fun e -> e.cell <> cell) renemies, rpowerups)
  | Bumped ((r, c), revealed) ->
    burst_at ~n:6 (r, c) (Palette.color_of pal.sand_dark);
    if revealed then begin
      msg := "IT WON'T EVEN CRACK. THAT ONE'S A LIE.";
      msg_danger := false;
      Fx.add_shake 3.
    end
    else begin
      msg := "THUD. PACKED SAND.";
      msg_danger := false
    end;
    (renemies, rpowerups)
  | _ -> (renemies, rpowerups)

let death_msg = function
  | Pricked -> "THE CACTUS. OF COURSE."
  | Stung -> "THE SCORPION GOT YOU."
  | Gazed -> "THE VIPER'S GAZE IS LETHAL."
  | Voided -> "THE VOID TOOK YOU."
  | Sunk -> "THE QUICKSAND ATE YOU. IT LOOKED SO CALM."

(* Replay [path]/[events] cosmetically, then commit [gs']. *)
let animate pre events path gs' =
  let rgrid = Array.map Array.copy pre.grid in
  let renemies = ref pre.enemies in
  let rpowerups = ref pre.powerups in
  let queue = ref events in
  let facing = gs'.facing in
  let draw_at camel_px =
    incr frame;
    Fx.step ();
    draw_level_frame ~grid:rgrid ~enemies:!renemies ~powerups:!rpowerups
      ~voids:pre.voids ~water:pre.water ~power_left:pre.power_left
      ~moves:pre.moves ~camel_px ~facing ();
    present ();
    Unix.sleepf 0.013
  in
  let arrive cell prev =
    let rec pump () =
      match !queue with
      | e :: rest ->
        (match event_cell e with
         | Some c when c = cell || c = prev ->
           let en, pw = apply_event_fx rgrid !renemies !rpowerups e in
           renemies := en;
           rpowerups := pw;
           queue := rest;
           pump ()
         | None ->
           queue := rest;
           pump ()
         | Some _ -> ())
      | [] -> ()
    in
    pump ()
  in
  (match path with
   | [] | [ _ ] -> ()
   | start :: rest ->
     let prev = ref start in
     List.iter
       (fun cell ->
         let x0, y0 = camel_px_of_cell !prev in
         let x1, y1 = camel_px_of_cell cell in
         let adjacent = manhattan !prev cell = 1 in
         if adjacent then
           for i = 1 to 2 do
             let t = float_of_int i /. 2. in
             draw_at (x0 +. ((x1 -. x0) *. t), y0 +. ((y1 -. y0) *. t))
           done
         else begin
           (* teleport hop: no interpolation across the board *)
           arrive !prev !prev;
           draw_at (x1, y1)
         end;
         arrive cell !prev;
         trail := (!prev, !frame) :: !trail;
         if adjacent && Random.int 2 = 0 then begin
           let x, y = Render.px_of_cell !prev in
           Fx.spawn ~n:2 ~speed:1.2 ~size:2.5 ~x:(x + 24) ~y:(y + 12)
             (Palette.color_of !palette.sand_dark)
         end;
         prev := cell)
       rest;
     let x, y = Render.px_of_cell !prev in
     Fx.spawn ~n:6 ~speed:1.6 ~size:3. ~x:(x + 24) ~y:(y + 10)
       (Palette.color_of !palette.sand_dark));
  (* prune old prints *)
  trail := List.filter (fun (_, stamp) -> !frame - stamp < 150) !trail;
  cur := gs';
  for _ = 1 to 3 do
    incr frame;
    Fx.step ();
    draw_idle ();
    present ();
    Unix.sleepf 0.013
  done

(* ---- sequences ---- *)

let wait_any_key_with ~draw =
  let rec loop () =
    incr frame;
    Fx.step ();
    draw ();
    present ();
    if Graphics.key_pressed () then ignore (Graphics.read_key ())
    else begin
      Unix.sleepf 0.033;
      loop ()
    end
  in
  while Graphics.key_pressed () do
    ignore (Graphics.read_key ())
  done;
  loop ()

let level_complete_overlay () =
  wait_any_key_with ~draw:(fun () ->
      draw_idle ();
      Render.draw_panel ~cx:(Render.win_w / 2) ~cy:(Render.board_h / 2) ~w:560
        ~h:170;
      Font.draw_centered ~scale:4 ~cx:(Render.win_w / 2)
        ~y_top:((Render.board_h / 2) + 66)
        (Palette.color_of !palette.gold)
        "LEVEL COMPLETE!";
      Font.draw_centered ~scale:2 ~cx:(Render.win_w / 2)
        ~y_top:((Render.board_h / 2) + 4)
        (Palette.color_of !palette.ui)
        (if !cur.threshold > 0 then
           Printf.sprintf "MOVES %d   WATER %d/%d" !cur.moves !cur.water
             !cur.threshold
         else Printf.sprintf "MOVES %d" !cur.moves);
      if !frame / 12 mod 2 = 0 then
        Font.draw_centered ~scale:2 ~cx:(Render.win_w / 2)
          ~y_top:((Render.board_h / 2) - 44)
          (Palette.color_of !palette.sand)
          "PRESS ANY KEY")

let death_sequence reason cell =
  let pal = !palette in
  incr deaths;
  burst_at ~n:46 cell (Palette.color_of pal.danger);
  burst_at ~n:20 cell (Palette.color_of pal.camel);
  Fx.add_shake 13.;
  for i = 0 to 1 do
    incr frame;
    Fx.step ();
    draw_idle ();
    if i = 0 then begin
      Graphics.set_color (Palette.color_of pal.danger);
      Graphics.fill_rect 0 0 Render.win_w Render.board_h
    end;
    present ();
    Unix.sleepf 0.04
  done;
  for _ = 1 to 16 do
    incr frame;
    Fx.step ();
    draw_idle ();
    present ();
    Unix.sleepf 0.028
  done;
  load_level ~quiet:true !level_idx;
  msg := death_msg reason;
  msg_danger := true

let typewriter ~scale ~cx ~y_top color text =
  let n = String.length text in
  for i = 1 to n do
    incr frame;
    Graphics.set_color Graphics.black;
    Graphics.fill_rect 0 0 Render.win_w Render.win_h;
    Font.draw_centered ~scale ~cx ~y_top color (String.sub text 0 i);
    present ();
    Unix.sleepf 0.05
  done;
  Unix.sleepf 1.2

let twist_sequence () =
  Unix.sleepf 1.0;
  for _ = 1 to 22 do
    incr frame;
    Fx.glitch_frame ~w:Render.win_w ~h:Render.win_h;
    present ();
    Unix.sleepf 0.055
  done;
  typewriter ~scale:3 ~cx:(Render.win_w / 2) ~y_top:((Render.win_h / 2) + 40)
    (Graphics.rgb 255 60 60) "THE DESERT ISN'T DONE WITH YOU...";
  unlocked_finale := true;
  load_level Levels.finale_index

(* Fast descent between void depths. *)
let page_transition next =
  Graphics.set_color Graphics.black;
  Graphics.fill_rect 0 0 Render.win_w Render.win_h;
  Font.draw_centered ~scale:4 ~cx:(Render.win_w / 2)
    ~y_top:((Render.win_h / 2) + 30)
    (Graphics.rgb 255 0 80) "DEEPER.";
  present ();
  Unix.sleepf 0.8;
  load_level next

(* ---- turns ---- *)

let do_turn dir =
  (* acting dismisses the level-name banner for good *)
  if !intro_timer > 0 then begin
    intro_timer := 0;
    last_app_tick := Unix.gettimeofday ();
    last_scorpion_tick := Unix.gettimeofday ()
  end;
  let pre = !cur in
  let gs', events, path = Slide.step pre dir in
  if List.length path <= 1 then begin
    (* a bump: maybe a chip — commit the grid, play feedback *)
    if events <> [] then begin
      undo_stack :=
        pre :: (if List.length !undo_stack > 400 then [] else !undo_stack);
      let scratch_enemies, scratch_powerups = (gs'.enemies, gs'.powerups) in
      List.iter
        (fun e ->
          ignore
            (apply_event_fx gs'.grid scratch_enemies scratch_powerups e))
        events
    end;
    cur := gs'
  end
  else begin
    msg := "";
    msg_danger := false;
    undo_stack :=
      pre :: (if List.length !undo_stack > 400 then [] else !undo_stack);
    animate pre events path gs';
    List.iter
      (fun e ->
        match e with
        | Mirage _ ->
          msg := "...JUST A MIRAGE.";
          msg_danger := true;
          Fx.add_shake 4.
        | Exit_locked _ ->
          msg := "THE OASIS SHIMMERS. COLLECT ALL THE WATER.";
          msg_danger := false
        | _ -> ())
      events;
    match gs'.status with
    | Dead reason ->
      undo_stack := [];
      death_sequence reason gs'.camel
    | Won -> begin
      cleared.(!level_idx) <- true;
      total_moves := !total_moves + gs'.moves;
      burst_at ~n:40 gs'.camel (Palette.color_of !palette.gold);
      let spec = Levels.all.(!level_idx) in
      match spec.next with
      | Some n when spec.voids <> [] -> page_transition n
      | Some n ->
        level_complete_overlay ();
        load_level n
      | None ->
        if spec.voids <> [] then begin
          (* the center of the map: it's over *)
          for _ = 1 to 20 do
            incr frame;
            Fx.step ();
            draw_idle ();
            present ();
            Unix.sleepf 0.03
          done;
          screen := Victory
        end
        else begin
          level_complete_overlay ();
          screen := Level_select
        end
    end
    | Twisted ->
      cleared.(!level_idx) <- true;
      total_moves := !total_moves + gs'.moves;
      twist_sequence ()
    | Alive ->
      if not (Slide.has_any_move gs') then begin
        msg := "STRANDED... PRESS R";
        msg_danger := true
      end
  end

(* ---- real-time world ---- *)

let world_tick () =
  if !screen = In_level && !cur.status = Alive && !intro_timer = 0 then begin
    let now = Unix.gettimeofday () in
    (* scorpions walk on their own clock, faster when hunting *)
    let pace =
      if Slide.is_any_scorpion_chasing !cur then scorpion_chase_tick_s
      else scorpion_tick_s
    in
    if now -. !last_scorpion_tick >= pace then begin
      last_scorpion_tick := now;
      enemy_prev := List.map (fun e -> e.cell) !cur.enemies;
      enemy_moved_at := now;
      let gs', events = Slide.tick_scorpions !cur in
      cur := gs';
      List.iter
        (fun e ->
          match e with
          | Ate_enemy cell ->
            burst_at ~n:30 cell (Palette.color_of !palette.gold)
          | Died (reason, cell) ->
            burst_at ~n:20 cell (Palette.color_of !palette.danger);
            death_sequence reason cell
          | _ -> ())
        events
    end;
    (* the void swallows its next line *)
    if !cur.status = Alive && !cur.voids <> []
       && now -. !last_app_tick >= Levels.all.(!level_idx).void_tick_s
    then begin
      last_app_tick := now;
      let gs', events = Slide.tick_void !cur in
      cur := gs';
      Fx.add_shake 3.;
      List.iter
        (fun e ->
          match e with
          | Died (reason, cell) ->
            burst_at ~n:24 cell (Palette.color_of !palette.danger);
            death_sequence reason cell
          | _ -> ())
        events
    end
  end

(* ---- input ---- *)

let quit () =
  Graphics.close_graph ();
  exit 0

let handle_key ch =
  let ch = Char.lowercase_ascii ch in
  match !screen with
  | Title -> (
    match ch with
    | '\r' | '\n' ->
      sel := 0;
      screen := Level_select
    | '\027' | 'q' -> quit ()
    | _ -> ())
  | Level_select -> (
    let max_sel =
      if !unlocked_finale then Levels.card_count - 1
      else Levels.card_count - 2
    in
    match ch with
    | 'a' -> sel := max 0 (!sel - 1)
    | 'd' -> sel := min max_sel (!sel + 1)
    | '\r' | '\n' ->
      load_level !sel;
      screen := In_level
    | '\027' -> screen := Title
    | _ -> ())
  | In_level -> (
    match ch with
    | 'w' -> do_turn Up
    | 's' -> do_turn Down
    | 'a' -> do_turn Left
    | 'd' -> do_turn Right
    | 'z' | 'u' -> (
      match !undo_stack with
      | prev :: rest ->
        cur := prev;
        undo_stack := rest;
        msg := "";
        msg_danger := false
      | [] -> ())
    | 'r' ->
      load_level ~quiet:true !level_idx;
      msg := "FRESH EYES.";
      msg_danger := false
    | '\027' -> screen := Level_select
    | _ -> ())
  | Victory -> (
    match ch with
    | '\r' | '\n' | '\027' -> screen := Title
    | _ -> ())

(* ---- main ---- *)

let () =
  Random.self_init ();
  Graphics.open_graph " 960x720";
  Graphics.set_window_title "DuneScape";
  Graphics.auto_synchronize false;
  (* debug/demo: jump straight into a level, e.g. `main.exe --level 3` *)
  (match Sys.argv with
   | [| _; "--level"; n |] ->
     let n = int_of_string n in
     unlocked_finale := true;
     load_level n;
     screen := In_level
   | _ -> ());
  (try
     while true do
       incr frame;
       Fx.step ();
       ambient ();
       world_tick ();
       (match !screen with
        | Title -> Render.draw_title Palette.day ~frame:!frame
        | Level_select ->
          Render.draw_level_select Palette.day ~frame:!frame ~sel:!sel
            ~unlocked_void:!unlocked_finale ~cleared
        | In_level -> draw_idle ()
        | Victory ->
          Render.draw_victory Palette.dusk ~frame:!frame
            ~total_moves:!total_moves ~deaths:!deaths);
       present ();
       while Graphics.key_pressed () do
         handle_key (Graphics.read_key ())
       done;
       Unix.sleepf 0.033
     done
   with
  | Graphics.Graphic_failure _ -> ()
  | Exit -> ());
  quit ()
