/*
 * Hardware idea: a 16-bit counter that ticks every clock and is only cleared
 * by reset. Human button timing decides which value gets captured as the seed.
 */
`default_nettype none

module free_counter (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [15:0] count
);
  always @(posedge clk) begin
    if (!rst_n) count <= 16'd0;
    else count <= count + 16'd1;
  end
endmodule
