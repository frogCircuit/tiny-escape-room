/*
 * Hardware idea: the datapath every room shares. One 32-bit shift register
 * (new bit enters at bit 0, so the first bit in ends up as the MSB after 32
 * shifts) and one 8-bit equality comparator. Rooms 0 and 1 only use the
 * comparator; the shift register is first used by room 2.
 */
`default_nettype none

module shared_regs (
    input  wire        clk,
    input  wire        rst_n,
    // shift register
    input  wire        shift_en,
    input  wire        shift_in,
    output reg  [31:0] shift_q,
    // comparator
    input  wire [7:0]  cmp_a,
    input  wire [7:0]  cmp_b,
    output wire        match
);
  always @(posedge clk) begin
    if (!rst_n) shift_q <= 32'd0;
    else if (shift_en) shift_q <= {shift_q[30:0], shift_in};
  end

  assign match = (cmp_a == cmp_b);
endmodule
