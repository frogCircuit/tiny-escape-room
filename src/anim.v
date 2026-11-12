/*
 * Hardware idea: a tiny animation player. A mode register and a step counter walk
 * through a frame table: a door opening chases one segment around a to f twice, a
 * wrong code blinks every segment twice, and after reset there is one short chase.
 * Otherwise the display just shows the room digit (with the decimal point lit after
 * a door opened, until the next try). The buzzer pin gets a tone taken straight
 * from free-running counter bits: a two-note chime for a door, a low buzz for a
 * wrong code, silence otherwise. The step tick is the counter's terminal count, so
 * one step lasts 2^TICK_BITS clocks. Animations never gate any input.
 */
`default_nettype none

module anim #(
    parameter TICK_BITS = 16         // one animation step = 2^TICK_BITS clocks
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] free_cnt,
    input  wire        submit,       // a new try clears the decimal point
    input  wire        door,         // pulse: a door opened
    input  wire        wrong,        // pulse: wrong code
    input  wire [6:0]  idle_seg,     // the room digit, segments g..a (active high)
    output reg  [7:0]  seg_out,      // {dp, g..a}
    output wire        buzzer
);
  localparam [1:0] IDLE = 2'd0, DOOR = 2'd1, WRONG = 2'd2;

  wire tick = &free_cnt[TICK_BITS-1:0];

  reg [1:0] mode;
  reg [2:0] step;
  reg       lap;       // second lap of the chase
  reg       dp_flag;   // decimal point after a door opened
  reg       quiet;     // the reset chase makes no sound

  always @(posedge clk) begin
    if (!rst_n) begin
      mode    <= DOOR;     // short chase after reset: one lap, silent
      step    <= 3'd0;
      lap     <= 1'b1;
      dp_flag <= 1'b0;
      quiet   <= 1'b1;
    end else begin
      if (submit) dp_flag <= 1'b0;
      if (door) begin
        mode <= DOOR; step <= 3'd0; lap <= 1'b0; dp_flag <= 1'b0; quiet <= 1'b0;
      end else if (wrong) begin
        mode <= WRONG; step <= 3'd0; quiet <= 1'b0;
      end else if (tick) begin
        case (mode)
          DOOR: begin
            if (step == 3'd5) begin
              step <= 3'd0;
              if (lap) begin mode <= IDLE; dp_flag <= ~quiet; end
              else lap <= 1'b1;
            end else step <= step + 3'd1;
          end
          WRONG: begin
            if (step == 3'd7) mode <= IDLE;
            else step <= step + 3'd1;
          end
          default: ;
        endcase
      end
    end
  end

  always @* begin
    case (mode)
      DOOR:    seg_out = {1'b0, 7'd1 << step};              // one segment, a..f
      WRONG:   seg_out = step[1] ? 8'h00 : 8'hFF;           // blink twice (dp too)
      default: seg_out = {dp_flag, idle_seg};
    endcase
  end

  // Tones from free counter bits (about 2 kHz and 1 kHz, and 250 Hz, at a 1 MHz clock)
  assign buzzer = ~quiet & ((mode == DOOR)  ? (lap ? free_cnt[9] : free_cnt[8]) :
                            (mode == WRONG) ? free_cnt[11] : 1'b0);
endmodule
