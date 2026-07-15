(* All drawing: tiles, entities, HUD, and the three full screens.
   Coordinates: Graphics origin is bottom-left; cell (r,c) with r=0 the TOP
   row maps to pixel column c*48 and pixel row (rows-1-r)*48.  The board is
   960x624; the HUD strip is the top 96px. *)

open Game
open Game.Types

let tile = 48
let win_w = 960
let win_h = 720
let board_h = rows * tile (* 624 *)

let px_of_cell ?(ox = 0) ?(oy = 0) (r, c) =
  (c * tile + ox, (rows - 1 - r) * tile + oy)

(* Deterministic per-cell noise for sand speckles. *)
let cell_hash r c = ((r * 92821) + (c * 68917) + 12345) land 0xFFFF

let gray l = Graphics.rgb l l l

(* ---- sprite color maps ---- *)

let camel_colors (pal : Palette.t) = function
  | 'T' -> Some (Palette.color_of pal.camel)
  | 'D' | 'M' -> Some (Palette.color_of pal.camel_dark)
  | 'E' -> Some (Graphics.rgb 25 15 8)
  | 'R' -> Some (Graphics.rgb 186 70 70)
  | _ -> None

let scorpion_colors (pal : Palette.t) ~alert = function
  | 'B' | 'T' ->
    Some (Palette.color_of (if alert then pal.scorpion_alert else pal.scorpion))
  | 'C' | 'D' ->
    Some (Palette.color_of (Palette.scale (if alert then pal.scorpion_alert else pal.scorpion) 0.7))
  | 'S' -> Some (Palette.color_of pal.danger)
  | _ -> None

let viper_colors (pal : Palette.t) ~blink = function
  | 'S' -> Some (Palette.color_of pal.viper)
  | 'H' -> Some (Palette.color_of (Palette.scale pal.viper 0.75))
  | 'E' ->
    Some (if blink then Palette.color_of pal.danger else Graphics.rgb 40 20 20)
  | _ -> None

let cactus_colors (pal : Palette.t) = function
  | 'G' -> Some (Palette.color_of pal.cactus)
  | 'D' -> Some (Palette.color_of pal.cactus_dark)
  | 'F' -> Some (Palette.color_of pal.flower)
  | _ -> None

let palm_colors (pal : Palette.t) = function
  | 'L' -> Some (Palette.color_of pal.cactus)
  | 'K' -> Some (Palette.color_of pal.camel_dark)
  | _ -> None

let rock_colors _pal = function
  | 'R' -> Some (gray 148)
  | 'L' -> Some (gray 186)
  | 'D' -> Some (gray 104)
  | _ -> None

(* ---- tiles ---- *)

let draw_sand (pal : Palette.t) x y r c =
  Graphics.set_color (Palette.color_of pal.sand);
  Graphics.fill_rect x y tile tile;
  (* deterministic speckles *)
  let h = cell_hash r c in
  Graphics.set_color (Palette.color_of pal.sand_dark);
  Graphics.fill_rect (x + 6 + (h mod 31)) (y + 8 + (h / 7 mod 29)) 3 2;
  Graphics.fill_rect (x + 10 + (h / 3 mod 29)) (y + 30 + (h / 11 mod 12)) 2 2;
  if h mod 3 = 0 then
    Graphics.fill_rect (x + 30 + (h / 5 mod 12)) (y + 4 + (h / 13 mod 33)) 2 3

let draw_solid (pal : Palette.t) x y r c =
  Graphics.set_color (Palette.color_of pal.rock);
  Graphics.fill_rect x y tile tile;
  (* bevel *)
  Graphics.set_color (Palette.color_of pal.rock_light);
  Graphics.fill_rect x (y + tile - 4) tile 4;
  Graphics.fill_rect x y 4 tile;
  Graphics.set_color (Palette.color_of pal.rock_dark);
  Graphics.fill_rect x y tile 3;
  Graphics.fill_rect (x + tile - 3) y 3 tile;
  (* brick seams *)
  Graphics.set_color (Palette.color_of pal.rock_dark);
  Graphics.moveto x (y + (tile / 2));
  Graphics.lineto (x + tile - 1) (y + (tile / 2));
  let off = if (r + c) mod 2 = 0 then tile / 3 else 2 * tile / 3 in
  Graphics.moveto (x + off) y;
  Graphics.lineto (x + off) (y + (tile / 2));
  Graphics.moveto (x + tile - off) (y + (tile / 2));
  Graphics.lineto (x + tile - off) (y + tile - 1)

