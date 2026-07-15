(* Juice: particles, screen shake, gradients, glow, scanlines and the glitch
   effect (README section 15).  All cosmetic — game logic never touches this.

   In a turn-based game these run during the short animation bursts between
   keypresses and during the ambient idle loop. *)

type particle = {
  mutable x : float;
  mutable y : float;
  mutable vx : float;
  mutable vy : float;
  mutable life : float;
  mutable size : float;
  gravity : float;
  color : Graphics.color;
}

let particles : particle list ref = ref []

let spawn ?(gravity = -0.18) ?(speed = 3.5) ?(life = 1.0) ?(size = 4.) ~n ~x
    ~y color =
  for _ = 1 to n do
    let a = Random.float (2. *. Float.pi) in
    let s = Random.float speed +. 0.8 in
    particles :=
      { x = float_of_int x; y = float_of_int y; vx = cos a *. s;
        vy = sin a *. s; life = life -. Random.float 0.3;
        size = size +. Random.float 2.; gravity; color }
      :: !particles
  done

(* Slow upward sparkle (collect, exit shimmer). *)
let spawn_rise ~n ~x ~y color =
  for _ = 1 to n do
    particles :=
      { x = float_of_int x +. Random.float 30. -. 15.;
        y = float_of_int y +. Random.float 10.;
        vx = Random.float 0.8 -. 0.4; vy = 0.8 +. Random.float 1.2;
        life = 1.0; size = 2. +. Random.float 3.; gravity = 0.02;
        color }
      :: !particles
  done

let step () =
  List.iter
    (fun p ->
      p.x <- p.x +. p.vx;
      p.y <- p.y +. p.vy;
      p.vy <- p.vy +. p.gravity;
      p.life <- p.life -. 0.035)
    !particles;
  particles := List.filter (fun p -> p.life > 0.) !particles

let draw () =
  List.iter
    (fun p ->
      Graphics.set_color p.color;
      let s = max 1 (int_of_float (p.life *. p.size)) in
      Graphics.fill_rect (int_of_float p.x) (int_of_float p.y) s s)
    !particles

let clear () = particles := []

(* ---- screen shake ---- *)

let shake_amt = ref 0.

let add_shake a = shake_amt := Float.max !shake_amt a

let shake_offset () =
  if !shake_amt <= 0.5 then (0, 0)
  else begin
    shake_amt := !shake_amt *. 0.82;
    let a = int_of_float !shake_amt in
    (Random.int ((2 * a) + 1) - a, Random.int ((2 * a) + 1) - a)
  end

(* ---- primitives ---- *)

let draw_gradient ~x ~y ~w ~h top bot =
  for i = 0 to h - 1 do
    let t = float_of_int i /. float_of_int (max 1 (h - 1)) in
    Graphics.set_color (Palette.lerp_c bot top t);
    Graphics.moveto x (y + i);
    Graphics.lineto (x + w - 1) (y + i)
  done

let draw_glow ~cx ~cy ~radius ~steps color_in color_out =
  for i = steps downto 1 do
    let t = float_of_int i /. float_of_int steps in
    Graphics.set_color (Palette.lerp_c color_in color_out t);
    Graphics.fill_circle cx cy (int_of_float (float_of_int radius *. t))
  done

(* One frame of the twist glitch: displace horizontal bands of the current
   screen and slash red bars through them (README 15.10). *)
let glitch_frame ~w ~h =
  for _ = 1 to 10 do
    let by = Random.int h in
    let bh = Random.int 24 + 4 in
    let bh = min bh (h - by) in
    if bh > 0 then begin
      let dx = Random.int 60 - 30 in
      let img = Graphics.get_image 0 by w bh in
      Graphics.draw_image img dx by
    end;
    if Random.int 3 = 0 then begin
      Graphics.set_color (Graphics.rgb 255 0 80);
      Graphics.fill_rect 0 (Random.int h) w 2
    end
  done
