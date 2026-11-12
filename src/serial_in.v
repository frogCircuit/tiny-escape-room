/*
 * Hardware idea: the serial clock and data pins are asynchronous, so each goes
 * through the same two-flop synchronizer (keeping them aligned). A rising edge
 * of the synchronized serial clock produces a one-cycle strobe, and the data bit
 * that goes with it is sampled on that strobe.
 */
`default_nettype none

module serial_in (
    input  wire clk,
    input  wire rst_n,
    input  wire sclk,     // serial clock in (uio[2])
    input  wire sdata,    // serial data in (uio[1])
    output wire strobe,   // one cycle per rising edge of sclk
    output wire bit_in    // data bit to shift in on that strobe
);
  reg c1, c2, cprev, d1, d2;

  always @(posedge clk) begin
    if (!rst_n) begin
      c1 <= 1'b0; c2 <= 1'b0; cprev <= 1'b0;
      d1 <= 1'b0; d2 <= 1'b0;
    end else begin
      c1 <= sclk;  c2 <= c1;  cprev <= c2;
      d1 <= sdata; d2 <= d1;
    end
  end

  assign strobe = c2 & ~cprev;
  assign bit_in = d2;
endmodule
