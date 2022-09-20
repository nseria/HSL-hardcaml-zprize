open Core
open Hardcaml
open Hardcaml_waveterm
open Msm_pippenger

module Make (Config : Msm_pippenger.Config.S) = struct
  module Utils = Utils.Make (Config)
  module Top = Top.Make (Config)
  module Kernel = Kernel_for_vitis.Make (Config)
  module I = Kernel.I
  module O = Kernel.O
  module I_rules = Display_rules.With_interface (Kernel.I)
  module O_rules = Display_rules.With_interface (Kernel.O)
  module Sim = Cyclesim.With_interface (I) (O)

  let create_sim verilator () =
    let scope =
      Scope.create ~flatten_design:true ~auto_label_hierarchical_ports:true ()
    in
    let create = Kernel.hierarchical ~build_mode:Simulation scope in
    if verilator
    then
      let module V = Hardcaml_verilator.With_interface (Kernel.I) (Kernel.O) in
      V.create ~clock_names:[ "clock" ] ~cache_dir:"/tmp/kernel/" ~verbose:true create
    else Sim.create ~config:Cyclesim.Config.trace_all create
  ;;

  let display_rules =
    List.concat [ I_rules.default (); O_rules.default (); [ Display_rule.default ] ]
  ;;

  type result =
    { waves : Waveform.t option
    ; points : Utils.window_bucket_point list
    ; inputs : Bits.t Utils.Msm_input.t array
    }

  type sim_and_waves =
    { sim : Sim.t
    ; waves : Waveform.t option
    }

  let create ~verilator ~waves =
    let sim = create_sim verilator () in
    let i = Cyclesim.inputs sim in
    i.ap_rst_n := Bits.gnd;
    Cyclesim.cycle sim;
    Cyclesim.cycle sim;
    i.ap_rst_n := Bits.vdd;
    Cyclesim.cycle sim;
    Cyclesim.cycle sim;
    Cyclesim.cycle sim;
    if waves
    then (
      let waves, sim = Waveform.create sim in
      { waves = Some waves; sim })
    else { waves = None; sim }
  ;;

  let aligned_to = 64
  let aligned_field_bits = Int.round_up Config.field_bits ~to_multiple_of:aligned_to

  let num_clocks_per_input =
    Int.round_up (Config.scalar_bits + (3 * aligned_field_bits)) ~to_multiple_of:512 / 512
  ;;

  let drop_t = false

  let num_clocks_per_output =
    Int.round_up ((if drop_t then 3 else 4) * aligned_field_bits) ~to_multiple_of:512
    / 512
  ;;

  module Input_aligned = struct
    type 'a t =
      { x : 'a [@bits aligned_field_bits]
      ; y : 'a [@bits aligned_field_bits]
      ; t : 'a [@bits aligned_field_bits]
      }
    [@@deriving sexp_of, hardcaml]
  end

  let run ?sim ?(waves = true) ~seed ~timeout ~verilator num_inputs () =
    let cycle_cnt = ref 0 in
    let sim_and_waves = Option.value sim ~default:(create ~verilator ~waves) in
    let sim = sim_and_waves.sim in
    let i, o = Cyclesim.inputs sim, Cyclesim.outputs sim in
    let inputs = Utils.random_inputs ~seed num_inputs in
    Cyclesim.cycle sim;
    i.fpga_to_host_dest.tready := Bits.vdd;
    for idx = 0 to num_inputs - 1 do
      let input = inputs.(idx) in
      let aligned_point =
        { Input_aligned.x = Bits.uresize input.affine_point_with_t.x aligned_field_bits
        ; Input_aligned.y = Bits.uresize input.affine_point_with_t.y aligned_field_bits
        ; Input_aligned.t = Bits.uresize input.affine_point_with_t.t aligned_field_bits
        }
      in
      let to_send = ref Bits.(input.scalar @: Input_aligned.Of_bits.pack aligned_point) in
      for beat = 0 to num_clocks_per_input - 1 do
        i.host_to_fpga.tdata := Bits.sel_bottom !to_send 512;
        i.host_to_fpga.tvalid := Bits.random ~width:1;
        if beat = num_clocks_per_input - 1 && idx = num_inputs - 1
        then i.host_to_fpga.tlast := Bits.vdd;
        if Bits.is_gnd !(i.host_to_fpga.tvalid) then Cyclesim.cycle sim;
        i.host_to_fpga.tvalid := Bits.vdd;
        cycle_cnt := 0;
        while Bits.is_gnd !(o.host_to_fpga_dest.tready) && !cycle_cnt < timeout do
          Int.incr cycle_cnt;
          Cyclesim.cycle sim
        done;
        Cyclesim.cycle sim;
        to_send := Bits.(srl !to_send 512)
      done;
      i.host_to_fpga.tvalid := Bits.gnd;
      for _ = 0 to Random.int 5 do
        Cyclesim.cycle sim
      done
    done;
    i.host_to_fpga.tlast := Bits.gnd;
    i.host_to_fpga.tvalid := Bits.gnd;
    Cyclesim.cycle sim;
    cycle_cnt := 0;
    while Bits.is_gnd !(o.fpga_to_host.tvalid) && !cycle_cnt < timeout do
      Int.incr cycle_cnt;
      Cyclesim.cycle sim
    done;
    cycle_cnt := 0;
    let word = ref 0 in
    let output_buffer_bits = num_clocks_per_output * 512 in
    let output_buffer = ref (Bits.zero output_buffer_bits) in
    let result_points = ref [] in
    let bucket = ref ((1 lsl Config.window_size_bits) - 1) in
    let window = ref 0 in
    let is_last = ref false in
    let field_bits = Config.field_bits in
    let aligned_field_bits = Int.round_up field_bits ~to_multiple_of:64 in
    print_s [%message "Expecting" (Top.num_result_points : int)];
    while (not !is_last) && !cycle_cnt < timeout do
      i.fpga_to_host_dest.tready := Bits.random ~width:1;
      Int.incr cycle_cnt;
      if Bits.is_vdd !(i.fpga_to_host_dest.tready) && Bits.is_vdd !(o.fpga_to_host.tvalid)
      then (
        (output_buffer
           := Bits.(
                sel_top (!(o.fpga_to_host.tdata) @: !output_buffer) output_buffer_bits));
        Int.incr word;
        if !word = num_clocks_per_output
        then (
          word := 0;
          is_last := Bits.to_bool !(o.fpga_to_host.tlast);
          let to_z b = Bits.to_constant b |> Constant.to_z ~signedness:Unsigned in
          let extended : Utils.Twisted_edwards.extended =
            { x = to_z (Bits.select !output_buffer (field_bits - 1) 0)
            ; y =
                to_z
                  (Bits.select
                     !output_buffer
                     (aligned_field_bits + field_bits - 1)
                     aligned_field_bits)
            ; t =
                (if drop_t
                then Z.zero
                else
                  to_z
                    (Bits.select
                       !output_buffer
                       ((3 * aligned_field_bits) + field_bits - 1)
                       (aligned_field_bits * 3)))
            ; z =
                to_z
                  (Bits.select
                     !output_buffer
                     ((2 * aligned_field_bits) + field_bits - 1)
                     (aligned_field_bits * 2))
            }
          in
          let affine = Utils.twisted_edwards_extended_to_affine ~has_t:true extended in
          result_points
            := { Utils.point = affine; bucket = !bucket; window = !window }
               :: !result_points;
          bucket
            := if !bucket = 1
               then (
                 Int.incr window;
                 let next_window_size_bits =
                   if !window = Top.num_windows - 1
                   then Top.last_window_size_bits
                   else Config.window_size_bits
                 in
                 (1 lsl next_window_size_bits) - 1)
               else !bucket - 1));
      Cyclesim.cycle sim
    done;
    print_s [%message "Got" (List.length !result_points : int)];
    let result =
      { waves = sim_and_waves.waves; points = List.rev !result_points; inputs }
    in
    let fpga_calculated_result = Utils.calculate_result_from_fpga result.points in
    let expected = Utils.expected inputs in
    if not (Ark_bls12_377_g1.equal_affine fpga_calculated_result expected)
    then
      print_s
        [%message
          "ERROR: Result points did not match!"
            (expected : Ark_bls12_377_g1.affine)
            (fpga_calculated_result : Ark_bls12_377_g1.affine)]
    else print_s [%message "PASS"];
    result
  ;;

  let run_test
    ?(waves = false)
    ?(seed = 0)
    ?(timeout = 10_000)
    ?(verilator = false)
    num_inputs
    =
    run ~waves ~seed ~timeout ~verilator num_inputs ()
  ;;
