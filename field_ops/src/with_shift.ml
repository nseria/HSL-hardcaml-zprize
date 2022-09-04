open Core
open Hardcaml
open Signal

type t =
  { x : Signal.t
  ; shift : int
  }

let width t = Signal.width t.x + t.shift
let no_shift x = { x; shift = 0 }
let create ~shift x = { x; shift }
let sll t ~by = { x = t.x; shift = t.shift + by }
let map ~f t = { x = f t.x; shift = t.shift }

let uresize t new_width =
  { x = Signal.uresize t.x (new_width - t.shift); shift = t.shift }
;;

let validate_all_items_same_width items =
  let w = width (List.hd_exn items) in
  List.iter items ~f:(fun x -> assert (width x = w));
  w
;;

let pipe_add ~scope ~enable ~clock ~stages (items : t list) =
  let item_width = validate_all_items_same_width items in
  let smallest_shift =
    Option.value_exn
      (List.min_elt ~compare:Int.compare (List.map items ~f:(fun i -> i.shift)))
  in
  let x =
    List.map items ~f:(fun item ->
        let signal =
          match item.shift - smallest_shift with
          | 0 -> item.x
          | shift -> item.x @: zero shift
        in
        Signal.uresize signal (item_width - smallest_shift))
    |> Adder_subtractor_pipe.add ~scope ~enable ~clock ~stages
    |> Adder_subtractor_pipe.O.result
  in
  { x; shift = smallest_shift }
;;

let to_signal t = t.x @: zero t.shift