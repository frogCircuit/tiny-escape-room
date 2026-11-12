# M2: first synthesis and go/no-go data

Tiny Tapeout flow (ttsky26d gds action), one 1x1 tile, 20 ns clock target,
60 percent placement density (`src/config.json`).

## What was measured

Design: room controller, shared datapath, seed register and free counter,
display, rooms 0 to 2. Measured on branch `m2-measure`, which adds a hook that
keeps the seed and the upper 16 shift-register bits alive (see below).

| Item | Value |
|---|---|
| Total cells (excluding fill and tap) | **516** |
| Utilization | **31.37 %** |
| Wire length | 9214 um |
| Flip-flops (`dfxtp`) | 88 |
| Real logic (combo, AND, OR, NOR, NAND, inverter, mux) | 266 |
| Physical overhead (delay/tie 97, clock delay 36, buffers 29) | 162 |
| Timing slack | **not seen yet** (not in the summary that was pasted) |

Source: the gds job summary, pasted by the owner. The branch is inferred from the
flip-flop count (88) matching a local yosys synthesis of the hooked design.

### Why the hook exists

Synthesis deletes logic nobody reads. Until rooms 4, 6 and 9 read the seed and
room 7 uses all 32 shift-register bits, a plain build drops about 32 flip-flops
and their logic. A local generic synthesis of the unhooked rooms 0 and 1 gave
141 cells and 12 flip-flops, which would have understated the design by half.
The hook (two XOR reductions onto idle pins) costs about 30 gates and stays on
the throwaway branch.

## Capacity

31.37 % for 516 cells is about 0.061 % per cell, so about 1650 cells at 100 %.

| Utilization | Cells | Note |
|---|---|---|
| 60 % | ~990 | the configured placement density, matches the "about 1000" budget |
| 80 % | ~1320 | the config comment says some users reached this, unverified for routing here |

This is an area estimate with an average cell size. Flip-flops are larger than
gates, so a flip-flop-heavy design uses more area per cell than this assumes.

## Extrapolation to ten rooms (estimates, not measurements)

Today: 354 logic and flop cells, minus about 30 hook gates, is about 324 for the
skeleton and rooms 0 to 2. The CLAUDE.md budget gave about 430 for the same
parts, so the skeleton came in roughly a quarter under budget.

Added cells still to build, with ranges (my estimates, from the hardware in
CLAUDE.md section 6):

| Block | Low | High | Main driver |
|---|---|---|---|
| Room 3 Vault | 25 | 40 | 8-bit store, flag, two compares |
| Room 4 Guard | 70 | 110 | byte index, 16-cycle delay counter, P[i] adder, busy |
| Room 5 Hatch | 40 | 70 | command decoder, state-to-serial shifter |
| Room 6 Radio | 70 | 100 | 16-bit LFSR with seed load, XOR, key compare |
| Room 7 Server closet | 150 | 300 | mixer rounds (adders), 16-bit lockout counter |
| Room 8 Archive | 50 | 80 | CRC-8, tag compare, 0xAD check |
| Room 9 Exit | 70 | 110 | entry register, flag shifter (less if the shared register is reused) |
| Animation | 30 | 60 | step counter, frame table |
| Buzzer | 22 | 40 | divider, three tones |
| Per-room glue | 20 | 40 | constants ROM, door/wrong OR, muxes |
| **Added total** | **~550** | **~950** | |

Physical overhead is 162 now and grows with flip-flop count (clock delay
buffers are about 0.4 per flop). Expect about 200 to 260 at 200 flops.

| Case | Logic + flops | + overhead | Cells | Utilization |
|---|---|---|---|---|
| Low | 324 + 550 | 200 | ~1070 | ~65 % |
| Middle | 324 + 750 | 230 | ~1300 | ~79 % |
| High | 324 + 950 | 260 | ~1530 | ~93 % |

The estimates carry large error bars, about plus or minus 40 percent on the
added blocks. Room 7 is the biggest single unknown, and its mixer rounds are
the first item on the cut list.

## Reading

- The low case fits at the configured density.
- The middle case needs about 80 % fill, which is unproven for routing here.
- The high case does not fit.
- So the full ten-room design is possible but not safe yet. The skeleton is
  cheaper than budgeted, and the risk sits in rooms 4, 6, 7, 8 and 9.

## Recommendation (the owner decides)

1. **Keep this design**, with a hard gate: re-run the flow after every room
   batch (M3 and M4), and cut when the measured utilization plus a margin for the
   remaining rooms passes about 80 %. The flow takes about five minutes.
2. **Cut order is already in MILESTONES.md** (room 7 mixer rounds, animation
   detail, buzzer, room 9). Add one more lever: reuse the shared shift register
   as the room 8 message buffer and the room 9 entry register, and the shared
   comparator for every compare.
3. **Room 9 should be the seed check**, built on the shared register and
   comparator, with the victory-screen fallback if M4's measurement is over the
   gate. Do not plan the iButton stretch: it would not fit in the middle case.
4. **iButton design:** no cell count exists for it, so there is no data to
   compare against. If the Nov 14 decision needs one, that design must be
   synthesized the same way.
