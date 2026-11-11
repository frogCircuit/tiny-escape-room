/*
 * Room 0, Cell door. Hardware idea: on a submit, the shared comparator says
 * whether ui_in equals K0. A match opens the door; anything else is a wrong
 * code. (The seed latch happens in the top level on the same door_open pulse.)
 */
`default_nettype none

module room0 (
    input  wire submit,
    input  wire en,
    input  wire match,       // ui_in == K0, from the shared comparator
    output wire door_open,
    output wire wrong
);
  wire act = submit & en;
  assign door_open = act & match;
  assign wrong     = act & ~match;
endmodule
