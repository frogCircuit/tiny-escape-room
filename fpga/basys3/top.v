/*
 * Basys 3 board wrapper for tt_um_tiny_escape_room. NOT part of the Tiny Tapeout
 * submission; all board glue lives here.
 *
 *   sw[15:8]     -> ui_in[7:0]  (SW8 = bit 0 ... SW15 = bit 7; SW4 is dead on the author's board)
 *   btnC         -> uio[0] submit (debounced)
 *   btnR         -> uio[2] serial clock (debounced; one press = one rising edge)
 *   SW0          -> uio[1] serial data
 *   SW1          -> step mode: the design clock follows btnU (press = high, release = low)
 *   SW2          -> slow mode: about 10 Hz, so a human can time room 4's busy pin
 *   btnU         -> manual clock in step mode (room 3 needs single-stepping)
 *   btnD         -> reset (hold it; in step mode also step the clock so the reset is seen)
 *   JA4..JA10    -> uio[3..7] outputs (busy, serial out, buzzer, door, wrong)
 *   right digit  -> uo_out (the display is active-low and multiplexed, so segments are
 *                   inverted and the digits are scanned); the next digit to the left lights
 *                   segment g during a wrong-code flash
 *   led[7:0]     -> mirror SW8..SW15, or the room 4 ANSWER KEY while SW3 is up (see below)
 *   led[13:8]    -> uio_out[5:0] (LED11 = busy,
 *   LED12 = serial out, LED13 = buzzer)   led[14] -> door pulse, stretched
 *   led[15]      -> the design clock (see it move in step and slow mode)
 *
 * ANSWER KEY (wrapper-only test aid, off by default, not part of the design): the wrapper keeps
 * a copy of the design's free counter, captures the seed when the first door opens, and with
 * SW3 up shows password byte P[i] on LED0..LED7 (LED0 = bit 0). i is set by SW6 (bit 1) and
 * SW5 (bit 0). P[i] = (seed_hi ^ 0x5C) + i * 0x11. Solving room 4 by timing instead stays
 * possible: watch LED11 in slow mode.
 *
 * The 100 MHz board clock is divided to the demo-board rate (CLK_HALF sets the half
 * period in board cycles: 50 -> 1 MHz). The Pmod serial inputs are not used: a floating
 * pin fires phantom submits.
 */
