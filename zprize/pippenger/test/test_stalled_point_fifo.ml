open! Core
open Hardcaml
open Hardcaml_waveterm
module Config = Pippenger.Config.Zprize
module Fifo = Pippenger.Stalled_point_fifos.Make (Config)
module Sim = Cyclesim.With_interface (Fifo.I) (Fifo.O)

let ( <-. ) a b = a := Bits.of_int ~width:(Bits.width !a) b

let test () =
  let sim =
    Sim.create
      ~config:Cyclesim.Config.trace_all
      (Fifo.create
         (Scope.create ~flatten_design:true ~auto_label_hierarchical_ports:true ()))
  in
  let waves, sim = Waveform.create sim in
  let inputs = Cyclesim.inputs sim in
  inputs.clear := Bits.vdd;
  Cyclesim.cycle sim;
  inputs.clear := Bits.gnd;
  let push ~window ~scalar ~affine_point =
    inputs.window <-. window;
    inputs.scalar <-. scalar;
    inputs.affine_point <-. affine_point;
    inputs.push <-. 1;
    Cyclesim.cycle sim;
    inputs.push <-. 0
  in
  let pop ~window =
    inputs.window <-. window;
    inputs.pop <-. 1;
    Cyclesim.cycle sim;
    inputs.pop <-. 0
  in
  for window = 0 to Config.num_windows - 1 do
    push ~window ~scalar:(window + 1) ~affine_point:((window + 1) * 0x100)
  done;
  for window = 0 to Config.num_windows - 1 do
    pop ~window
  done;
  for _ = 0 to 10 do
    Cyclesim.cycle sim
  done;
  waves
;;