end

let%expect_test "Test over small input size" =
  let module Config = struct
    let field_bits = 377
    let scalar_bits = 12
    let controller_log_stall_fifo_depth = 2
    let window_size_bits = 3
    let ram_read_latency = 1
  end
  in
  let module Test = Make (Config) in
  let _result = Test.run_test 8 in
  [%expect
    {|
    (Expecting (Top.num_result_points 28))
    (Got ("List.length (!result_points)" 28))
    PASS |}]
;;

let test_back_to_back () =
  let module Config = struct
    let field_bits = 377
    let scalar_bits = 13
    let controller_log_stall_fifo_depth = 2
    let window_size_bits = 3
    let ram_read_latency = 1
  end
  in
  let module Test = Make (Config) in
  let sim = Test.create ~waves:true ~verilator:false in
  let _result0 = Test.run ~sim ~seed:0 ~timeout:1000 ~verilator:false 8 () in
  let _result1 : Test.result =
    Test.run ~sim ~seed:1 ~timeout:1000 ~verilator:false 8 ()
  in
  let result2 : Test.result = Test.run ~sim ~seed:2 ~timeout:1000 ~verilator:false 8 () in
  Option.value_exn result2.waves
;;

let%expect_test "Test multiple back-back runs" =
  let _waves = test_back_to_back () in
  [%expect
    {|
    (Expecting (Top.num_result_points 36))
    (Got ("List.length (!result_points)" 36))
    PASS
    (Expecting (Top.num_result_points 36))
    (Got ("List.length (!result_points)" 36))
    PASS
    (Expecting (Top.num_result_points 36))
    (Got ("List.length (!result_points)" 36))
    PASS |}]
;;