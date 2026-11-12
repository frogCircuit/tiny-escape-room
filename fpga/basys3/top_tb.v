// Wrapper smoke test: plays rooms 0 and 1 through the board glue.
// Run: iverilog -g2012 -o /tmp/top_tb top_tb.v top.v rtl/*.v rtl/rooms/*.v && vvp /tmp/top_tb
`default_nettype none
`timescale 1ns / 1ps

module BUFG (input wire I, output wire O);  // simulation stand-in for the Xilinx primitive
  assign O = I;
endmodule

module top_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg [15:8] sw = 0;
  reg btnC = 0, btnD = 0;
  wire [6:0] seg; wire dp; wire [3:0] an; wire [15:0] led; wire [7:3] ja_out;

  top #(.CLK_HALF(2), .DEBOUNCE_CYCLES(40), .STRETCH_CYCLES(800), .SCAN_BIT(3)) dut (
      .clk(clk), .sw(sw), .btnC(btnC), .btnD(btnD),
      .ja_out(ja_out), .seg(seg), .dp(dp), .an(an), .led(led));

  // active-low segment patterns for digits 0..2 (~{g,f,e,d,c,b,a})
  function [6:0] digit_seg(input integer d);
    case (d)
      0: digit_seg = ~7'b0111111;
      1: digit_seg = ~7'b0000110;
      default: digit_seg = ~7'b1011011;
    endcase
  endfunction

  task press(input [7:0] code);
    begin
      sw = code; #2000; btnC = 1; #3000; btnC = 0; #500;
    end
  endtask

  integer errors = 0;

  // The display is multiplexed: wait for the room digit's turn, then check it.
  task expect_digit(input integer d);
    integer n;
    begin
      n = 0;
      while (an !== 4'b1110 && n < 100) begin @(posedge clk); n = n + 1; end
      if (seg !== digit_seg(d) || an !== 4'b1110 || dp !== 1'b1) begin
        $display("FAIL: expected digit %0d, seg=%b an=%b dp=%b", d, seg, an, dp);
        errors = errors + 1;
      end else $display("ok: digit %0d shown (seg=%b)", d, seg);
    end
  endtask

  // A wrong code must light only segment g of the next digit while stretched.
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

  initial begin
    #3000;
    expect_digit(0);
    expect_wrong_flash(0);
    press(8'h00);  expect_wrong_flash(1); expect_digit(0);   // wrong code
    #8000; expect_wrong_flash(0);   // flash has ended
    press(8'h3C);  expect_digit(1);   // K0
    press(8'h11); press(8'h6E); press(8'hA4); press(8'hD9);
    expect_digit(2);
    btnD = 1; #1000; btnD = 0; #1000;  // reset button
    expect_digit(0);
    if (errors == 0) $display("WRAPPER PASS"); else $display("WRAPPER FAIL");
    $finish;
  end
endmodule
