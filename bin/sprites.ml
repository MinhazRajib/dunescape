(* Pixel-art sprites as color-coded grids (README 15.3), drawn as chunky
   scaled rects.  Each sprite is 12x12; at scale 4 it fills a 48px tile. *)

let camel =
  [|
    "............";
    ".........TT.";
    "........TTE.";
    "........TTM.";
    "..TTT...TT..";
    ".TTTTTT.TT..";
    ".TTRRTTTTT..";
    ".TTRRTTTTT..";
    "..TTTTTTT...";
    "..DD..DD....";
    "..DD..DD....";
    "............";
  |]

let scorpion =
  [|
    "....TT......";
    "...T........";
    "...TS.......";
    "....T.......";
    "....BBBB....";
    "...BBBBBB...";
    "..CBBBBBBC..";
    ".CC.BBBB.CC.";
    "....BBBB....";
    "...D.DD.D...";
    "..D......D..";
    "............";
  |]

let viper =
  [|
    "....HH......";
    "...HEEH.....";
    "...HHHH.....";
    "....HH......";
    "....SS......";
    "..SSSSSS....";
    ".SS....SS...";
    ".S..SS..S...";
    ".S.SSSS.S...";
    ".SS....SS...";
    "..SSSSSS....";
    "............";
  |]

let cactus =
  [|
    ".....FF.....";
    "....GGGG....";
    "....GDGG....";
    ".GG.GGDG.GG.";
    ".GG.GDGG.GG.";
    ".GG.GGGG.GG.";
    ".GGGGGGGGGG.";
    "....GDGG....";
    "....GGDG....";
    "....GDGG....";
    "....GGGG....";
    "............";
  |]

let palm =
  [|
    "..L.LLL.L...";
    ".LLLLLLLLL..";
    "LL.LLLLL.LL.";
    "....LKL.....";
    ".....K......";
    "....KK......";
    "....K.......";
  |]

let rock =
  [|
    "............";
    "...RRRR.....";
    "..RLLRRR....";
    ".RLRRRRRR...";
    ".RRRRRRRRR..";
    ".RRRRRRRRR..";
    ".RRRRRRRRD..";
    ".RRRRRRRDD..";
    "..RRRRRDD...";
    "...DDDDD....";
    "............";
    "............";
  |]

(* Draw [grid] with its top-left at (x, y_top) in Graphics coords (y up),
   [scale] px per sprite pixel.  [color_of] maps a grid char to a color;
   [None] = transparent.  [flip] mirrors horizontally. *)
let draw ?(flip = false) ~color_of ~x ~y_top ~scale grid =
  Array.iteri
    (fun row line ->
      String.iteri
        (fun col ch ->
          match color_of ch with
          | None -> ()
          | Some c ->
            let col = if flip then String.length line - 1 - col else col in
            Graphics.set_color c;
            Graphics.fill_rect
              (x + (col * scale))
              (y_top - ((row + 1) * scale))
              scale scale)
        line)
    grid
