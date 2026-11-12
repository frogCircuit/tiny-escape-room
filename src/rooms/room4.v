/*
 * Room 4, Guard. Hardware idea: a side channel. The player pushes four bytes
 * (one per submit) into the shared register; a loop then checks one byte per
 * step against the password, waiting 16 cycles per byte with busy high, and stops
 * at the first mismatch. How long busy stays high leaks how many leading bytes
 * were right.
 */
`default_nettype none

module room4 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        submit,
    input  wire        en,
    input  wire [31:0] shift_q,      // four entered bytes, first byte in [31:24]
    input  wire        match,        // cur_byte == P[idx], from the shared comparator
    output wire        load_byte,    // push ui_in into the shared register
    output wire [7:0]  cur_byte,     // byte under test, for the shared comparator
    output reg  [1:0]  idx,
    output reg         busy,
    output wire        door_open,
    output wire        wrong
);
  reg [1:0] cnt;    // bytes entered so far
  reg [3:0] d;      // delay counter within one byte

  wire act  = submit & en & ~busy;     // submits are ignored while the loop runs
  wire last = &d;                      // 16th cycle of this byte's delay: compare now

  assign load_byte = act;
  assign cur_byte  = shift_q[31 - 8 * idx -: 8];
  assign door_open = busy & last & match & (idx == 2'd3);
  assign wrong     = busy & last & ~match;

  always @(posedge clk) begin
    if (!rst_n) begin
      cnt  <= 2'd0;
      idx  <= 2'd0;
      d    <= 4'd0;
      busy <= 1'b0;
    end else if (act) begin
      if (cnt == 2'd3) begin           // fourth byte in: start checking
        cnt  <= 2'd0;
        idx  <= 2'd0;
        d    <= 4'd0;
        busy <= 1'b1;
      end else begin
        cnt <= cnt + 2'd1;
      end
    end else if (busy) begin
      d <= d + 4'd1;
      if (last) begin
        if (match && idx != 2'd3) idx <= idx + 2'd1;
        else busy <= 1'b0;             // mismatch (wrong) or all four right (door)
      end
    end
  end
endmodule