let draw_dune (pal : Palette.t) x y ~hp =
  (* a packed, rounded sand hump; chips show as widening cracks *)
  Graphics.set_color (Palette.color_of pal.dune_dark);
  Graphics.fill_ellipse (x + (tile / 2)) (y + 16) 20 14;
  Graphics.set_color (Palette.color_of pal.dune);
  Graphics.fill_ellipse (x + (tile / 2)) (y + 20) 18 13;
  Graphics.set_color (Palette.color_of (Palette.scale pal.dune 1.15));
  Graphics.fill_ellipse (x + (tile / 2) - 5) (y + 25) 8 5;
  (* ripple lines *)
  Graphics.set_color (Palette.color_of pal.dune_dark);
  Graphics.draw_arc (x + (tile / 2)) (y + 17) 12 6 200 340;
  Graphics.draw_arc (x + (tile / 2)) (y + 22) 8 4 200 340;
  (* damage cracks *)
  if hp < 3 then begin
    Graphics.set_color (Palette.color_of pal.pit);
    Graphics.moveto (x + (tile / 2)) (y + 30);
    Graphics.lineto (x + (tile / 2) - 6) (y + 20);
    Graphics.lineto (x + (tile / 2) - 3) (y + 12)
  end;
  if hp < 2 then begin
    Graphics.set_color (Palette.color_of pal.pit);
    Graphics.moveto (x + (tile / 2) + 3) (y + 28);
    Graphics.lineto (x + (tile / 2) + 8) (y + 18);
    Graphics.moveto (x + (tile / 2) - 6) (y + 20);
    Graphics.lineto (x + (tile / 2) - 12) (y + 16)
  end

let draw_quicksand (pal : Palette.t) x y r c frame =
  (* deceptively calm rippled sand, slightly sunken and greenish *)
  let base = Palette.scale pal.sand 0.8 in
  Graphics.set_color (Palette.color_of base);
  Graphics.fill_rect (x + 2) (y + 2) (tile - 4) (tile - 4);
  let cx = x + (tile / 2) and cy = y + (tile / 2) in
  Graphics.set_color (Palette.color_of (Palette.scale pal.sand 0.62));
  Graphics.fill_ellipse cx cy 19 13;
  Graphics.set_color (Palette.color_of (Palette.scale pal.sand 0.5));
  Graphics.fill_ellipse cx cy 12 8;
  Graphics.set_color (Palette.color_of base);
  Graphics.draw_ellipse cx cy (15 + (frame / 12 mod 3)) (10 + (frame / 12 mod 2));
  (* a lazy bubble *)
  let h = cell_hash r c in
  if (frame + h) / 14 mod 4 = 0 then begin
    Graphics.set_color (Palette.color_of (Palette.scale pal.sand 0.95));
    Graphics.draw_circle (cx - 6 + (h mod 12)) (cy - 2 + (h / 7 mod 6)) 2
  end

let draw_water_drop (pal : Palette.t) x y frame =
  let cx = x + (tile / 2) and cy = y + (tile / 2) - 4 in
  Graphics.set_color (Palette.color_of pal.sand_dark);
  Graphics.fill_ellipse cx (cy - 8) 12 4;
  Graphics.set_color (Palette.color_of pal.water);
  Graphics.fill_circle cx cy 9;
  Graphics.fill_poly [| (cx - 8, cy + 3); (cx + 8, cy + 3); (cx, cy + 16) |];
  Graphics.set_color Graphics.white;
  Graphics.fill_rect (cx - 4) (cy + 2) 3 3;
  (* slow ripple *)
  if frame / 10 mod 3 = 0 then begin
    Graphics.set_color (Palette.color_of pal.water);
    Graphics.draw_ellipse cx (cy - 8) (14 + (frame mod 10)) 5
  end

let draw_cactus_tile (pal : Palette.t) x y =
  Sprites.draw ~color_of:(cactus_colors pal) ~x ~y_top:(y + tile) ~scale:4
    Sprites.cactus

let draw_teleport (pal : Palette.t) x y id frame =
  let cx = x + (tile / 2) and cy = y + (tile / 2) in
  Graphics.set_color (Palette.color_of (Palette.scale pal.sand 0.6));
  Graphics.fill_circle cx cy 16;
  let col =
    if id mod 2 = 1 then Palette.color_of pal.water
    else Palette.color_of pal.gold
  in
  Graphics.set_color col;
  for i = 0 to 2 do
    let a = (frame * 6) + (i * 120) in
    Graphics.draw_arc cx cy (14 - (i * 3)) (14 - (i * 3)) a (a + 100)
  done;
  Graphics.fill_circle cx cy 3

