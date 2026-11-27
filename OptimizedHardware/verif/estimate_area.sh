#!/usr/bin/env bash
# estimate_area.sh - Quick LUT/FF ESTIMATE with Yosys (synth_xilinx, 7-series).
# For comparing iterations quickly. These are NOT the numbers to report:
# Vivado's results (vivado/build_opt.tcl) are the real ones, and Yosys's
# absolute counts differ from Vivado's.
# Needs: sv2v and yosys (or yowasp-yosys: pip install yowasp-yosys).
# Usage: estimate_area.sh [opt|baseline|it<N>_<name>]
set -euo pipefail
cd "$(dirname "$0")"
WHICH="${1:-opt}"
case "$WHICH" in
    opt)      TOP=crypto_core_2pass_opt; SRC="../rtl/asconp.sv ../rtl/crypto_core_2pass_opt.sv" ;;
    baseline) TOP=crypto_core_2pass_sv;  SRC="../../SystemVerilogHardware/rtl/asconp.sv ../../SystemVerilogHardware/rtl/crypto_core_2pass.sv" ;;
    it*)      TOP=crypto_core_2pass_opt; SRC="../rtl/asconp.sv ../iterations/$WHICH/crypto_core_2pass_opt.sv" ;;
    *) echo "usage: $0 [opt|baseline|it<N>_<name>]"; exit 2 ;;
esac
mkdir -p build
YOSYS="${YOSYS:-$(command -v yowasp-yosys || command -v yosys)}"
# Yosys cannot parse some SystemVerilog used here (function return {...}),
# so the sources are first converted with sv2v (github.com/zachjs/sv2v).
SV2V="${SV2V:-$(command -v sv2v || true)}"
[ -n "$SV2V" ] || { echo "sv2v not found (set SV2V=/path/to/sv2v)"; exit 2; }
"$SV2V" $SRC > build/$WHICH.v
"$YOSYS" -q -l build/yosys_$WHICH.log -p "read_verilog build/$WHICH.v; synth_xilinx -family xc7 -top $TOP -flatten -noiopad -noclkbuf; write_json build/net_$WHICH.json; tee -o build/area_$WHICH.txt stat" >/dev/null
python3 -I - "build/area_$WHICH.txt" "$WHICH" <<'EOF'
import re, sys
txt = open(sys.argv[1]).read()
cells = dict((m.group(2), int(m.group(1))) for m in re.finditer(r"^\s+(\d+)\s+(\w+)\s*$", txt, re.M))
luts = sum(v for k, v in cells.items() if re.fullmatch(r"LUT[1-6]|INV", k))
ffs = sum(v for k, v in cells.items() if re.fullmatch(r"FD\w*", k))
muxf = sum(v for k, v in cells.items() if k.startswith("MUXF"))
carry = cells.get("CARRY4", 0)
print(f"[yosys estimate] {sys.argv[2]}: LUTs={luts} FFs={ffs} MUXF7/8={muxf} CARRY4={carry}")
EOF
python3 -I logic_depth.py "build/net_$WHICH.json" | head -1
