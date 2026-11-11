/*
 * Hardware idea: a combinational lookup (a small ROM) that gives the code the
 * active room expects right now. All values are public, on purpose.
 * Values are proposed first-pass constants.
 */
`default_nettype none

module consts (
    input  wire [3:0] room,
    input  wire [2:0] r1_state,   // room 1 FSM state
    output reg  [7:0] expected,   // code the shared comparator checks against
    output wire [7:0] s1          // room 1 shortcut code
);
  localparam [7:0] K0  = 8'h3C;
  localparam [7:0] K1A = 8'h11;
  localparam [7:0] K1B = 8'h6E;
  localparam [7:0] K1C = 8'hA4;
  localparam [7:0] K1D = 8'hD9;
  localparam [7:0] S1  = 8'hFE;

  assign s1 = S1;

  always @* begin
    expected = 8'h00;
    case (room)
      4'd0: expected = K0;
      4'd1: begin
        case (r1_state)
          3'd0: expected = K1A;
          3'd1: expected = K1B;
          3'd2: expected = K1C;
          3'd3: expected = K1D;
          default: expected = 8'h00;
        endcase
      end
      default: expected = 8'h00;
    endcase
  end
endmodule
