# M3: synthesis after rooms 0 to 5, animations and buzzer

Tiny Tapeout flow (ttsky26d gds action), one 1x1 tile, 20 ns clock target.
Design: skeleton, rooms 0 to 5, byte-load shared register, door/wrong/reset
animations and buzzer. No measurement hook this time: the free counter feeds the
animation and tones, room 4 reads `seed[15:8]` and all 32 shift bits, so only
`seed[7:0]` (room 6) is still pruned, about 16 cells.

## Measured

| Item | M2 stage | M3 stage |
|---|---|---|
| Total cells (excluding fill and tap) | 516 | **730** |
| Utilization | 31.37 % | **47.20 %** |
| Wire length | 9214 um | 17520 um |
| Flip-flops | 88 | 112 |
| Logic (combo 238, AND 64, NOR 34, OR 34, NAND 26, mux 25, inverter 22) | 266 | 443 |
| Physical overhead (delay/tie 103, clock delay 45, buffers 27) | 162 | 175 |
| Tiny Tapeout precheck | - | 15 of 15 passed |
| Gate-level test (smoke) | - | passed |
| Timing slack | not seen | not seen |

The projection made at M2 for this stage was 700 to 840 cells and 43 to 51 %.

## What the batch cost

- Gross cells added by rooms 3, 4, 5, the byte-load mode, animations and buzzer:
  about 247 (net +214 after removing the old measurement hook, about 30 gates, and
  pruning `seed[7:0]`, about 16 cells). The M2 estimate for the same blocks was 220 to 350.
- Flip-flops added: about 32, which matches the registers in the rooms and the animation.
- Area per added cell is about 0.074 utilization points, above the whole-design average of
  0.0646, because the added logic is flip-flop and mux heavy (mux4 appears for room 4).
- The average cell is now bigger, so capacity in cells shrank: about 930 cells at 60 %,
  about 1240 at 80 %, about 1550 at 100 %.

## Projection to ten rooms (estimates)

Still to build: rooms 6 to 9, plus `seed[7:0]` coming back. Block estimates are unchanged
from M2 (room 6 70 to 100, room 7 150 to 300, room 8 50 to 80, room 9 70 to 110, glue 10 to 20,
seed low byte 16), plus about 35 cells of overhead for roughly 90 more flip-flops.

| Case | Cells still to add | Final cells | Final utilization |
|---|---|---|---|
| Low | ~400 | ~1130 | 73 to 77 % |
| Middle | ~530 | ~1260 | 81 to 86 % |
| High | ~660 | ~1390 | 90 to 96 % |

The range for each case uses 0.0646 (whole-design average) and 0.074 (what the last batch
actually cost) points per cell. Room 7 alone is 150 to 300 cells, which is 10 to 22
utilization points, and it is the main uncertainty.

## Reading against the 80 % gate

- The low case fits. The middle case misses the gate by about 1 to 6 points. The high case
  does not fit. The projection moved up slightly from M2 (middle 79 % to about 83 %).
- No cut is forced today, but the margin is thin enough that the remaining rooms must be
  built to a budget.

## Recommended budget rules for M4 to M6

1. **Room 7 gets a hard cap of about 150 cells**: build the mixer with a rounds parameter and
   start at two rounds. Landing room 7 at 150 instead of 225 pulls the middle case to about 80 %.
2. **Rooms 8 and 9 reuse the shared shift register and the 16-bit comparator** for the message
   buffer, the entry register and the seed compare. No new 16-bit registers.
3. **Re-measure after M4** (rooms 6 and 8). Real costs for two more rooms replace the
   estimates, and the remaining projection is recomputed before M5 starts.
4. **Prepared cuts, with rough savings:** room 7 mixer rounds (about 50 cells, 3.5 points per
   round), room 9 as a victory screen (70 to 110 cells, 5 to 8 points), buzzer (about 1 point),
   animation detail (about 1 point). Savings are estimates; the buzzer and animation share
   was not measured separately.
5. About 100 cells (14 %) are delay and tie cells the flow adds. They are not under our control.