let draw_oneway (pal : Palette.t) x y d =
  Graphics.set_color (Palette.color_of pal.oneway);
  Graphics.fill_rect (x + 3) (y + 3) (tile - 6) (tile - 6);
  Graphics.set_color (Palette.color_of pal.oneway_light);
  Graphics.fill_rect (x + 3) (y + tile - 6) (tile - 6) 3;
  Graphics.fill_rect (x + 3) (y + 3) 3 (tile - 6);
  let cx = x + (tile / 2) and cy = y + (tile / 2) in
  let a = 13 in
  let pts =
    match d with
    | Up -> [| (cx - a, cy - a + 3); (cx + a, cy - a + 3); (cx, cy + a) |]
    | Down -> [| (cx - a, cy + a - 3); (cx + a, cy + a - 3); (cx, cy - a) |]
    | Right -> [| (cx - a + 3, cy - a); (cx - a + 3, cy + a); (cx + a, cy) |]
    | Left -> [| (cx + a - 3, cy - a); (cx + a - 3, cy + a); (cx - a, cy) |]
  in
  Graphics.set_color Graphics.white;
  Graphics.fill_poly pts

let draw_crumble (pal : Palette.t) x y r c =
  Graphics.set_color (Palette.color_of (Palette.scale pal.sand 0.88));
  Graphics.fill_rect (x + 2) (y + 2) (tile - 4) (tile - 4);
  Graphics.set_color (Palette.color_of pal.pit);
  let h = cell_hash r c in
  let cx = x + 14 + (h mod 20) and cy = y + 12 + (h / 9 mod 20) in
  Graphics.moveto (x + 6) (y + 10 + (h mod 24));
  Graphics.lineto cx cy;
  Graphics.lineto (x + tile - 8) (y + tile - 12 - (h / 5 mod 20));
  Graphics.moveto cx cy;
  Graphics.lineto (x + 12 + (h / 3 mod 24)) (y + tile - 6);
  Graphics.moveto cx cy;
  Graphics.lineto (x + tile - 6) (y + 8 + (h / 7 mod 14))

let draw_pit (pal : Palette.t) x y =
  draw_sand pal x y 0 0;
  Graphics.set_color (Palette.color_of pal.pit);
  Graphics.fill_ellipse (x + (tile / 2)) (y + (tile / 2)) 20 16;
  Graphics.set_color Graphics.black;
  Graphics.fill_ellipse (x + (tile / 2)) (y + (tile / 2) - 2) 15 11;
  Graphics.set_color (Palette.color_of pal.sand_dark);
  Graphics.draw_arc (x + (tile / 2)) (y + (tile / 2) + 4) 19 13 20 160

let draw_oasis (pal : Palette.t) x y frame ~locked ~fake =
  (* pool *)
  let wob = if fake && frame / 3 mod 2 = 0 then 1 else 0 in
  let pool_color =
    if locked && frame / 4 mod 2 = 0 then
      Palette.color_of (Palette.scale pal.water 1.45)
    else Palette.color_of pal.water
  in
  Graphics.set_color (Palette.color_of pal.sand_dark);
  Graphics.fill_ellipse (x + (tile / 2)) (y + 14) 20 11;
  Graphics.set_color pool_color;
  Graphics.fill_ellipse (x + (tile / 2) + wob) (y + 15) 17 9;
  Graphics.set_color Graphics.white;
  Graphics.fill_rect (x + (tile / 2) - 6 + wob) (y + 16) 4 2;
  (* palm *)
  Sprites.draw ~color_of:(palm_colors pal) ~x:(x + 6) ~y_top:(y + tile + 8)
    ~scale:3 Sprites.palm;
  if not locked then begin
    (* welcoming gold rim *)
    Graphics.set_color (Palette.color_of pal.gold);
    Graphics.draw_ellipse (x + (tile / 2)) (y + 14) 21 12
  end

let draw_push_rock (pal : Palette.t) x y =
  Sprites.draw ~color_of:(rock_colors pal) ~x ~y_top:(y + tile) ~scale:4
    Sprites.rock

let draw_gate (pal : Palette.t) x y frame ~center_goal =
  (* a stone gate out of the page — or, at the very center, the safe spot *)
  if center_goal then begin
    let cx = x + (tile / 2) and cy = y + (tile / 2) in
    Fx.draw_glow ~cx ~cy ~radius:(20 + (frame / 6 mod 4)) ~steps:5 pal.gold
      pal.sand;
    Graphics.set_color (Palette.color_of pal.gold);
    Graphics.draw_circle cx cy 14;
    Graphics.draw_circle cx cy 9;
    Graphics.fill_circle cx cy 4
  end
  else begin
    Graphics.set_color (Palette.color_of pal.rock_dark);
    Graphics.fill_rect (x + 4) (y + 4) 10 (tile - 8);
    Graphics.fill_rect (x + tile - 14) (y + 4) 10 (tile - 8);
    Graphics.fill_rect (x + 2) (y + tile - 12) (tile - 4) 8;
    Fx.draw_glow ~cx:(x + (tile / 2)) ~cy:(y + (tile / 2) - 4)
      ~radius:(10 + (frame / 8 mod 3)) ~steps:4 pal.gold pal.sand;
    Graphics.set_color (Palette.color_of pal.rock_light);
    Graphics.fill_rect (x + 4) (y + tile - 10) (tile - 8) 3
  end

