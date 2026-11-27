#!/usr/bin/env bash
# check_core.sh - Verify a SystemVerilog CryptoCore against every golden trace
# (needs Verilator). Exit code 0 only if every trace matches on every cycle.
#
# Usage: check_core.sh [opt|baseline|it<N>_<name>]   (default: opt)
#   opt      -> ../rtl/crypto_core_2pass_opt.sv   (module crypto_core_2pass_opt)
#   baseline -> ../../SystemVerilogHardware/rtl/crypto_core_2pass.sv
#   itN_name -> ../iterations/itN_name/crypto_core_2pass_opt.sv (a snapshot)
set -euo pipefail
cd "$(dirname "$0")"
WHICH="${1:-opt}"
case "$WHICH" in
    opt)      TOP=crypto_core_2pass_opt; SRC=(../rtl/asconp.sv ../rtl/crypto_core_2pass_opt.sv) ;;
    baseline) TOP=crypto_core_2pass_sv;  SRC=(../../SystemVerilogHardware/rtl/asconp.sv ../../SystemVerilogHardware/rtl/crypto_core_2pass.sv) ;;
    it*)      TOP=crypto_core_2pass_opt; SRC=(../rtl/asconp.sv ../iterations/$WHICH/crypto_core_2pass_opt.sv)
              [ -f "${SRC[1]}" ] || { echo "no snapshot ${SRC[1]}"; exit 2; } ;;
    *) echo "usage: $0 [opt|baseline|it<N>_<name>]"; exit 2 ;;
esac
ls traces/*.trc >/dev/null 2>&1 || { echo "no traces: run ./make_golden_traces.sh first"; exit 2; }
replay/build_replay.sh "$WHICH" "$TOP" "${SRC[@]}"
fail=0
for t in traces/*.trc; do
    replay/build/$WHICH/replay "$t" 5 || fail=1
done
echo
if [ $fail -eq 0 ]; then echo "*** $WHICH core: ALL TRACES MATCH THE ORIGINAL DESIGN ***"
else echo "*** $WHICH core: MISMATCHES FOUND ***"; fi
exit $fail
