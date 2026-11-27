#!/usr/bin/env bash
# run_golden.sh - Simulate the ORIGINAL ISAP team VHDL design (LWC wrapper +
# v1 CryptoCore) in GHDL on a KAT set and record a cycle-by-cycle trace of
# every signal on the CryptoCore boundary.
#
# The original LWC testbench checks every output word against the KAT, so a
# trace from a passing run is a known-good "golden" record of how a correct
# core behaves, cycle by cycle, inside the real wrapper.
#
# Usage: run_golden.sh <kat_dir> <test_mode> <out_trace> [max_failures]
#   test_mode 0 = no stalls, 1 = stalls on pdi/sdi and do (see LWC_TB.vhd)
#   max_failures: use a large value for deliberately failing (bad-tag) sets
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
KAT="$(cd "$1" && pwd)"; MODE="$2"; OUT="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"; MAXF="${4:-0}"
HW="$REPO/hardware"
BUILD="$HERE/build"
mkdir -p "$BUILD"
cd "$BUILD"

if [ ! -f LWC_2pass_trace.vhd ] || [ "$HERE/make_trace_wrapper.py" -nt LWC_2pass_trace.vhd ]; then
    python3 "$HERE/make_trace_wrapper.py" "$HW/LWC_rtl/LWC_2pass.vhd" LWC_2pass_trace.vhd
fi

FLAGS="--workdir=$BUILD --std=08 -frelaxed -frelaxed-rules --warn-no-vital-generic -fsynopsys"
SRCS=(
    "$HW/isap_lwc/src_rtl/v1/design_pkg.vhd"
    "$HW/isap_lwc/src_rtl/LWC_config_32.vhd"
    "$HW/LWC_rtl/NIST_LWAPI_pkg.vhd"
    "$HW/isap_lwc/src_rtl/v1/CryptoCore.vhd"
    "$HW/LWC_rtl/key_piso.vhd"
    "$HW/LWC_rtl/FIFO.vhd"
    "$HW/LWC_rtl/data_sipo.vhd"
    "$HW/LWC_rtl/data_piso.vhd"
    "$HW/LWC_rtl/PreProcessor.vhd"
    "$HW/LWC_rtl/PostProcessor.vhd"
    "$BUILD/LWC_2pass_trace.vhd"
    "$HW/isap_lwc/src_tb/v1/LWC_TB_config.vhd"
    "$HW/LWC_tb/LWC_TB_2pass_uut.vhd"
    "$HW/LWC_tb/LWC_TB.vhd"
)
if [ ! -f .compiled ] || [ "$HERE/run_golden.sh" -nt .compiled ] || [ LWC_2pass_trace.vhd -nt .compiled ]; then
    rm -f work-obj08.cf
    for s in "${SRCS[@]}"; do ghdl -a $FLAGS "$s"; done
    : # mcode GHDL elaborates at run time (with the generics below)
    touch .compiled
fi

RUN="$BUILD/run_$$"; mkdir -p "$RUN"; cd "$RUN"
set +e
ghdl -r $FLAGS LWC_TB \
    -gG_FNAME_PDI="$KAT/pdi.txt" -gG_FNAME_SDI="$KAT/sdi.txt" -gG_FNAME_DO="$KAT/do.txt" \
    -gG_TEST_MODE="$MODE" -gG_MAX_FAILURES="$MAXF" -gG_TIMEOUT_CYCLES=5000 \
    --ieee-asserts=disable-at-0 > sim.log 2>&1
RC=$?
set -e
mv core_trace.txt "$OUT"
cp sim.log "$OUT.log"
[ -f failed_testvectors.txt ] && cp failed_testvectors.txt "$OUT.failed.txt"
cd "$BUILD"; rm -rf "$RUN"
echo "GHDL exit code $RC; trace $(wc -l < "$OUT") cycles -> $OUT"
grep -E "PASS|FAIL|Timeout|timeout|failures" "$OUT.log" | tail -5 || true
exit 0
