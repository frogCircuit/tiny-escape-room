#!/usr/bin/env bash
# Source this before `make` in test/:  source scripts/sim-env.sh
# The oss-cad-suite vvp/iverilog wrappers set PYTHONHOME, which breaks
# cocotb's embedded Python. These shims call the real binaries instead.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="$HOME/.apio/packages/oss-cad-suite"
SHIM="$ROOT/.venv/sim-shim"
mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\nexec "%s/libexec/vvp" "$@"\n' "$SUITE" > "$SHIM/vvp"
printf '#!/usr/bin/env bash\nexec "%s/bin/iverilog" "$@"\n' "$SUITE" > "$SHIM/iverilog"
chmod +x "$SHIM/vvp" "$SHIM/iverilog"
export ICARUS_BIN_DIR="$SHIM"
export PATH="$SHIM:$ROOT/.venv/bin:$SUITE/bin:$PATH"
