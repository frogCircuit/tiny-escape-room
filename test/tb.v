`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // Replace tt_um_tiny_escape_room with your module name:
  tt_um_tiny_escape_room user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

`ifndef GL_TEST
  // Unit-test access to blocks the top level cannot fully exercise yet.
  // (Not present in the gate-level netlist, so excluded from GL tests.)
  reg  [3:0]  disp_digit;
  reg         disp_dp;
  wire [7:0]  disp_out;
  display u_disp_test (.digit(disp_digit), .dp(disp_dp), .seg_out(disp_out));

  reg         sr_shift_en;
  reg         sr_shift_in;
  reg         sr_load_byte;
  reg  [7:0]  sr_byte_in;
  wire [31:0] sr_q;
  reg  [15:0] sr_a, sr_b;
  wire        sr_match;
  shared_regs u_shared_test (
      .clk(clk), .rst_n(rst_n),
      .shift_en(sr_shift_en), .shift_in(sr_shift_in),
      .load_byte(sr_load_byte), .byte_in(sr_byte_in), .shift_q(sr_q),
      .cmp_a(sr_a), .cmp_b(sr_b), .match(sr_match)
  );
`endif

endmodule
