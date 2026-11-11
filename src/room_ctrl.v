/*
 * Hardware idea: a 4-bit room counter (0 to 9) is the only progress gate.
 * A door_open pulse moves it forward one room; reset sends it back to room 0.
 * Room N is enabled exactly when the counter equals N.
 */
`default_nettype none

module room_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       door_open,   // one-cycle pulse from the active room
    output reg  [3:0] room,
    output wire [9:0] en           // one-hot: en[N] = (room == N)
);
  always @(posedge clk) begin
    if (!rst_n) room <= 4'd0;
    else if (door_open && room != 4'd9) room <= room + 4'd1;
  end

  assign en = 10'b1 << room;
endmodule
