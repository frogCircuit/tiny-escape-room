/*
 * Room 3, Vault. Hardware idea: a time-of-check to time-of-use race. On the
 * submit cycle T a flag latches "ui_in is small (< 0x10)"; one cycle later (T+1)
 * the store register loads ui_in if the flag is set, using whatever ui_in is
 * THEN. The door opens when the stored value is 0xF0 or more, so the player
 * must pass the check with a small value and change ui_in before the next edge.
 */
`default_nettype none

module room3 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       submit,
    input  wire       en,
    input  wire [3:0] ui_hi,    // ui_in[7:4]: the only bits this room looks at
    output wire       door_open,
    output wire       wrong
);
  wire act   = submit & en;
  wire is_small = (ui_hi == 4'h0);   // ui_in <  8'h10
  wire is_big = (ui_hi == 4'hF);   // ui_in >= 8'hF0

  reg       flag;    // the check result, from cycle T
  reg [3:0] store;   // high nibble of the value actually used, from cycle T+1 (only it is tested)

  always @(posedge clk) begin
    if (!rst_n) begin
      flag  <= 1'b0;
      store <= 4'h0;
    end else begin
      flag <= act & is_small;
      if (flag) store <= ui_hi;
    end
  end

  assign door_open = en & (store == 4'hF);   // stored value >= 8'hF0
  // Rejected at the check (not small), or stored but still too small.
  assign wrong = (act & ~is_small) | (flag & ~is_big);
endmodule
