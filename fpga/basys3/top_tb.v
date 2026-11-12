// Wrapper smoke test: plays rooms 0 to 2 through the board glue (debounce, serial
// controls, display scan), then checks reset and step mode.
// Run: iverilog -g2012 -o /tmp/top_tb top_tb.v top.v debounce.v rtl/*.v rtl/rooms/*.v && vvp /tmp/top_tb
`default_nettype none
`timescale 1ns / 1ps

module BUFG (input wire I, output wire O);  // simulation stand-in for the Xilinx primitive
  assign O = I;
endmodule

module top_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg [15:8] sw = 0;
  reg [2:0] mode_sw = 0;
  reg btnC = 0, btnD = 0, btnR = 0, btnU = 0;
  wire [6:0] seg; wire dp; wire [3:0] an; wire [15:0] led; wire [7:3] ja_out;

  top #(.CLK_HALF(2), .SLOW_HALF(8), .DEBOUNCE_CYCLES(40), .STRETCH_CYCLES(800),
        .SCAN_BIT(3), .TICK_BITS(3)) dut (
      .clk(clk), .sw(sw), .mode_sw(mode_sw), .btnC(btnC), .btnD(btnD), .btnR(btnR),
      .btnU(btnU), .ja_out(ja_out), .seg(seg), .dp(dp), .an(an), .led(led));

  // active-low segment patterns for digits 0..3 (~{g,f,e,d,c,b,a})
  function [6:0] digit_seg(input integer d);
    case (d)
      0: digit_seg = ~7'b0111111;
      1: digit_seg = ~7'b0000110;
      2: digit_seg = ~7'b1011011;
      default: digit_seg = ~7'b1001111;
    endcase
  endfunction

  integer errors = 0;

  // the display is multiplexed: wait for the room digit's turn, then check it
  task expect_digit(input integer d, input dp_lit);
    integer n;
    begin
      n = 0;
      while (an !== 4'b1110 && n < 100) begin @(posedge clk); n = n + 1; end
      if (seg !== digit_seg(d) || dp !== ~dp_lit) begin
        $display("FAIL: expected digit %0d dp_lit=%0d, seg=%b dp=%b", d, dp_lit, seg, dp);
        errors = errors + 1;
      end else $display("ok: digit %0d shown, dp %s", d, dp_lit ? "lit" : "off");
    end
  endtask

  // a wrong code must light only segment g of the next digit while stretched
  task expect_wrong_flash(input integer want);
    integer n; reg seen;
    begin
      n = 0; seen = 0;
      while (n < 100) begin
        @(posedge clk); n = n + 1;
        if (an === 4'b1101 && seg === 7'b0111111) seen = 1;
      end
      if (seen !== want[0]) begin
        $display("FAIL: wrong-flash seen=%0d, expected %0d", seen, want);
        errors = errors + 1;
      end else $display("ok: wrong flash %s", want ? "shown on next digit (g)" : "absent");
    end
  endtask

  task press(input [7:0] code);          // switches, then the submit button
    begin sw = code; #200; btnC = 1; #1500; btnC = 0; #1000; end
  endtask

  task serial_bit(input b);              // data on SW0, one press of btnR = one clock edge
    begin mode_sw[0] = b; #200; btnR = 1; #1000; btnR = 0; #800; end
  endtask

  task send16(input [15:0] v);
    integer i;
    begin for (i = 15; i >= 0; i = i - 1) serial_bit(v[i]); mode_sw[0] = 0; end
  endtask

  initial begin
    #8000;                               // power-on reset, then the reset chase
    expect_digit(0, 0);
    expect_wrong_flash(0);
    press(8'h00);  expect_wrong_flash(1);  #6000;  expect_digit(0, 0);  // wrong code
    #8000; expect_wrong_flash(0);        // the flash has ended
    press(8'h3C);  #6000;  expect_digit(1, 1);                           // room 0 -> door, dp lit
    press(8'h11); press(8'h6E); press(8'hA4); press(8'hD9);
    #6000;  expect_digit(2, 1);                                          // room 1 -> door
    send16(16'hB3A5);                    // room 2: the frame over the serial controls
    press(8'h00);  #6000;  expect_digit(3, 1);
    btnD = 1; #1000; btnD = 0; #6000;    // reset button
    expect_digit(0, 0);
    // step mode: the design clock follows btnU and nothing else
    mode_sw[1] = 1; #1000;
    if (led[15] !== 1'b0) begin $display("FAIL: step mode clock not low"); errors = errors + 1; end
    #3000;
    if (led[15] !== 1'b0) begin $display("FAIL: step mode clock moved on its own"); errors = errors + 1; end
    btnU = 1; #1500;
    if (led[15] !== 1'b1) begin $display("FAIL: btnU did not raise the clock"); errors = errors + 1; end
    btnU = 0; #1500;
    if (led[15] !== 1'b0) begin $display("FAIL: btnU release did not lower the clock"); errors = errors + 1; end
    else $display("ok: step mode follows btnU");
    if (errors == 0) $display("WRAPPER PASS"); else $display("WRAPPER FAIL");
    $finish;
  end
endmodule