let draw_tile (pal : Palette.t) ~frame ~locked_exit ~gate ~center_goal r c t
    ~ox ~oy =
  let x, y = px_of_cell ~ox ~oy (r, c) in
  match t with
  | Solid -> draw_solid pal x y r c
  | Empty -> draw_sand pal x y r c
  | Dune hp ->
    draw_sand pal x y r c;
    draw_dune pal x y ~hp
  | Fake_dune _ ->
    (* identical to a healthy dune on purpose: the herring never cracks *)
    draw_sand pal x y r c;
    draw_dune pal x y ~hp:3
  | Water ->
    draw_sand pal x y r c;
    draw_water_drop pal x y frame
  | Cactus ->
    draw_sand pal x y r c;
    draw_cactus_tile pal x y
  | Teleport id ->
    draw_sand pal x y r c;
    draw_teleport pal x y id frame
  | One_way d -> draw_oneway pal x y d
  | Crumble ->
    draw_sand pal x y r c;
    draw_crumble pal x y r c
  | Quicksand ->
    draw_sand pal x y r c;
    draw_quicksand pal x y r c frame
  | Pit -> draw_pit pal x y
  | Push_rock ->
    draw_sand pal x y r c;
    draw_push_rock pal x y
  | False_exit ->
    draw_sand pal x y r c;
    draw_oasis pal x y frame ~locked:false ~fake:true
  | Exit ->
    draw_sand pal x y r c;
    if gate then draw_gate pal x y frame ~center_goal
    else draw_oasis pal x y frame ~locked:locked_exit ~fake:false

(* ---- entities ---- *)

let draw_camel (pal : Palette.t) ~px ~py ~facing =
  let x = int_of_float px and y = int_of_float py in
  Graphics.set_color (Palette.color_of (Palette.scale pal.sand 0.75));
  Graphics.fill_ellipse (x + (tile / 2)) (y + 6) 16 4;
  Sprites.draw
    ~flip:(facing = Left)
    ~color_of:(camel_colors pal) ~x ~y_top:(y + tile) ~scale:4 Sprites.camel

let draw_enemy (pal : Palette.t) ~frame ~ox ~oy e =
  let x, y = px_of_cell ~ox ~oy e.cell in
  match e.kind with
  | Scorpion ->
    let alert = e.st = Chase in
    if alert then begin
      Fx.draw_glow ~cx:(x + (tile / 2)) ~cy:(y + (tile / 2)) ~radius:26
        ~steps:4 pal.scorpion_alert pal.sand;
      Sprites.draw
        ~color_of:(scorpion_colors pal ~alert)
        ~x ~y_top:(y + tile) ~scale:4 Sprites.scorpion;
      Font.draw ~scale:3 ~x:(x + 18) ~y_top:(y + tile + 22)
        (Palette.color_of pal.danger) "!"
    end
    else
      Sprites.draw
        ~color_of:(scorpion_colors pal ~alert)
        ~x ~y_top:(y + tile) ~scale:4 Sprites.scorpion
  | Viper ->
    let blink = frame / 8 mod 4 <> 0 in
    Sprites.draw
      ~color_of:(viper_colors pal ~blink)
      ~x ~y_top:(y + tile) ~scale:4 Sprites.viper

let draw_los (pal : Palette.t) ~frame ~is_protected ~ox ~oy cells =
  let col =
    if is_protected then Palette.color_of pal.gold
    else Palette.color_of pal.danger
  in
  Graphics.set_color col;
  let pulse = if frame / 6 mod 2 = 0 then 3 else 2 in
  List.iter
    (fun (r, c) ->
      let x, y = px_of_cell ~ox ~oy (r, c) in
      let cx = x + (tile / 2) and cy = y + (tile / 2) in
      Graphics.fill_rect (cx - 1) (cy - 8) pulse pulse;
      Graphics.fill_rect (cx - 1) (cy + 6) pulse pulse;
      Graphics.fill_rect (cx - 8) (cy - 1) pulse pulse;
      Graphics.fill_rect (cx + 6) (cy - 1) pulse pulse;
      Graphics.fill_rect (cx - 1) (cy - 1) pulse pulse)
    cells

