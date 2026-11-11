/*
 * Basys 3 board wrapper for tt_um_tiny_escape_room. NOT part of the Tiny Tapeout
 * submission; all board glue lives here.
 *
 *   sw[7:0]      -> ui_in           btnC (debounced) or JA1 -> uio[0] submit
 *   btnD         -> reset (active-low rst_n inside)
 *   JA1..JA3     -> uio[0..2] inputs (submit, serial data, serial clock)
 *   JA4..JA10    -> uio[3..7] outputs (busy, serial out, buzzer, door, wrong)
 *   right digit  -> uo_out (the Basys display is active-low and multiplexed,
 *                   so segments are inverted and only one anode is held on)
 *   led[15]/[14] -> wrong / door pulses, stretched so a human can see them
 *   led[13:8]    -> uio_out[5:0] directly; led[7:0] mirror the switches
 *
 * The 100 MHz board clock is divided to the demo-board rate (CLK_HALF sets
 * the half period in board cycles: 50 -> 1 MHz).
 */
`default_nettype none

module top #(
    parameter CLK_HALF        = 50,          // 100 MHz / (2*50) = 1 MHz
    parameter DEBOUNCE_CYCLES = 2_000_000,   // 20 ms at 100 MHz
    parameter STRETCH_CYCLES  = 20_000_000   // 0.2 s at 100 MHz
) (
    input  wire        clk,
    input  wire [7:0]  sw,
    input  wire        btnC,
    input  wire        btnD,
    input  wire [2:0]  ja_in,    // JA1, JA2, JA3
    output wire [7:3]  ja_out,   // JA4, JA7, JA8, JA9, JA10
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    output wire [15:0] led
);

  // ---- power-on reset plus reset button, synchronised to the board clock ----
  reg [7:0] por = 8'd0;
  reg [1:0] rst_sync = 2'b00;
  always @(posedge clk) begin
    if (por != 8'hFF) por <= por + 8'd1;
    rst_sync <= {rst_sync[0], btnD};
  end
  wire rst_n = (por == 8'hFF) & ~rst_sync[1];

  // ---- divide the board clock to the demo-board rate ----
  reg [$clog2(CLK_HALF)-1:0] div = 0;
  reg tt_clk_raw = 1'b0;
  always @(posedge clk) begin
    if (div == CLK_HALF - 1) begin
      div        <= 0;
      tt_clk_raw <= ~tt_clk_raw;
    end else begin
      div <= div + 1'b1;
    end
  end
  wire tt_clk;
  BUFG u_bufg (.I(tt_clk_raw), .O(tt_clk));

  // ---- debounce the submit button (wrapper only) ----
  reg [1:0] btn_sync = 2'b00;
  reg [$clog2(DEBOUNCE_CYCLES+1)-1:0] db_cnt = 0;
  reg btn_db = 1'b0;
  always @(posedge clk) begin
    btn_sync <= {btn_sync[0], btnC};
    if (btn_sync[1] == btn_db) db_cnt <= 0;
    else if (db_cnt == DEBOUNCE_CYCLES) begin
      btn_db <= btn_sync[1];
      db_cnt <= 0;
    end else db_cnt <= db_cnt + 1'b1;
  end

  // ---- the design under test ----
  wire [7:0] uo_out, uio_out, uio_oe;
  tt_um_tiny_escape_room dut (
      .ui_in  (sw),
      .uo_out (uo_out),
      .uio_in ({5'b00000, ja_in[2:1], btn_db | ja_in[0]}),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (1'b1),
      .clk    (tt_clk),
      .rst_n  (rst_n)
  );

  // ---- display: active-low, rightmost digit only ----
  assign seg = ~uo_out[6:0];
  assign dp  = ~uo_out[7];
  assign an  = 4'b1110;

  assign ja_out = uio_out[7:3];

  // ---- LEDs: stretch the one-microsecond pulses so they can be seen ----
  reg [$clog2(STRETCH_CYCLES+1)-1:0] door_cnt = 0, wrong_cnt = 0;
  always @(posedge clk) begin
    if (uio_out[6]) door_cnt <= STRETCH_CYCLES;
    else if (door_cnt != 0) door_cnt <= door_cnt - 1'b1;
    if (uio_out[7]) wrong_cnt <= STRETCH_CYCLES;
    else if (wrong_cnt != 0) wrong_cnt <= wrong_cnt - 1'b1;
  end

  assign led = {wrong_cnt != 0, door_cnt != 0, uio_out[5:0], sw};

  wire _unused = &{uio_oe, 1'b0};
endmodule
