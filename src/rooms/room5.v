/*
 * Room 5, Hatch. Hardware idea: a hidden debug port. A bit counter splits the
 * serial stream into bytes. The undocumented byte 0xA5 connects a 16-bit status
 * word to the serial output pin, one bit per serial clock; after the 16 bits
 * the hatch waits for the second command 0x5A (the low byte of that same word).
 * A submit resets the framing so a mis-aligned stream can be recovered.
 */
`default_nettype none

module room5 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       submit,
    input  wire       en,
    input  wire       strobe,     // one cycle per serial clock rising edge
    input  wire       match,      // received byte == the byte expected in this state
    input  wire [3:0] room,
    output reg  [1:0] state,      // 0 wait 0xA5, 1 dumping, 2 wait 0x5A
    output wire       door_open,
    output wire       wrong,
    output wire       ser_out
);
  reg [2:0] bitcnt;
  reg [3:0] dcnt;
  reg       rx_done;              // a full byte is in the register this cycle

  wire dumping = (state == 2'd1);
  wire clk_ev  = strobe & en;

  // The status word: room counter, hatch state and the unlock byte. It holds no seed bits.
  wire [15:0] word = {room, 2'b00, state, 8'h5A};
  assign ser_out = dumping & word[15 - dcnt];

  assign door_open = en & rx_done & (state == 2'd2) & match;
  assign wrong     = en & rx_done & ~match & ((state == 2'd0) | (state == 2'd2));

  always @(posedge clk) begin
    if (!rst_n) begin
      bitcnt  <= 3'd0;
      dcnt    <= 4'd0;
      state   <= 2'd0;
      rx_done <= 1'b0;
    end else begin
      rx_done <= 1'b0;
      if (rx_done) begin
        if (state == 2'd0 && match) begin
          state <= 2'd1;
          dcnt  <= 4'd0;
        end else if (state == 2'd2 && !match) begin
          state <= 2'd0;
        end
      end
      if (clk_ev) begin
        if (dumping) begin
          dcnt <= dcnt + 4'd1;
          if (dcnt == 4'd15) begin
            state  <= 2'd2;
            bitcnt <= 3'd0;
          end
        end else begin
          bitcnt <= bitcnt + 3'd1;
          if (bitcnt == 3'd7) rx_done <= 1'b1;
        end
      end
      if (en & submit) begin          // resync: forget a partial byte and start over
        bitcnt <= 3'd0;
        state  <= 2'd0;
        dcnt   <= 4'd0;
      end
    end
  end
endmodule