let draw_powerup (pal : Palette.t) ~frame ~ox ~oy (r, c) =
  let x, y = px_of_cell ~ox ~oy (r, c) in
  let cx = x + (tile / 2) and cy = y + (tile / 2) in
  let pulse = 2 * (frame / 6 mod 3) in
  Fx.draw_glow ~cx ~cy ~radius:(18 + pulse) ~steps:4 pal.gold pal.sand;
  Graphics.set_color (Palette.color_of pal.gold);
  Graphics.fill_circle cx cy 8;
  Graphics.set_color Graphics.white;
  Graphics.fill_rect (cx - 3) (cy + 2) 3 3;
  Graphics.set_color (Palette.color_of pal.gold);
  for i = 0 to 7 do
    let a = (float_of_int i *. Float.pi /. 4.) +. (float_of_int frame /. 20.) in
    let x2 = cx + int_of_float (cos a *. 14.)
    and y2 = cy + int_of_float (sin a *. 14.) in
    Graphics.fill_rect (x2 - 1) (y2 - 1) 3 3
  done

(* The job application: an advancing wall of cream paper with ruled lines,
   checkboxes and a torn leading edge.  One is drawn per active front. *)
let paper_color = Graphics.rgb 248 242 222
let rule_color = Graphics.rgb 140 150 180
let margin_color = Graphics.rgb 220 90 90
let ink_color = Graphics.rgb 70 70 85

let draw_paper_rect x0 y0 x1 y1 =
  let x0 = max 0 x0 and y0 = max 0 y0 in
  let x1 = min win_w x1 and y1 = min board_h y1 in
  if x1 > x0 && y1 > y0 then begin
    Graphics.set_color paper_color;
    Graphics.fill_rect x0 y0 (x1 - x0) (y1 - y0);
    (* ruled lines *)
    Graphics.set_color rule_color;
    let y = ref (y0 + 6) in
    while !y < y1 do
      Graphics.moveto x0 !y;
      Graphics.lineto (x1 - 1) !y;
      y := !y + 14
    done;
    (* scribbled "ink" and checkboxes *)
    let y = ref (y0 + 10) in
    while !y < y1 - 6 do
      let x = ref (x0 + 10) in
      while !x < x1 - 24 do
        if (!x + (7 * !y)) mod 5 = 0 then begin
          Graphics.set_color ink_color;
          Graphics.fill_rect !x !y (8 + ((!x * !y) mod 9)) 2
        end;
        if (!x + (3 * !y)) mod 97 = 0 then begin
          Graphics.set_color ink_color;
          Graphics.draw_rect !x (!y - 2) 7 7;
          if !y mod 2 = 0 then begin
            Graphics.moveto !x (!y - 2);
            Graphics.lineto (!x + 7) (!y + 5);
            Graphics.moveto !x (!y + 5);
            Graphics.lineto (!x + 7) (!y - 2)
          end
        end;
        x := !x + 26
      done;
      y := !y + 28
    done
  end

(* Torn edge + red margin line along the leading edge of a front. *)
let draw_paper_edge ~vertical ~pos ~toward =
  (* [toward] = +1 if the paper grows toward larger coords *)
  if vertical then begin
    let y = ref 0 in
    while !y < board_h do
      let bh = 6 + Random.int 12 in
      let reach = Random.int 14 * toward in
      Graphics.set_color paper_color;
      Graphics.fill_rect (min pos (pos + reach)) !y (abs reach) bh;
      y := !y + bh
    done;
    Graphics.set_color margin_color;
    Graphics.moveto (pos - (6 * toward)) 0;
    Graphics.lineto (pos - (6 * toward)) (board_h - 1)
  end
  else begin
    let x = ref 0 in
    while !x < win_w do
      let bw = 6 + Random.int 12 in
      let reach = Random.int 14 * toward in
      Graphics.set_color paper_color;
      Graphics.fill_rect !x (min pos (pos + reach)) bw (abs reach);
      x := !x + bw
    done;
    Graphics.set_color margin_color;
    Graphics.moveto 0 (pos - (6 * toward));
    Graphics.lineto (win_w - 1) (pos - (6 * toward))
  end

let draw_application ~voids ~ox:_ =
  List.iter
    (fun (side, p) ->
      match side with
      | Left ->
        let x1 = (p + 1) * tile in
        draw_paper_rect 0 0 x1 board_h;
        draw_paper_edge ~vertical:true ~pos:x1 ~toward:1
      | Right ->
        let x0 = p * tile in
        draw_paper_rect x0 0 win_w board_h;
        draw_paper_edge ~vertical:true ~pos:x0 ~toward:(-1)
      | Up ->
        (* rows 0..p = the TOP strip of the screen *)
        let y0 = (rows - 1 - p) * tile in
        draw_paper_rect 0 y0 win_w board_h;
        draw_paper_edge ~vertical:false ~pos:y0 ~toward:(-1)
      | Down ->
        (* rows p..12 = the BOTTOM strip of the screen *)
        let y1 = (rows - p) * tile in
        draw_paper_rect 0 0 win_w y1;
        draw_paper_edge ~vertical:false ~pos:y1 ~toward:1)
    voids

