/*
 * Hardware idea: a 2-flop synchronizer plus a "previous" flop turns the
 * asynchronous submit button into a clean one-cycle pulse on its rising edge.
 */
`default_nettype none

module submit_edge (
    input  wire clk,
    input  wire rst_n,
    input  wire btn,    // raw submit button (uio[0])
    output wire pulse   // high for exactly one clock per button press
);
  reg sync1, sync2, prev;

  always @(posedge clk) begin
    if (!rst_n) begin
      sync1 <= 1'b0;
      sync2 <= 1'b0;
      prev  <= 1'b0;
    end else begin
      sync1 <= btn;
      sync2 <= sync1;
      prev  <= sync2;
    end
  end

  assign pulse = sync2 & ~prev;
endmodule