let%expect_test "" =
  let waves = test () in
  Waveform.print ~display_height:120 ~display_width:120 ~wave_width:2 waves;
  [%expect
    {|
    ┌Signals───────────┐┌Waves─────────────────────────────────────────────────────────────────────────────────────────────┐
    │clock             ││┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌─│
    │                  ││   └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘ │
    │clear             ││──────┐                                                                                           │
    │                  ││      └───────────────────────────────────────────────────────────────────────────────────────────│
    │                  ││──────┬─────┬─────┬─────┬─────┬─────┬─────┬───────────────────────────────────────────────────────│
    │affine_point      ││ 0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000000000000000000000000000000000000000000000000000000│
    │                  ││──────┴─────┴─────┴─────┴─────┴─────┴─────┴───────────────────────────────────────────────────────│
    │pop               ││                                                ┌─────────────────────────────────────────┐       │
    │                  ││────────────────────────────────────────────────┘                                         └───────│
    │push              ││      ┌─────────────────────────────────────────┐                                                 │
    │                  ││──────┘                                         └─────────────────────────────────────────────────│
    │                  ││──────┬─────┬─────┬─────┬─────┬─────┬─────┬───────────────────────────────────────────────────────│
    │scalar            ││ 0000 │0001 │0002 │0003 │0004 │0005 │0006 │0007                                                   │
    │                  ││──────┴─────┴─────┴─────┴─────┴─────┴─────┴───────────────────────────────────────────────────────│
    │                  ││────────────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────────────│
    │window            ││ 0          │1    │2    │3    │4    │5    │6    │0    │1    │2    │3    │4    │5    │6            │
    │                  ││────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────────────│
    │                  ││────────────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─│
    │affine_point_out  ││ 0000000000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0000.│0│
    │                  ││────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─│
    │all_windows_are_em││────────────┐                                                                             ┌───────│
    │                  ││            └─────────────────────────────────────────────────────────────────────────────┘       │
    │all_windows_have_s││                                                ┌─────┐                                           │
    │                  ││────────────────────────────────────────────────┘     └───────────────────────────────────────────│
    │                  ││────────────────────────────────────────────────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬───────│
    │scalar_out        ││ 0000                                           │0001 │0002 │0003 │0004 │0005 │0006 │0007 │0000   │
    │                  ││────────────────────────────────────────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴───────│
    │some_windows_are_f││                                                                                                  │
    │                  ││──────────────────────────────────────────────────────────────────────────────────────────────────│
    │                  ││────────────┬─────────────────────────────────────────┬───────────────────────────────────────────│
    │sf_0$LEVEL        ││ 0          │1                                        │0                                          │
    │                  ││────────────┴─────────────────────────────────────────┴───────────────────────────────────────────│
    │sf_0$i$clear      ││──────┐                                                                                           │
    │                  ││      └───────────────────────────────────────────────────────────────────────────────────────────│
    │sf_0$i$clock      ││                                                                                                  │
    │                  ││──────────────────────────────────────────────────────────────────────────────────────────────────│
    │sf_0$i$pop        ││                                                ┌─────────────────────────────────────────┐       │
    │                  ││────────────────────────────────────────────────┘                                         └───────│
    │sf_0$i$push       ││      ┌─────────────────────────────────────────┐                                                 │
    │                  ││──────┘                                         └─────────────────────────────────────────────────│
    │                  ││──────┬─────┬─────┬─────┬─────┬─────┬─────┬───────────────────────────────────────────────────────│
    │sf_0$i$scalar     ││ 0000 │0001 │0002 │0003 │0004 │0005 │0006 │0007                                                   │
    │                  ││──────┴─────┴─────┴─────┴─────┴─────┴─────┴───────────────────────────────────────────────────────│
    │                  ││────────────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────────────│
    │sf_0$i$window     ││ 0          │1    │2    │3    │4    │5    │6    │0    │1    │2    │3    │4    │5    │6            │
    │                  ││────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────────────│
    │sf_0$o$empty      ││────────────┐                                         ┌───────────────────────────────────────────│
    │                  ││            └─────────────────────────────────────────┘                                           │
    │sf_0$o$full       ││                                                                                                  │
    │                  ││──────────────────────────────────────────────────────────────────────────────────────────────────│
    │sf_0$o$not_empty  ││            ┌─────────────────────────────────────────┐                                           │
    │                  ││────────────┘                                         └───────────────────────────────────────────│
    │                  ││──────────────────────────────────────────────────────┬───────────────────────────────────────────│
    │sf_0$o$read_addres││ 0                                                    │1                                          │
    │                  ││──────────────────────────────────────────────────────┴───────────────────────────────────────────│
    │                  ││────────────┬─────────────────────────────────────────┬───────────────────────────────────────────│
    │sf_0$o$scalar     ││ 0000       │0001                                     │0000                                       │
    │                  ││────────────┴─────────────────────────────────────────┴───────────────────────────────────────────│
    │                  ││────────────┬─────────────────────────────────────────────────────────────────────────────────────│
    │sf_0$o$write_addre││ 0          │1                                                                                    │
    │                  ││────────────┴─────────────────────────────────────────────────────────────────────────────────────│
    │                  ││──────────────────┬─────────────────────────────────────────┬─────────────────────────────────────│
    │sf_1$LEVEL        ││ 0                │1                                        │0                                    │
    │                  ││──────────────────┴─────────────────────────────────────────┴─────────────────────────────────────│
    │sf_1$i$clear      ││──────┐                                                                                           │
    │                  ││      └───────────────────────────────────────────────────────────────────────────────────────────│
    │sf_1$i$clock      ││                                                                                                  │
    │                  ││──────────────────────────────────────────────────────────────────────────────────────────────────│
    │sf_1$i$pop        ││                                                ┌─────────────────────────────────────────┐       │
    │                  ││────────────────────────────────────────────────┘                                         └───────│
    │sf_1$i$push       ││      ┌─────────────────────────────────────────┐                                                 │
    │                  ││──────┘                                         └─────────────────────────────────────────────────│
    │                  ││──────┬─────┬─────┬─────┬─────┬─────┬─────┬───────────────────────────────────────────────────────│
    │sf_1$i$scalar     ││ 0000 │0001 │0002 │0003 │0004 │0005 │0006 │0007                                                   │
    │                  ││──────┴─────┴─────┴─────┴─────┴─────┴─────┴───────────────────────────────────────────────────────│
    │                  ││────────────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────────────│
    │sf_1$i$window     ││ 0          │1    │2    │3    │4    │5    │6    │0    │1    │2    │3    │4    │5    │6            │
    │                  ││────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────────────│
    │sf_1$o$empty      ││──────────────────┐                                         ┌─────────────────────────────────────│
    │                  ││                  └─────────────────────────────────────────┘                                     │
    │sf_1$o$full       ││                                                                                                  │
    │                  ││──────────────────────────────────────────────────────────────────────────────────────────────────│
    │sf_1$o$not_empty  ││                  ┌─────────────────────────────────────────┐                                     │
    │                  ││──────────────────┘                                         └─────────────────────────────────────│
    │                  ││────────────────────────────────────────────────────────────┬─────────────────────────────────────│
    │sf_1$o$read_addres││ 0                                                          │1                                    │
    │                  ││────────────────────────────────────────────────────────────┴─────────────────────────────────────│
    │                  ││──────────────────┬─────────────────────────────────────────┬─────────────────────────────────────│
    │sf_1$o$scalar     ││ 0000             │0002                                     │0000                                 │
    │                  ││──────────────────┴─────────────────────────────────────────┴─────────────────────────────────────│
    │                  ││──────────────────┬───────────────────────────────────────────────────────────────────────────────│
    │sf_1$o$write_addre││ 0                │1                                                                              │
    │                  ││──────────────────┴───────────────────────────────────────────────────────────────────────────────│
    │                  ││────────────────────────┬─────────────────────────────────────────┬───────────────────────────────│
    │sf_2$LEVEL        ││ 0                      │1                                        │0                              │
    │                  ││────────────────────────┴─────────────────────────────────────────┴───────────────────────────────│
    │sf_2$i$clear      ││──────┐                                                                                           │
    │                  ││      └───────────────────────────────────────────────────────────────────────────────────────────│
    │sf_2$i$clock      ││                                                                                                  │
    │                  ││──────────────────────────────────────────────────────────────────────────────────────────────────│
    │sf_2$i$pop        ││                                                ┌─────────────────────────────────────────┐       │
    │                  ││────────────────────────────────────────────────┘                                         └───────│
    │sf_2$i$push       ││      ┌─────────────────────────────────────────┐                                                 │
    │                  ││──────┘                                         └─────────────────────────────────────────────────│
    │                  ││──────┬─────┬─────┬─────┬─────┬─────┬─────┬───────────────────────────────────────────────────────│
    │sf_2$i$scalar     ││ 0000 │0001 │0002 │0003 │0004 │0005 │0006 │0007                                                   │
    │                  ││──────┴─────┴─────┴─────┴─────┴─────┴─────┴───────────────────────────────────────────────────────│
    │                  ││────────────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────────────│
    │sf_2$i$window     ││ 0          │1    │2    │3    │4    │5    │6    │0    │1    │2    │3    │4    │5    │6            │
    │                  ││────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────────────│
    │sf_2$o$empty      ││────────────────────────┐                                         ┌───────────────────────────────│
    │                  ││                        └─────────────────────────────────────────┘                               │
    │sf_2$o$full       ││                                                                                                  │
    │                  ││──────────────────────────────────────────────────────────────────────────────────────────────────│
    │sf_2$o$not_empty  ││                        ┌─────────────────────────────────────────┐                               │
    │                  ││────────────────────────┘                                         └───────────────────────────────│
    │                  ││──────────────────────────────────────────────────────────────────┬───────────────────────────────│
    │sf_2$o$read_addres││ 0                                                                │1                              │
    └──────────────────┘└──────────────────────────────────────────────────────────────────────────────────────────────────┘ |}]
;;