(* Fading hoofprints along recently traversed cells. *)
let draw_trail (pal : Palette.t) ~frame ~ox ~oy trail =
  List.iter
    (fun ((r, c), stamp) ->
      let age = frame - stamp in
      if age < 150 then begin
        let x, y = px_of_cell ~ox ~oy (r, c) in
        let shade = if age < 50 then 0.78 else if age < 100 then 0.86 else 0.93 in
        Graphics.set_color (Palette.color_of (Palette.scale pal.sand shade));
        let h = cell_hash r c in
        Graphics.fill_rect (x + 14 + (h mod 5)) (y + 18) 4 3;
        Graphics.fill_rect (x + 26 + (h mod 4)) (y + 26) 4 3;
        Graphics.fill_rect (x + 18 + (h mod 3)) (y + 32) 3 3;
        Graphics.fill_rect (x + 28) (y + 14) 3 3
      end)
    trail

(* ---- the full board ---- *)

let draw_board (pal : Palette.t) ~grid ~enemies ~powerups ~voids ~trail
    ~water ~threshold ~frame ~camel_px ~facing ~is_protected ~ox ~oy =
  let locked_exit = water < threshold in
  let gate = voids <> [] in
  (* the "center goal" styling is used on the last page of the application *)
  let center_goal = gate && List.mem Up (List.map fst voids) in
  for r = 0 to rows - 1 do
    for c = 0 to cols - 1 do
      draw_tile pal ~frame ~locked_exit ~gate ~center_goal r c grid.(r).(c)
        ~ox ~oy
    done
  done;
  draw_trail pal ~frame ~ox ~oy trail;
  draw_los pal ~frame ~is_protected ~ox ~oy
    (Slide.viper_los_cells grid enemies);
  List.iter (draw_powerup pal ~frame ~ox ~oy) powerups;
  List.iter (draw_enemy pal ~frame ~ox ~oy) enemies;
  (let px, py = camel_px in
   draw_camel pal ~px:(px +. float_of_int ox) ~py:(py +. float_of_int oy)
     ~facing);
  Fx.draw ();
  draw_application ~voids ~ox

(* ---- HUD ---- *)

let draw_hud (pal : Palette.t) ~name ~water ~threshold ~moves ~power_left
    ~msg ~msg_danger ~frame =
  Graphics.set_color (Graphics.rgb 46 28 16);
  Graphics.fill_rect 0 board_h win_w (win_h - board_h);
  Graphics.set_color (Palette.color_of pal.sand_dark);
  Graphics.fill_rect 0 board_h win_w 2;
  Graphics.set_color (Graphics.rgb 70 46 26);
  Graphics.fill_rect 0 (win_h - 2) win_w 2;
  (* level name + message *)
  Font.draw ~scale:2 ~x:16 ~y_top:(win_h - 10) (Palette.color_of pal.ui) name;
  (match msg with
   | "" -> ()
   | m ->
     let color =
       if msg_danger then Palette.color_of pal.danger
       else Palette.color_of pal.gold
     in
     if (not msg_danger) || frame / 8 mod 2 = 0 then
       Font.draw ~scale:2 ~x:16 ~y_top:(win_h - 52) color m);
  (* water meter (hidden when the level needs none) *)
  let wx = 480 in
  if threshold > 0 then begin
  Font.draw ~scale:1 ~x:wx ~y_top:(win_h - 8) (Palette.color_of pal.sand) "WATER";
  for i = 0 to max threshold water - 1 do
    let cx = wx + 8 + (i * 26) and cy = win_h - 34 in
    if i < water then begin
      Graphics.set_color (Palette.color_of pal.water);
      Graphics.fill_circle cx cy 8;
      Graphics.fill_poly [| (cx - 7, cy + 3); (cx + 7, cy + 3); (cx, cy + 14) |]
    end
    else begin
      Graphics.set_color (Palette.color_of (Palette.scale pal.water 0.45));
      Graphics.draw_circle cx cy 8
    end
  done;
  Font.draw ~scale:2 ~x:(wx + 8 + (max threshold water * 26) + 6)
    ~y_top:(win_h - 26)
    (Palette.color_of pal.ui)
    (Printf.sprintf "%d/%d" water threshold)
  end;
  (* oasis power *)
  if power_left > 0 then begin
    Font.draw ~scale:1 ~x:wx ~y_top:(win_h - 56) (Palette.color_of pal.gold)
      "OASIS POWER";
    for i = 0 to power_left - 1 do
      Graphics.set_color (Palette.color_of pal.gold);
      Graphics.fill_circle (wx + 8 + (i * 18)) (win_h - 74) 6
    done
  end;
  (* moves *)
  Font.draw ~scale:1 ~x:740 ~y_top:(win_h - 8) (Palette.color_of pal.sand) "MOVES";
  Font.draw ~scale:4 ~x:740 ~y_top:(win_h - 22) (Palette.color_of pal.gold)
    (string_of_int moves);
  (* controls *)
  Font.draw ~scale:1 ~x:740 ~y_top:(win_h - 66) (Palette.color_of pal.sand)
    "WASD SLIDE  Z UNDO";
  Font.draw ~scale:1 ~x:740 ~y_top:(win_h - 80) (Palette.color_of pal.sand)
    "R RESET  ESC MENU"

