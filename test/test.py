# SPDX-FileCopyrightText: © 2026 Fernando Valdez
# SPDX-License-Identifier: Apache-2.0
#
# Tiny Escape Room: rooms 0 to 2, reset, display, pin plan.

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

# Public constants, mirrored from src/consts.v
K0 = 0x3C
K1 = [0x11, 0x6E, 0xA4, 0xD9]
S1 = 0xFE
K2 = 0xB3A5

# {g,f,e,d,c,b,a} per digit, mirrored from src/display.v
SEG = {
    0: 0b0111111, 1: 0b0000110, 2: 0b1011011, 3: 0b1001111, 4: 0b1100110,
    5: 0b1101101, 6: 0b1111101, 7: 0b0000111, 8: 0b1111111, 9: 0b1101111,
    0xF: 0b1110001,
}

WRONG_BIT = 7
DOOR_BIT = 6

# Hierarchical peeks do not exist in the gate-level netlist.
RTL = os.environ.get("GATES") != "yes"


def peek(dut, name):
    """Internal signal value, or None in gate-level sim."""
    if not RTL:
        return None
    return int(getattr(dut.user_project, name).value)


def peek_r1_state(dut):
    return int(dut.user_project.u_room1.state.value) if RTL else None


async def init(dut):
    """Start the clock and reset the design."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def press(dut, code, hold=4, gap=4):
    """Put `code` on the switches and press submit for `hold` cycles."""
    dut.ui_in.value = code
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, hold)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, gap)


class Pulses:
    """Counts clock cycles in which a uio_out bit is high."""

    def __init__(self, dut, bit):
        self.n = 0
        self._dut = dut
        self._bit = bit
        self._task = cocotb.start_soon(self._run())

    async def _run(self):
        while True:
            await RisingEdge(self._dut.clk)
            if (int(self._dut.uio_out.value) >> self._bit) & 1:
                self.n += 1


def shown_digit(dut):
    """Decode the displayed digit from uo_out[6:0]; None if unknown pattern."""
    seg = int(dut.uo_out.value) & 0x7F
    for digit, pattern in SEG.items():
        if pattern == seg:
            return digit
    return None


def cur_room(dut):
    """The room counter (RTL only: the display is animated, so it cannot be read at a glance)."""
    return peek(dut, "room")


def dp_on(dut):
    return (int(dut.uo_out.value) >> 7) & 1


async def seed_monitor(dut):
    """The seed may only change by loading the free counter value of the previous cycle."""
    prev_cnt = prev_seed = prev_rst = None
    while True:
        await RisingEdge(dut.clk)
        cnt, seed = peek(dut, "free_cnt"), peek(dut, "seed")
        rst = int(dut.rst_n.value)
        if prev_seed is not None and prev_rst == 1 and seed != prev_seed:
            assert seed == prev_cnt, f"seed {seed:#06x} != counter {prev_cnt:#06x}"
        prev_cnt, prev_seed, prev_rst = cnt, seed, rst


async def solve_room0(dut):
    await press(dut, K0)


async def solve_room1(dut):
    for code in K1:
        await press(dut, code)


# uio_in bit 0 = submit, bit 1 = serial data, bit 2 = serial clock
async def serial_bit(dut, b, hold=3):
    """One serial clock pulse carrying bit b (data stable before the rising edge)."""
    dut.uio_in.value = b << 1
    await ClockCycles(dut.clk, hold)
    dut.uio_in.value = (b << 1) | 0b100
    await ClockCycles(dut.clk, hold)
    dut.uio_in.value = b << 1
    await ClockCycles(dut.clk, hold)


async def send_bits(dut, value, nbits):
    """Clock `nbits` of `value` in, MSB first."""
    for i in range(nbits - 1, -1, -1):
        await serial_bit(dut, (value >> i) & 1)
    dut.uio_in.value = 0


async def send_frame(dut, value):
    """Clock a 16-bit frame in, then submit it."""
    await send_bits(dut, value, 16)
    await press(dut, 0x00)


async def goto_room2(dut):
    await solve_room0(dut)
    await solve_room1(dut)
    assert cur_room(dut) == 2


# ---------------------------------------------------------------- pin plan

@cocotb.test()
async def test_pin_plan(dut):
    await init(dut)
    assert int(dut.uio_oe.value) == 0b1111_1000
    assert int(dut.uio_out.value) & 0x3F == 0  # busy, serial out, buzzer idle
    assert (int(dut.uio_out.value) >> 5) & 1 == 0  # buzzer silent after reset


# ------------------------------------------------------------------ room 0

@cocotb.test(skip=not RTL)
async def test_room0_solver(dut):
    await init(dut)
    doors = Pulses(dut, DOOR_BIT)
    if RTL:
        cocotb.start_soon(seed_monitor(dut))
    assert cur_room(dut) == 0
    await solve_room0(dut)
    assert cur_room(dut) == 1
    assert doors.n == 1


@cocotb.test(skip=not RTL)
async def test_room0_wrong_codes(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    doors = Pulses(dut, DOOR_BIT)
    bad = [0x00, 0xFF] + [K0 ^ (1 << i) for i in range(8)]
    for n, code in enumerate(bad, start=1):
        await press(dut, code)
        assert cur_room(dut) == 0, f"code {code:#04x} opened the door"
        assert wrongs.n == n
        if RTL:
            assert peek(dut, "seed") == 0, "wrong code latched the seed"
    assert doors.n == 0


@cocotb.test(skip=not RTL)
async def test_submit_is_edge_triggered(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    doors = Pulses(dut, DOOR_BIT)
    # Hold submit high for a long time with a wrong code: one action only.
    await press(dut, 0x00, hold=50)
    assert wrongs.n == 1
    # Hold submit high with the right code: the door opens exactly once,
    # and the held button does not act again in room 1.
    await press(dut, K0, hold=50)
    assert doors.n == 1
    assert cur_room(dut) == 1
    assert peek_r1_state(dut) in (0, None)
    assert wrongs.n == 1


@cocotb.test(skip=not RTL)
async def test_seed_follows_press_timing(dut):
    seeds = []
    for delay in (0, 7, 100, 1234):
        await init(dut)
        if RTL:
            cocotb.start_soon(seed_monitor(dut))
        await ClockCycles(dut.clk, delay)
        await solve_room0(dut)
        assert cur_room(dut) == 1
        if RTL:
            seeds.append(peek(dut, "seed"))
    if RTL:
        assert len(set(seeds)) == len(seeds), f"seeds repeated: {seeds}"
        assert all(s != 0 for s in seeds)


# ------------------------------------------------------------------ room 1

@cocotb.test(skip=not RTL)
async def test_room1_ignored_in_room0(dut):
    await init(dut)
    for code in K1 + [S1]:
        await press(dut, code)
    assert cur_room(dut) == 0
    assert peek_r1_state(dut) in (0, None)


@cocotb.test(skip=not RTL)
async def test_room1_solver(dut):
    await init(dut)
    doors = Pulses(dut, DOOR_BIT)
    await solve_room0(dut)
    for i, code in enumerate(K1):
        assert cur_room(dut) == 1
        await press(dut, code)
        if RTL and i < 3:
            assert peek_r1_state(dut) == i + 1
    assert cur_room(dut) == 2
    assert doors.n == 2


@cocotb.test(skip=not RTL)
async def test_room1_shortcut(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    await solve_room0(dut)
    await press(dut, K1[0])
    await press(dut, S1)           # state 1 -> state 3
    assert peek_r1_state(dut) in (3, None)
    assert wrongs.n == 0, "the shortcut must not count as a wrong code"
    assert cur_room(dut) == 1
    await press(dut, K1[3])        # last code
    assert cur_room(dut) == 2


@cocotb.test(skip=not RTL)
async def test_room1_shortcut_only_from_state1(dut):
    for state in (0, 2, 3):
        await init(dut)
        wrongs = Pulses(dut, WRONG_BIT)
        await solve_room0(dut)
        if state == 3:
            for code in K1[:3]:
                await press(dut, code)
        else:
            for code in K1[:state]:
                await press(dut, code)
        await press(dut, S1)
        assert cur_room(dut) == 1, f"S1 opened the door from state {state}"
        assert peek_r1_state(dut) in (0, None), f"S1 stuck in state {state}"
        assert wrongs.n == 1


@cocotb.test(skip=not RTL)
async def test_room1_wrong_code_resets(dut):
    for state in range(4):
        await init(dut)
        wrongs = Pulses(dut, WRONG_BIT)
        await solve_room0(dut)
        for code in K1[:state]:
            await press(dut, code)
        await press(dut, 0x00)                # wrong at this state
        assert wrongs.n == 1
        assert peek_r1_state(dut) in (0, None)
        # The old progress is gone: the next code in the old sequence fails.
        # (From state 0 the "old next code" is K1[0], which is correct, so skip it.)
        if state >= 1:
            await press(dut, K1[state])
            assert cur_room(dut) == 1
            assert peek_r1_state(dut) in (0, None)
        # Starting over from state 0 still works.
        await solve_room1(dut)
        assert cur_room(dut) == 2


# ------------------------------------------------------------------ room 2

@cocotb.test(skip=not RTL)
async def test_room2_solver(dut):
    await init(dut)
    doors = Pulses(dut, DOOR_BIT)
    await goto_room2(dut)
    await send_frame(dut, K2)
    assert cur_room(dut) == 3
    assert doors.n == 3


@cocotb.test(skip=not RTL)
async def test_room2_wrong_frames(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    await goto_room2(dut)
    n = 0
    for bad in [0x0000, 0xFFFF] + [K2 ^ (1 << i) for i in range(16)]:
        await send_frame(dut, bad)
        n += 1
        assert cur_room(dut) == 2, f"frame {bad:#06x} opened the door"
        assert wrongs.n == n
    await send_frame(dut, K2)       # the right frame still works afterwards
    assert cur_room(dut) == 3


@cocotb.test(skip=not RTL)
async def test_room2_short_frame(dut):
    await init(dut)
    await goto_room2(dut)
    await send_bits(dut, K2 & 0x7FFF, 15)   # only 15 bits: the MSB is missing
    await press(dut, 0x00)
    assert cur_room(dut) == 2


@cocotb.test(skip=not RTL)
async def test_room2_last_16_bits_win(dut):
    await init(dut)
    await goto_room2(dut)
    await send_bits(dut, 0x5A5A5A, 24)       # junk first
    await send_bits(dut, K2, 16)             # last 16 bits are the frame
    await press(dut, 0x00)
    assert cur_room(dut) == 3


@cocotb.test(skip=not RTL)
async def test_room2_shifts_on_rising_edge_only(dut):
    await init(dut)
    await goto_room2(dut)
    dut.uio_in.value = 0b110                 # data=1, clock rises and stays high
    await ClockCycles(dut.clk, 50)
    assert peek(dut, "shift_q") in (1, None), "held clock shifted more than once"
    dut.uio_in.value = 0b010                 # falling edge: no shift
    await ClockCycles(dut.clk, 10)
    assert peek(dut, "shift_q") in (1, None)


@cocotb.test(skip=not RTL)
async def test_serial_ignored_outside_room2(dut):
    await init(dut)
    await send_bits(dut, 0xFFFF, 16)         # room 0
    assert peek(dut, "shift_q") in (0, None)
    assert cur_room(dut) == 0
    await solve_room0(dut)
    await send_bits(dut, 0xFFFF, 16)         # room 1
    assert peek(dut, "shift_q") in (0, None)
    await press(dut, K1[0])
    assert cur_room(dut) == 1


# ------------------------------------------------------------------- reset

@cocotb.test(skip=not RTL)
async def test_reset_midgame(dut):
    await init(dut)
    await solve_room0(dut)
    await press(dut, K1[0])
    await press(dut, K1[1])
    assert cur_room(dut) == 1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    assert cur_room(dut) == 0
    assert peek(dut, "seed") in (0, None)
    assert peek_r1_state(dut) in (0, None)
    # Everything must be earned again from scratch.
    await press(dut, K1[2])
    assert cur_room(dut) == 0
    await solve_room0(dut)
    await solve_room1(dut)
    assert cur_room(dut) == 2


# ----------------------------------------------- unit tests (RTL sim only)

@cocotb.test(skip=not RTL)
async def test_display_decoder(dut):
    for digit, pattern in SEG.items():
        dut.disp_digit.value = digit
        dut.disp_dp.value = 0
        await cocotb.triggers.Timer(1, unit="ns")
        assert int(dut.disp_out.value) == pattern, f"digit {digit:x}"
    dut.disp_digit.value = 3
    dut.disp_dp.value = 1
    await cocotb.triggers.Timer(1, unit="ns")
    assert int(dut.disp_out.value) == 0x80 | SEG[3]
    dut.disp_digit.value = 0xA     # not a digit: blank
    dut.disp_dp.value = 0
    await cocotb.triggers.Timer(1, unit="ns")
    assert int(dut.disp_out.value) == 0


@cocotb.test(skip=not RTL)
async def test_shared_regs(dut):
    await init(dut)
    # comparator
    for a, b, eq in ((0x12, 0x12, 1), (0x12, 0x13, 0), (0x00, 0x00, 1), (0xFF, 0x7F, 0),
                     (0xB3A5, 0xB3A5, 1), (0xB3A5, 0xB3A4, 0), (0x33A5, 0xB3A5, 0), (0xFFFF, 0xFFFF, 1)):
        dut.sr_a.value = a
        dut.sr_b.value = b
        await cocotb.triggers.Timer(1, unit="ns")
        assert int(dut.sr_match.value) == eq
    # shift register: first bit in ends up as the MSB after 32 shifts
    pattern = 0xDEADBEEF
    dut.sr_shift_en.value = 1
    for i in range(31, -1, -1):
        dut.sr_shift_in.value = (pattern >> i) & 1
        await ClockCycles(dut.clk, 1)
    dut.sr_shift_en.value = 0
    await ClockCycles(dut.clk, 2)
    assert int(dut.sr_q.value) == pattern
    # holds when not enabled
    dut.sr_shift_in.value = 1
    await ClockCycles(dut.clk, 3)
    assert int(dut.sr_q.value) == pattern


# ============================================================ rooms 3, 4, 5

BUSY_BIT = 3
SEROUT_BIT = 4
C1 = 0x5C
CMD_DUMP = 0xA5
CMD_UNLOCK = 0x5A


def password(seed):
    """Room 4 password from the seed (CLAUDE.md section 5)."""
    return [(((seed >> 8) ^ C1) + 0x11 * i) & 0xFF for i in range(4)]


class Runs:
    """Lengths of the runs of consecutive cycles in which a uio_out bit is high."""

    def __init__(self, dut, bit):
        self.runs = []
        self._dut = dut
        self._bit = bit
        self._task = cocotb.start_soon(self._run())

    async def _run(self):
        cur = 0
        while True:
            await RisingEdge(self._dut.clk)
            if (int(self._dut.uio_out.value) >> self._bit) & 1:
                cur += 1
            elif cur:
                self.runs.append(cur)
                cur = 0


# ---- room 2 and room 3 solvers

async def solve_room2(dut):
    await send_frame(dut, K2)


async def race(dut, delay=3, small=0x05, big=0xF5):
    """Hold submit; pass the check with `small`, then switch to `big` after `delay` cycles."""
    dut.ui_in.value = small
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, delay)
    dut.ui_in.value = big
    await ClockCycles(dut.clk, 4)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 4)


async def solve_room3(dut):
    await race(dut)


# ---- room 4: one password attempt, and the timing-only solver

async def attempt(dut, bs, runs):
    """Enter four bytes (one submit each); return how long busy stayed high."""
    n_before = len(runs.runs)
    for b in bs:
        await press(dut, b)
    await ClockCycles(dut.clk, 70)           # longest possible busy run is 64 cycles
    assert len(runs.runs) == n_before + 1, "busy did not run exactly once"
    return runs.runs[-1]


async def recover_password(dut, runs, doors):
    """Recover the password from the busy pin (and the door pulse) only."""
    known = []
    for k in range(4):
        for cand in range(256):
            opened = doors.n
            n = await attempt(dut, known + [cand] + [0] * (3 - k), runs)
            if doors.n > opened:             # accepted: the whole password was right
                return known + [cand] + [0] * (3 - k)
            if n >= 16 * (k + 2):            # byte k right: the loop got further
                known.append(cand)
                break
        else:
            raise AssertionError(f"no candidate for byte {k}")
    raise AssertionError("password recovered but the door never opened")


async def solve_room4(dut):
    """Fast path for tests of other rooms: read the seed instead of timing."""
    runs = Runs(dut, BUSY_BIT)
    await attempt(dut, password(peek(dut, "seed")), runs)


# ---- room 5: bytes over the serial pins, and the debug dump

async def read_bits(dut, n):
    """Clock out n bits from uio[4], MSB first: sample, then pulse the serial clock."""
    v = 0
    for _ in range(n):
        v = (v << 1) | ((int(dut.uio_out.value) >> SEROUT_BIT) & 1)
        await serial_bit(dut, 0)
    dut.uio_in.value = 0
    return v


async def solve_room5(dut):
    await send_bits(dut, CMD_DUMP, 8)
    dump = await read_bits(dut, 16)
    await send_bits(dut, dump & 0xFF, 8)     # the second command comes from the dump


async def to_room(dut, n):
    for solver in (solve_room0, solve_room1, solve_room2, solve_room3, solve_room4, solve_room5)[:n]:
        await solver(dut)
    assert cur_room(dut) == n


# ------------------------------------------------------------------ room 3

@cocotb.test(skip=not RTL)
async def test_room3_race_solver(dut):
    await init(dut)
    doors = Pulses(dut, DOOR_BIT)
    await to_room(dut, 3)
    await solve_room3(dut)
    assert cur_room(dut) == 4
    assert doors.n == 4


@cocotb.test(skip=not RTL)
async def test_room3_window_is_exactly_one_cycle(dut):
    wins = []
    for delay in range(1, 9):
        await init(dut)
        await to_room(dut, 3)
        await race(dut, delay=delay)
        if cur_room(dut) == 4:
            wins.append(delay)
    assert wins == [3], f"race wins at delays {wins}, expected only the one-cycle window"


@cocotb.test(skip=not RTL)
async def test_room3_negative_cases(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    await to_room(dut, 3)
    # A large value straight away is rejected at the check.
    await press(dut, 0xF5)
    assert cur_room(dut) == 3 and wrongs.n == 1
    # A small value that stays small is stored, but is not enough.
    await press(dut, 0x05)
    assert cur_room(dut) == 3 and wrongs.n == 2
    # Switching to large too early (before the check) fails the check.
    await race(dut, delay=1)
    assert cur_room(dut) == 3
    # Switching too late stores the small value.
    await race(dut, delay=6)
    assert cur_room(dut) == 3
    # And it still works afterwards.
    await solve_room3(dut)
    assert cur_room(dut) == 4


# ------------------------------------------------------------------ room 4

@cocotb.test(skip=not RTL)
async def test_room4_busy_time_leaks_correct_prefix(dut):
    await init(dut)
    runs = Runs(dut, BUSY_BIT)
    await to_room(dut, 4)
    pw = password(peek(dut, "seed")) if RTL else None
    if not RTL:
        return
    for k in range(4):
        bad = pw[:k] + [pw[k] ^ 0x01] + [0] * (3 - k)
        n = await attempt(dut, bad, runs)
        assert n == 16 * (k + 1), f"first wrong byte at {k}: busy {n}, expected {16 * (k + 1)}"
    assert cur_room(dut) == 4


@cocotb.test(skip=not RTL)
async def test_room4_solver_from_busy_timing_only(dut):
    await init(dut)
    runs = Runs(dut, BUSY_BIT)
    doors = Pulses(dut, DOOR_BIT)
    await to_room(dut, 4)
    seed = peek(dut, "seed")
    recovered = await recover_password(dut, runs, doors)
    assert cur_room(dut) == 5
    if seed is not None:
        assert recovered == password(seed), f"{recovered} vs {password(seed)}"
        assert (recovered[0] ^ C1) == (seed >> 8)   # the player's route to seed_hi


@cocotb.test(skip=not RTL)
async def test_room4_failed_attempt_leaves_no_state(dut):
    await init(dut)
    runs = Runs(dut, BUSY_BIT)
    await to_room(dut, 4)
    pw = password(peek(dut, "seed"))
    await attempt(dut, [0x00, 0x00, 0x00, 0x00], runs)
    await attempt(dut, pw[:3] + [pw[3] ^ 0x80], runs)
    assert cur_room(dut) == 4
    await attempt(dut, pw, runs)
    assert cur_room(dut) == 5


@cocotb.test(skip=not RTL)
async def test_room4_submits_ignored_while_busy(dut):
    await init(dut)
    runs = Runs(dut, BUSY_BIT)
    await to_room(dut, 4)
    pw = password(peek(dut, "seed"))
    for b in pw[:3] + [pw[3] ^ 0x01]:        # wrong in the last byte: busy for 64 cycles
        await press(dut, b)
    for b in (0x11, 0x22, 0x33, 0x44, 0x55):  # junk submitted while busy
        await press(dut, b, hold=4, gap=2)
    await ClockCycles(dut.clk, 70)
    assert runs.runs and runs.runs[-1] == 64
    await attempt(dut, pw, runs)             # nothing leaked into the entry count
    assert cur_room(dut) == 5


# ------------------------------------------------------------------ room 5

@cocotb.test(skip=not RTL)
async def test_room5_solver_uses_the_dump(dut):
    await init(dut)
    doors = Pulses(dut, DOOR_BIT)
    await to_room(dut, 5)
    await send_bits(dut, CMD_DUMP, 8)
    dump = await read_bits(dut, 16)
    assert dump == 0x515A, f"dump {dump:#06x}"   # {room 5, state 1, 0x5A}
    await send_bits(dut, dump & 0xFF, 8)
    assert cur_room(dut) == 6
    assert doors.n == 6


@cocotb.test(skip=not RTL)
async def test_room5_dump_does_not_depend_on_seed(dut):
    dumps = []
    for delay in (0, 37, 513):
        await init(dut)
        await ClockCycles(dut.clk, delay)
        await to_room(dut, 5)
        await send_bits(dut, CMD_DUMP, 8)
        dumps.append(await read_bits(dut, 16))
    assert len(set(dumps)) == 1, f"dump varies with the seed: {[hex(d) for d in dumps]}"


@cocotb.test(skip=not RTL)
async def test_room5_wrong_order_and_junk(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    await to_room(dut, 5)
    await send_bits(dut, CMD_UNLOCK, 8)      # second command first: rejected
    assert cur_room(dut) == 5 and wrongs.n == 1
    await send_bits(dut, 0x00, 8)            # junk byte
    assert cur_room(dut) == 5 and wrongs.n == 2
    await send_bits(dut, CMD_DUMP, 8)
    assert (await read_bits(dut, 16)) == 0x515A
    await send_bits(dut, 0xEE, 8)            # wrong second byte: back to waiting for 0xA5
    assert cur_room(dut) == 5 and wrongs.n == 3
    await send_bits(dut, CMD_UNLOCK, 8)      # no longer accepted without a new dump
    assert cur_room(dut) == 5
    await send_bits(dut, CMD_DUMP, 8)
    await read_bits(dut, 16)
    await send_bits(dut, CMD_UNLOCK, 8)
    assert cur_room(dut) == 6


@cocotb.test(skip=not RTL)
async def test_room5_submit_resyncs_a_misaligned_stream(dut):
    await init(dut)
    await to_room(dut, 5)
    await send_bits(dut, 0b101, 3)           # three stray bits knock the framing off
    await send_bits(dut, CMD_DUMP, 8)        # so this byte is not seen as 0xA5
    assert cur_room(dut) == 5
    await press(dut, 0x00)                   # submit: forget the partial byte
    await send_bits(dut, CMD_DUMP, 8)
    assert (await read_bits(dut, 16)) == 0x515A
    await send_bits(dut, CMD_UNLOCK, 8)
    assert cur_room(dut) == 6


@cocotb.test(skip=not RTL)
async def test_room5_unlock_byte_during_dump_is_ignored(dut):
    await init(dut)
    await to_room(dut, 5)
    await send_bits(dut, CMD_DUMP, 8)
    await send_bits(dut, CMD_UNLOCK, 8)      # these 8 clocks are just dump clocks
    assert cur_room(dut) == 5
    await send_bits(dut, 0x00, 8)            # the other 8 dump clocks; dump is now over
    assert cur_room(dut) == 5
    await send_bits(dut, CMD_UNLOCK, 8)      # now it counts
    assert cur_room(dut) == 6


# ============================================================ gate-level smoke

@cocotb.test()
async def test_gl_smoke_pulses(dut):
    """Runs in RTL and gate-level: only the door and wrong pulse pins are watched."""
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    doors = Pulses(dut, DOOR_BIT)
    await press(dut, 0x00)
    assert wrongs.n == 1 and doors.n == 0
    await press(dut, K0)
    assert doors.n == 1
    await press(dut, K1[0])
    await press(dut, 0x00)
    assert wrongs.n == 2


# ============================================================ animations (RTL only)

SIM_TICK = 1 << 10          # clocks per animation step in the RTL testbench (TICK_BITS = 10)


async def record(dut, n):
    """(uo_out, buzzer) once per clock for n clocks."""
    frames = []
    for _ in range(n):
        await RisingEdge(dut.clk)
        frames.append((int(dut.uo_out.value), (int(dut.uio_out.value) >> 5) & 1))
    return frames


def dedupe(seq):
    out = []
    for s in seq:
        if not out or out[-1] != s:
            out.append(s)
    return out


def toggles(bits):
    return sum(1 for a, b in zip(bits, bits[1:]) if a != b)


async def wait_idle(dut):
    await ClockCycles(dut.clk, 14 * SIM_TICK)


@cocotb.test(skip=not RTL)
async def test_anim_reset_chase_is_silent_then_room0(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    frames = await record(dut, 9 * SIM_TICK)
    shown = dedupe([f[0] for f in frames])
    chase = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20]
    assert [s for s in shown if s in chase] == chase, f"reset chase: {[hex(s) for s in shown]}"
    assert shown[-1] == SEG[0], "room 0 digit after the reset chase"
    assert not any(f[1] for f in frames), "reset chase must be silent"


@cocotb.test(skip=not RTL)
async def test_anim_door_chase_chime_and_decimal_point(dut):
    await init(dut)
    await wait_idle(dut)
    dut.ui_in.value = K0
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 4)
    dut.uio_in.value = 0
    frames = await record(dut, 14 * SIM_TICK)
    shown = dedupe([f[0] for f in frames])
    one_lap = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20]
    assert shown == one_lap * 2 + [0x80 | SEG[1]], f"door frames: {[hex(s) for s in shown]}"
    buzz = [f[1] for f in frames]
    half = 6 * SIM_TICK
    assert toggles(buzz[:half]) > 20, "chime note 1 missing"
    assert toggles(buzz[half:2 * half]) > 10, "chime note 2 missing"
    assert not any(buzz[2 * half + SIM_TICK:]), "buzzer must be silent after the chime"
    assert dp_on(dut) == 1
    # A new try clears the decimal point.
    await press(dut, 0x00)
    await ClockCycles(dut.clk, 10 * SIM_TICK)
    assert dp_on(dut) == 0


@cocotb.test(skip=not RTL)
async def test_anim_wrong_blinks_twice_and_buzzes(dut):
    await init(dut)
    await wait_idle(dut)
    dut.ui_in.value = 0x00
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 4)
    dut.uio_in.value = 0
    frames = await record(dut, 11 * SIM_TICK)
    shown = dedupe([f[0] for f in frames])
    assert shown == [0xFF, 0x00, 0xFF, 0x00, SEG[0]], f"wrong frames: {[hex(s) for s in shown]}"
    buzz = [f[1] for f in frames]
    assert toggles(buzz[:8 * SIM_TICK]) >= 3, "buzz missing"   # bit 11: ~4 toggles in 8 short steps
    assert not any(buzz[9 * SIM_TICK:]), "buzzer must be silent afterwards"


@cocotb.test(skip=not RTL)
async def test_anim_never_blocks_input(dut):
    """Rooms 0 to 3 are solved back to back while animations are running."""
    await init(dut)
    await to_room(dut, 3)
    await solve_room3(dut)
    assert cur_room(dut) == 4


@cocotb.test(skip=not RTL)
async def test_buzzer_silent_when_idle(dut):
    await init(dut)
    await wait_idle(dut)
    frames = await record(dut, 5000)
    assert not any(f[1] for f in frames)
