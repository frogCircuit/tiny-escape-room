/*
 * Room 2, Intercom. Hardware idea: the player clocks bits into the shared shift
 * register over the serial pins; a submit ends the frame, and the shared
 * comparator says whether the last 16 bits equal K2. A match opens the door.
 */
`default_nettype none

module room2 (
    input  wire submit,
    input  wire en,
    input  wire match,       // shift_q[15:0] == K2, from the shared comparator
    output wire door_open,
    output wire wrong
);
  wire act = submit & en;
  assign door_open = act & match;
  assign wrong     = act & ~match;
endmodule