(* ---- panels & screens ---- *)

let draw_panel ~cx ~cy ~w ~h =
  Graphics.set_color (Graphics.rgb 40 26 16);
  Graphics.fill_rect (cx - (w / 2)) (cy - (h / 2)) w h;
  Graphics.set_color (Graphics.rgb 255 244 214);
  Graphics.draw_rect (cx - (w / 2)) (cy - (h / 2)) w h;
  Graphics.draw_rect (cx - (w / 2) + 4) (cy - (h / 2) + 4) (w - 8) (h - 8)

let dune_layer (pal : Palette.t) ~base_y ~amp ~phase ~color_scale =
  let n = win_w / 8 in
  let curve =
    Array.init (n + 1) (fun x ->
        let fx = float_of_int x *. 8. in
        let y =
          base_y
          + int_of_float
              (amp *. sin ((fx /. 130.) +. phase)
               +. (amp /. 2.) *. sin ((fx /. 61.) +. (phase *. 1.7)))
        in
        (int_of_float fx, y))
  in
  Graphics.set_color (Palette.color_of (Palette.scale pal.sand color_scale));
  Graphics.fill_poly (Array.append curve [| (win_w, 0); (0, 0) |])

let draw_title (pal : Palette.t) ~frame =
  Fx.draw_gradient ~x:0 ~y:0 ~w:win_w ~h:win_h pal.sky_top pal.sky_bot;
  (* sun *)
  Fx.draw_glow ~cx:730 ~cy:560 ~radius:90 ~steps:6 pal.gold pal.sky_top;
  Graphics.set_color (Palette.color_of pal.gold);
  Graphics.fill_circle 730 560 42;
  (* parallax dunes *)
  let ph = float_of_int frame in
  dune_layer pal ~base_y:230 ~amp:22. ~phase:(ph /. 240.) ~color_scale:0.62;
  dune_layer pal ~base_y:185 ~amp:26. ~phase:(0.9 +. (ph /. 150.)) ~color_scale:0.8;
  dune_layer pal ~base_y:130 ~amp:30. ~phase:(2.3 +. (ph /. 90.)) ~color_scale:1.0;
  (* camel walking the front dune *)
  let cx = (frame * 2) mod (win_w + 200) - 100 in
  let cy =
    128
    + int_of_float
        (30. *. sin ((float_of_int cx /. 130.) +. 2.3 +. (ph /. 90.)))
    + if frame / 6 mod 2 = 0 then 2 else 0
  in
  Sprites.draw ~color_of:(camel_colors pal) ~x:cx ~y_top:(cy + 84) ~scale:7
    Sprites.camel;
  (* title: big, central *)
  Font.draw_shadowed ~scale:12 ~cx:(win_w / 2) ~y_top:530
    ~shadow:(Palette.color_of pal.camel_dark)
    (Palette.color_of pal.ui) "DUNESCAPE";
  Font.draw_centered ~scale:3 ~cx:(win_w / 2) ~y_top:410
    (Palette.color_of pal.gold)
    "ALL TRADES ARE FINAL.";
  if frame / 14 mod 2 = 0 then
    Font.draw_centered ~scale:3 ~cx:(win_w / 2) ~y_top:80
      (Palette.color_of pal.ui) "PRESS ENTER";
  Fx.draw ()

let level_icon (pal : Palette.t) i ~x ~y =
  match i with
  | 0 ->
    Sprites.draw ~color_of:(camel_colors pal) ~x ~y_top:(y + 60) ~scale:5
      Sprites.camel
  | 1 ->
    Sprites.draw
      ~color_of:(scorpion_colors pal ~alert:false)
      ~x ~y_top:(y + 60) ~scale:5 Sprites.scorpion
  | 2 ->
    Sprites.draw
      ~color_of:(viper_colors pal ~blink:true)
      ~x ~y_top:(y + 60) ~scale:5 Sprites.viper
  | _ ->
    Fx.draw_glow ~cx:(x + 30) ~cy:(y + 30) ~radius:28 ~steps:5 pal.void_edge
      pal.void_deep

