/*
 * Hardware idea: a combinational lookup (a small ROM plus one adder) that gives
 * the value the active room expects right now. All constants are public, on
 * purpose; only the room 4 password depends on the per-run seed.
 * Values are proposed first-pass constants.
 */
`default_nettype none

module consts (
    input  wire [3:0]  room,
    input  wire [2:0]  r1_state,   // room 1 FSM state
    input  wire [1:0]  r4_idx,     // room 4: which password byte is being checked
    input  wire [7:0]  seed_hi,    // room 4: high byte of the seed
    input  wire [1:0]  r5_state,   // room 5 hatch state
    output reg  [15:0] expected,   // value the shared comparator checks against
    output wire [7:0]  s1          // room 1 shortcut code
);
  localparam [7:0]  K0  = 8'h3C;
  localparam [7:0]  K1A = 8'h11;
  localparam [7:0]  K1B = 8'h6E;
  localparam [7:0]  K1C = 8'hA4;
  localparam [7:0]  K1D = 8'hD9;
  localparam [7:0]  S1  = 8'hFE;
  localparam [15:0] K2  = 16'hB3A5;  // room 2 frame
  localparam [7:0]  C1  = 8'h5C;     // room 4: P[i] = (seed_hi ^ C1) + i * 8'h11
  localparam [7:0]  CMD_DUMP   = 8'hA5;  // room 5: opens the debug port
  localparam [7:0]  CMD_UNLOCK = 8'h5A;  // room 5: second command

  assign s1 = S1;

  // i * 8'h11 for i = 0..3 is just {0,0,i,0,0,i}: wiring, no multiplier
  wire [7:0] p4 = (seed_hi ^ C1) + {2'b00, r4_idx, 2'b00, r4_idx};

  always @* begin
    expected = 16'h0000;
    case (room)
      4'd0: expected = {8'h00, K0};
      4'd1: begin
        case (r1_state)
          3'd0: expected = {8'h00, K1A};
          3'd1: expected = {8'h00, K1B};
          3'd2: expected = {8'h00, K1C};
          3'd3: expected = {8'h00, K1D};
          default: expected = 16'h0000;
        endcase
      end
      4'd2: expected = K2;
      4'd4: expected = {8'h00, p4};
      4'd5: expected = {8'h00, (r5_state == 2'd2) ? CMD_UNLOCK : CMD_DUMP};
      default: expected = 16'h0000;
    endcase
  end
endmodule
