/*
 * Room 1, Corridor. Hardware idea: a 3-bit state register steps through four
 * codes. Any wrong code falls back to state 0, except one deliberate shortcut:
 * code S1 in state 1 jumps straight to state 3 (waiting for the last code).
 */
`default_nettype none

module room1 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       submit,
    input  wire       en,
    input  wire       match,      // ui_in == expected code for this state
    input  wire [7:0] code,       // ui_in, for the shortcut compare
    input  wire [7:0] s1,         // shortcut code
    output wire       door_open,
    output wire       wrong,
    output reg  [2:0] state
);
  wire act      = submit & en;
  wire shortcut = (code == s1) && (state == 3'd1);

  assign door_open = act & match & (state == 3'd3);
  assign wrong     = act & ~match & ~shortcut;

  always @(posedge clk) begin
    if (!rst_n) state <= 3'd0;
    else if (act) begin
      if (match) state <= (state == 3'd3) ? 3'd0 : state + 3'd1;
      else if (shortcut) state <= 3'd3;
      else state <= 3'd0;
    end
  end
endmodule