let draw_level_select (pal : Palette.t) ~frame ~sel ~unlocked_void ~cleared =
  Fx.draw_gradient ~x:0 ~y:0 ~w:win_w ~h:win_h pal.sky_top pal.sky_bot;
  dune_layer pal ~base_y:110 ~amp:24. ~phase:(float_of_int frame /. 200.)
    ~color_scale:0.75;
  Font.draw_shadowed ~scale:5 ~cx:(win_w / 2) ~y_top:680
    ~shadow:(Palette.color_of pal.camel_dark)
    (Palette.color_of pal.ui) "SELECT LEVEL";
  let n = Levels.card_count in
  let card_w = 200 and card_h = 280 and gap = 24 in
  let total = (n * card_w) + ((n - 1) * gap) in
  let x0 = (win_w - total) / 2 in
  Array.iteri
    (fun i (spec : Levels.spec) ->
      if i < n then begin
      let spec =
        if i = Levels.finale_index then
          { spec with Levels.name = "THE APPLICATION" }
        else spec
      in
      let x = x0 + (i * (card_w + gap)) in
      let y = 240 + if i = sel then 10 else 0 in
      let hidden = i = Levels.finale_index && not unlocked_void in
      Graphics.set_color
        (if i = sel then Graphics.rgb 60 40 22 else Graphics.rgb 44 30 18);
      Graphics.fill_rect x y card_w card_h;
      Graphics.set_color
        (if i = sel then Palette.color_of pal.gold
         else Palette.color_of pal.sand_dark);
      Graphics.draw_rect x y card_w card_h;
      Graphics.draw_rect (x + 3) (y + 3) (card_w - 6) (card_h - 6);
      if hidden then begin
        Font.draw_centered ~scale:4 ~cx:(x + (card_w / 2)) ~y_top:(y + 180)
          (Palette.color_of pal.sand_dark) "?????";
        Font.draw_centered ~scale:1 ~cx:(x + (card_w / 2)) ~y_top:(y + 60)
          (Palette.color_of pal.sand_dark) "SOMETHING WAITS"
      end
      else begin
        Font.draw_centered ~scale:2 ~cx:(x + (card_w / 2)) ~y_top:(y + card_h - 14)
          (Palette.color_of pal.gold)
          (Printf.sprintf "LEVEL %d" (i + 1));
        (* split name across lines *)
        let words = String.split_on_char ' ' spec.name in
        List.iteri
          (fun li w ->
            Font.draw_centered ~scale:2 ~cx:(x + (card_w / 2))
              ~y_top:(y + card_h - 54 - (li * 26))
              (Palette.color_of pal.ui) w)
          words;
        level_icon pal i ~x:(x + (card_w / 2) - 30) ~y:(y + 60);
        if cleared.(i) then
          Font.draw_centered ~scale:2 ~cx:(x + (card_w / 2)) ~y_top:(y + 34)
            (Palette.color_of pal.water) "CLEARED"
      end
      end)
    Levels.all;
  Font.draw_centered ~scale:2 ~cx:(win_w / 2) ~y_top:160
    (Palette.color_of pal.ui)
    "A/D CHOOSE   ENTER START   ESC TITLE";
  Fx.draw ()

let draw_victory (pal : Palette.t) ~frame ~total_moves ~deaths =
  Fx.draw_gradient ~x:0 ~y:0 ~w:win_w ~h:win_h pal.sky_top pal.sky_bot;
  Fx.draw_glow ~cx:(win_w / 2) ~cy:420 ~radius:160 ~steps:6 pal.gold
    pal.sky_bot;
  Sprites.draw ~color_of:(camel_colors pal) ~x:((win_w / 2) - 42)
    ~y_top:470 ~scale:7 Sprites.camel;
  Font.draw_shadowed ~scale:6 ~cx:(win_w / 2) ~y_top:660
    ~shadow:(Palette.color_of pal.void_deep)
    (Palette.color_of pal.gold) "YOU OUTWITTED";
  Font.draw_shadowed ~scale:6 ~cx:(win_w / 2) ~y_top:600
    ~shadow:(Palette.color_of pal.void_deep)
    (Palette.color_of pal.gold) "THE DESERT.";
  Font.draw_centered ~scale:2 ~cx:(win_w / 2) ~y_top:330
    (Palette.color_of pal.ui)
    "AND DODGED THE PAPERWORK.";
  Font.draw_centered ~scale:2 ~cx:(win_w / 2) ~y_top:290
    (Palette.color_of pal.ui)
    (Printf.sprintf "MOVES: %d    DEATHS: %d" total_moves deaths);
  if frame / 14 mod 2 = 0 then
    Font.draw_centered ~scale:3 ~cx:(win_w / 2) ~y_top:120
      (Palette.color_of pal.ui) "PRESS ENTER";
  Fx.draw ()
