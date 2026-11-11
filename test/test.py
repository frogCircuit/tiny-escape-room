# SPDX-FileCopyrightText: © 2026 Fernando Valdez
# SPDX-License-Identifier: Apache-2.0
#
# Tiny Escape Room, M1: rooms 0 and 1, reset, display, pin plan.

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

# Public constants, mirrored from src/consts.v
K0 = 0x3C
K1 = [0x11, 0x6E, 0xA4, 0xD9]
S1 = 0xFE

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


# ---------------------------------------------------------------- pin plan

@cocotb.test()
async def test_pin_plan(dut):
    await init(dut)
    assert int(dut.uio_oe.value) == 0b1111_1000
    assert int(dut.uio_out.value) & 0x3F == 0  # busy, serial out, buzzer idle
    assert dp_on(dut) == 0
    assert shown_digit(dut) == 0


# ------------------------------------------------------------------ room 0

@cocotb.test()
async def test_room0_solver(dut):
    await init(dut)
    doors = Pulses(dut, DOOR_BIT)
    if RTL:
        cocotb.start_soon(seed_monitor(dut))
    assert shown_digit(dut) == 0
    await solve_room0(dut)
    assert shown_digit(dut) == 1
    assert doors.n == 1


@cocotb.test()
async def test_room0_wrong_codes(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    doors = Pulses(dut, DOOR_BIT)
    bad = [0x00, 0xFF] + [K0 ^ (1 << i) for i in range(8)]
    for n, code in enumerate(bad, start=1):
        await press(dut, code)
        assert shown_digit(dut) == 0, f"code {code:#04x} opened the door"
        assert wrongs.n == n
        if RTL:
            assert peek(dut, "seed") == 0, "wrong code latched the seed"
    assert doors.n == 0


@cocotb.test()
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
    assert shown_digit(dut) == 1
    assert peek_r1_state(dut) in (0, None)
    assert wrongs.n == 1


@cocotb.test()
async def test_seed_follows_press_timing(dut):
    seeds = []
    for delay in (0, 7, 100, 1234):
        await init(dut)
        if RTL:
            cocotb.start_soon(seed_monitor(dut))
        await ClockCycles(dut.clk, delay)
        await solve_room0(dut)
        assert shown_digit(dut) == 1
        if RTL:
            seeds.append(peek(dut, "seed"))
    if RTL:
        assert len(set(seeds)) == len(seeds), f"seeds repeated: {seeds}"
        assert all(s != 0 for s in seeds)


# ------------------------------------------------------------------ room 1

@cocotb.test()
async def test_room1_ignored_in_room0(dut):
    await init(dut)
    for code in K1 + [S1]:
        await press(dut, code)
    assert shown_digit(dut) == 0
    assert peek_r1_state(dut) in (0, None)


@cocotb.test()
async def test_room1_solver(dut):
    await init(dut)
    doors = Pulses(dut, DOOR_BIT)
    await solve_room0(dut)
    for i, code in enumerate(K1):
        assert shown_digit(dut) == 1
        await press(dut, code)
        if RTL and i < 3:
            assert peek_r1_state(dut) == i + 1
    assert shown_digit(dut) == 2
    assert doors.n == 2


@cocotb.test()
async def test_room1_shortcut(dut):
    await init(dut)
    wrongs = Pulses(dut, WRONG_BIT)
    await solve_room0(dut)
    await press(dut, K1[0])
    await press(dut, S1)           # state 1 -> state 3
    assert peek_r1_state(dut) in (3, None)
    assert wrongs.n == 0, "the shortcut must not count as a wrong code"
    assert shown_digit(dut) == 1
    await press(dut, K1[3])        # last code
    assert shown_digit(dut) == 2


@cocotb.test()
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
        assert shown_digit(dut) == 1, f"S1 opened the door from state {state}"
        assert peek_r1_state(dut) in (0, None), f"S1 stuck in state {state}"
        assert wrongs.n == 1


@cocotb.test()
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
            assert shown_digit(dut) == 1
            assert peek_r1_state(dut) in (0, None)
        # Starting over from state 0 still works.
        await solve_room1(dut)
        assert shown_digit(dut) == 2


# ------------------------------------------------------------------- reset

@cocotb.test()
async def test_reset_midgame(dut):
    await init(dut)
    await solve_room0(dut)
    await press(dut, K1[0])
    await press(dut, K1[1])
    assert shown_digit(dut) == 1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    assert shown_digit(dut) == 0
    assert peek(dut, "seed") in (0, None)
    assert peek_r1_state(dut) in (0, None)
    # Everything must be earned again from scratch.
    await press(dut, K1[2])
    assert shown_digit(dut) == 0
    await solve_room0(dut)
    await solve_room1(dut)
    assert shown_digit(dut) == 2


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
    for a, b, eq in ((0x12, 0x12, 1), (0x12, 0x13, 0), (0x00, 0x00, 1), (0xFF, 0x7F, 0)):
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
