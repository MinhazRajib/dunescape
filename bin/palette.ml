(* Color palettes (README section 16).  Colors are kept as RGB triples so we
   can lerp gradients; convert with [color_of] at draw time. *)

type rgb = int * int * int

type t = {
  sky_top : rgb;
  sky_bot : rgb;
  sand : rgb;
  sand_dark : rgb;
  rock : rgb;
  rock_light : rgb;
  rock_dark : rgb;
  dune : rgb;
  dune_dark : rgb;
  water : rgb;
  cactus : rgb;
  cactus_dark : rgb;
  flower : rgb;
  camel : rgb;
  camel_dark : rgb;
  scorpion : rgb;
  scorpion_alert : rgb;
  viper : rgb;
  gold : rgb;
  oneway : rgb;
  oneway_light : rgb;
  ui : rgb;
  danger : rgb;
  void_deep : rgb;
  void_edge : rgb;
  pit : rgb;
}

let day =
  {
    sky_top = (255, 176, 124);
    sky_bot = (255, 123, 84);
    sand = (232, 193, 112);
    sand_dark = (212, 161, 94);
    rock = (176, 124, 71);
    rock_light = (205, 152, 96);
    rock_dark = (128, 88, 50);
    dune = (222, 176, 96);
    dune_dark = (170, 124, 66);
    water = (78, 205, 196);
    cactus = (63, 163, 77);
    cactus_dark = (40, 115, 52);
    flower = (255, 107, 165);
    camel = (210, 161, 94);
    camel_dark = (120, 80, 40);
    scorpion = (139, 90, 43);
    scorpion_alert = (224, 48, 48);
    viper = (184, 166, 90);
    gold = (255, 210, 74);
    oneway = (91, 125, 177);
    oneway_light = (140, 170, 215);
    ui = (255, 244, 214);
    danger = (255, 0, 0);
    void_deep = (40, 10, 40);
    void_edge = (255, 0, 80);
    pit = (60, 40, 25);
  }

let dusk =
  {
    sky_top = (93, 46, 93);
    sky_bot = (40, 10, 40);
    sand = (130, 98, 82);
    sand_dark = (104, 76, 62);
    rock = (86, 60, 62);
    rock_light = (116, 84, 86);
    rock_dark = (56, 38, 40);
    dune = (120, 88, 74);
    dune_dark = (88, 62, 52);
    water = (60, 160, 152);
    cactus = (45, 110, 60);
    cactus_dark = (28, 74, 40);
    flower = (200, 90, 140);
    camel = (196, 148, 90);
    camel_dark = (100, 66, 36);
    scorpion = (110, 72, 38);
    scorpion_alert = (255, 60, 60);
    viper = (150, 134, 76);
    gold = (255, 210, 74);
    oneway = (80, 100, 150);
    oneway_light = (120, 145, 190);
    ui = (255, 244, 214);
    danger = (255, 0, 0);
    void_deep = (24, 4, 28);
    void_edge = (255, 0, 80);
    pit = (36, 22, 20);
  }

let color_of (r, g, b) = Graphics.rgb r g b

let lerp_c (r1, g1, b1) (r2, g2, b2) t =
  let l a b = int_of_float (float_of_int a +. ((float_of_int (b - a)) *. t)) in
  Graphics.rgb (l r1 r2) (l g1 g2) (l b1 b2)

(* Darken / lighten helpers for bevels and glows. *)
let scale (r, g, b) f =
  let s x = max 0 (min 255 (int_of_float (float_of_int x *. f))) in
  (s r, s g, s b)
