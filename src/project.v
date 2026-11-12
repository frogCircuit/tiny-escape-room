/*
 * Copyright (c) 2026 Fernando Valdez
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Escape Room, top level. Hardware idea: a room counter gates ten small
 * puzzles; they share one comparator and one shift register, and the display
 * shows which room is open. Rooms 0 to 5 so far.
 */

`default_nettype none

module tt_um_tiny_escape_room (
    input  wire [7:0] ui_in,    // Dedicated inputs: 8-bit DIP code and data
    output wire [7:0] uo_out,   // Dedicated outputs: seven-segment a..g, dp
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ---- pin plan (CLAUDE.md section 3) ----
  // uio[0] submit, uio[1] serial in, uio[2] serial clk (inputs)
  // uio[3] busy, [4] serial out, [5] buzzer, [6] door pulse, [7] wrong pulse (outputs)
  assign uio_oe = 8'b1111_1000;

  // ---- submit button -> one-cycle pulse ----
  wire submit;
  submit_edge u_submit (.clk(clk), .rst_n(rst_n), .btn(uio_in[0]), .pulse(submit));

  // ---- free-running counter and seed register ----
  wire [15:0] free_cnt;
  free_counter u_free (.clk(clk), .rst_n(rst_n), .count(free_cnt));

  reg [15:0] seed;  // written once per run, on the room 0 door_open edge

  // ---- room controller ----
  wire [3:0] room;
  wire [9:0] en;
  wire       door0, door1, door2, door3, door4, door5;
  wire       wrong0, wrong1, wrong2, wrong3, wrong4, wrong5;
  wire       door_open = door0 | door1 | door2 | door3 | door4 | door5;
  wire       wrong     = wrong0 | wrong1 | wrong2 | wrong3 | wrong4 | wrong5;
  room_ctrl u_room_ctrl (.clk(clk), .rst_n(rst_n), .door_open(door_open), .room(room), .en(en));

  always @(posedge clk) begin
    if (!rst_n) seed <= 16'd0;
    else if (door0) seed <= free_cnt;
  end

  // ---- serial input: strobe + data bit, shifted into the shared register in rooms 2 and 5 ----
  wire serial_strobe, serial_bit;
  serial_in u_serial (
      .clk(clk), .rst_n(rst_n), .sclk(uio_in[2]), .sdata(uio_in[1]),
      .strobe(serial_strobe), .bit_in(serial_bit)
  );

  // ---- constants, shared comparator and shift register ----
  wire [2:0]  r1_state;
  wire [1:0]  r4_idx, r5_state;
  wire [15:0] expected;
  wire [7:0]  s1;
  consts u_consts (
      .room(room), .r1_state(r1_state), .r4_idx(r4_idx), .seed_hi(seed[15:8]),
      .r5_state(r5_state), .expected(expected), .s1(s1)
  );

  wire        match, r4_load;
  wire [7:0]  r4_byte;
  wire [31:0] shift_q;
  // what the comparator looks at depends on the room
  wire [15:0] cmp_a = en[2] ? shift_q[15:0] :
                      en[4] ? {8'h00, r4_byte} :
                      en[5] ? {8'h00, shift_q[7:0]} : {8'h00, ui_in};
  shared_regs u_shared (
      .clk(clk), .rst_n(rst_n),
      .shift_en(serial_strobe & (en[2] | en[5])), .shift_in(serial_bit),
      .load_byte(r4_load), .byte_in(ui_in), .shift_q(shift_q),
      .cmp_a(cmp_a), .cmp_b(expected), .match(match)
  );

  // ---- rooms ----
  wire r4_busy, r5_ser_out;
  room0 u_room0 (.submit(submit), .en(en[0]), .match(match), .door_open(door0), .wrong(wrong0));
  room1 u_room1 (
      .clk(clk), .rst_n(rst_n), .submit(submit), .en(en[1]), .match(match),
      .code(ui_in), .s1(s1), .door_open(door1), .wrong(wrong1), .state(r1_state)
  );
  room2 u_room2 (.submit(submit), .en(en[2]), .match(match), .door_open(door2), .wrong(wrong2));
  room3 u_room3 (
      .clk(clk), .rst_n(rst_n), .submit(submit), .en(en[3]), .ui_hi(ui_in[7:4]),
      .door_open(door3), .wrong(wrong3)
  );
  room4 u_room4 (
      .clk(clk), .rst_n(rst_n), .submit(submit), .en(en[4]), .shift_q(shift_q),
      .match(match), .load_byte(r4_load), .cur_byte(r4_byte), .idx(r4_idx),
      .busy(r4_busy), .door_open(door4), .wrong(wrong4)
  );
  room5 u_room5 (
      .clk(clk), .rst_n(rst_n), .submit(submit), .en(en[5]), .strobe(serial_strobe),
      .match(match), .room(room), .state(r5_state), .door_open(door5), .wrong(wrong5),
      .ser_out(r5_ser_out)
  );

  // ---- display: room digit; decimal point stays off for now ----
  display u_display (.digit(room), .dp(1'b0), .seg_out(uo_out));

  // ---- registered one-cycle pulses for the optional companion board ----
  reg door_q, wrong_q;
  always @(posedge clk) begin
    if (!rst_n) begin
      door_q  <= 1'b0;
      wrong_q <= 1'b0;
    end else begin
      door_q  <= door_open;
      wrong_q <= wrong;
    end
  end

  assign uio_out = {wrong_q, door_q, 1'b0, r5_ser_out, r4_busy, 3'b000};

  // List all unused inputs to prevent warnings (seed[7:0] is read from room 6 on;
  // shift_q[31:16] from room 7 on)
  wire _unused = &{ena, uio_in[7:3], en[9:6], seed[7:0], shift_q[31:16], 1'b0};

endmodule
