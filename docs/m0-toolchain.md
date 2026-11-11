# M0: Toolchain report

**FPGA route: Apio (openXC7 flow, native on the Mac).** No Nix, no VM.
Why: Apio 1.6.0 lists `basys3` (digilent, xc7a35tcpg236), downloads the chipdb
itself, builds natively on arm64 in about 17 s, and `apio upload` loads the
board through openFPGALoader 1.2.0.

## Versions seen
- Apio 1.6.0, packages: oss-cad-suite, openxc7, verible, definitions
- openFPGALoader v1.2.0 (`basys3` in its board list)
- cocotb 2.1.0 + pytest in `.venv` (Python 3.12), Icarus from oss-cad-suite
- Template: TinyTapeout/ttsky-verilog-template (SKY130 shuttles, TTSKY26d/e close 2026-11-30).
  The shuttle-to-template mapping is inferred from the names (unverified).

## Simulation
`source scripts/sim-env.sh && cd test && make`
The oss-cad-suite `vvp` wrapper sets PYTHONHOME and breaks cocotb; the script
adds shims and sets `ICARUS_BIN_DIR`. CI uses apt iverilog and is unaffected.

## FPGA
`cd fpga/blinky && apio build && apio upload` (LED0 blinks).