`default_nettype none

module top #(
    parameter CLK_HALF        = 50,          // 100 MHz / (2*50) = 1 MHz
    parameter SLOW_HALF       = 5_000_000,   // 100 MHz / (2*5M) = 10 Hz
    parameter DEBOUNCE_CYCLES = 2_000_000,   // 20 ms at 100 MHz
    parameter STRETCH_CYCLES  = 20_000_000,  // 0.2 s at 100 MHz
    parameter SCAN_BIT        = 15,          // display scan rate: 100 MHz / 2^(SCAN_BIT+1) per digit
    parameter TICK_BITS       = 16           // animation step = 2^TICK_BITS design clocks
) (
    input  wire        clk,
    input  wire [15:8] sw,
    input  wire [2:0]  mode_sw,   // SW0 data, SW1 step mode, SW2 slow mode
    input  wire        key_sw,    // SW3: show the room 4 answer key on the LEDs
    input  wire [1:0]  key_idx,   // SW6, SW5: which password byte
    input  wire        btnC,
    input  wire        btnD,
    input  wire        btnR,
    input  wire        btnU,
    output wire [7:3]  ja_out,    // JA4, JA7, JA8, JA9, JA10
    output reg  [6:0]  seg,
    output reg         dp,
    output reg  [3:0]  an,
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

  // ---- debounced buttons (wrapper only) ----
  wire submit_db, sclk_db, step_db;
  debounce #(.CYCLES(DEBOUNCE_CYCLES)) u_db_submit (.clk(clk), .in(btnC), .out(submit_db));
  debounce #(.CYCLES(DEBOUNCE_CYCLES)) u_db_sclk   (.clk(clk), .in(btnR), .out(sclk_db));
  debounce #(.CYCLES(DEBOUNCE_CYCLES)) u_db_step   (.clk(clk), .in(btnU), .out(step_db));

  // ---- mode switches, synchronised ----
  reg [1:0] step_sync = 2'b00, slow_sync = 2'b00;
  always @(posedge clk) begin
    step_sync <= {step_sync[0], mode_sw[1]};
    slow_sync <= {slow_sync[0], mode_sw[2]};
  end
  wire step_mode = step_sync[1];
  wire slow_mode = slow_sync[1];

  // ---- design clock: divided board clock, slow, or stepped by btnU ----
  localparam DIV_W = $clog2(SLOW_HALF);
  reg [DIV_W-1:0] div = 0;
  reg tt_clk_raw = 1'b0;
  wire [DIV_W-1:0] half = slow_mode ? SLOW_HALF - 1 : CLK_HALF - 1;
  always @(posedge clk) begin
    if (step_mode) begin
      div        <= 0;
      tt_clk_raw <= step_db;
    end else if (div >= half) begin
      div        <= 0;
      tt_clk_raw <= ~tt_clk_raw;
    end else begin
      div <= div + 1'b1;
    end
  end
  wire tt_clk;
  BUFG u_bufg (.I(tt_clk_raw), .O(tt_clk));

  // ---- the design under test ----
  wire [7:0] uo_out, uio_out, uio_oe;
  tt_um_tiny_escape_room #(.TICK_BITS(TICK_BITS)) dut (
      .ui_in  (sw[15:8]),
      .uo_out (uo_out),
      .uio_in ({5'b00000, sclk_db, mode_sw[0], submit_db}),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (1'b1),
      .clk    (tt_clk),
      .rst_n  (rst_n)
  );

  assign ja_out = uio_out[7:3];

  // ---- LEDs: stretch the one-microsecond door pulse so it can be seen ----
  reg [$clog2(STRETCH_CYCLES+1)-1:0] door_cnt = 0, wrong_cnt = 0;
  always @(posedge clk) begin
    if (uio_out[6]) door_cnt <= STRETCH_CYCLES;
    else if (door_cnt != 0) door_cnt <= door_cnt - 1'b1;
    if (uio_out[7]) wrong_cnt <= STRETCH_CYCLES;
    else if (wrong_cnt != 0) wrong_cnt <= wrong_cnt - 1'b1;
  end

  // ---- room 4 answer key (wrapper only) ----
  // rcnt is a copy of the design's free counter (same clock, same reset). The design latches
  // seed <= counter on the edge where door0 is high; door_q (uio_out[6]) is high one cycle
  // later, when rcnt has moved on by one, so the seed is rcnt - 1.
  reg [15:0] rcnt = 16'd0;
  reg        seen_door = 1'b0;
  reg [7:0]  seed_hi_cap = 8'd0;
  wire [15:0] rcnt_m1 = rcnt - 16'd1;
  always @(posedge tt_clk) begin
    if (!rst_n) begin
      rcnt        <= 16'd0;
      seen_door   <= 1'b0;
      seed_hi_cap <= 8'd0;
    end else begin
      rcnt <= rcnt + 16'd1;
      if (uio_out[6] && !seen_door) begin
        seen_door   <= 1'b1;
        seed_hi_cap <= rcnt_m1[15:8];
      end
    end
  end
  wire [7:0] key = (seed_hi_cap ^ 8'h5C) + {2'b00, key_idx, 2'b00, key_idx};

  assign led = {tt_clk_raw, door_cnt != 0, uio_out[5:0],
                (key_sw & seen_door) ? key : sw[15:8]};

  // ---- display, time-multiplexed (active-low segments and anodes) ----
  // Right digit: the room number. Next digit to the left: only segment g, lit
  // while a wrong-code flash is stretched (red segments, easy to tell from the
  // green LEDs).
  wire wrong_on = (wrong_cnt != 0);
  reg [SCAN_BIT:0] scan = 0;
  always @(posedge clk) begin
    scan <= scan + 1'b1;
    if (!scan[SCAN_BIT]) begin
      seg <= ~uo_out[6:0];
      dp  <= ~uo_out[7];
      an  <= 4'b1110;
    end else begin
      seg <= ~7'b1000000;                    // g only
      dp  <= 1'b1;
      an  <= wrong_on ? 4'b1101 : 4'b1111;   // blank unless flashing
    end
  end

  wire _unused = &{uio_oe, 1'b0};
endmodule
