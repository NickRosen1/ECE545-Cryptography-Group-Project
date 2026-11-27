#!/usr/bin/env bash
# sim_kat_xsim.sh - OPTIONAL sign-off: run the ISAP team's own LWC testbench
# (LWC_TB.vhd) on a core inside the real LWC wrapper with the Vivado simulator.
# This is the same check as SystemVerilogHardware/run_aead_regression.ps1,
# written for bash (Linux, macOS VM, WSL or Git Bash) and any core.
#
# Usage: sim_kat_xsim.sh [opt|baseline|reference] [kat_dir] [test_mode]
#   defaults: opt  ../verif/vectors/kat_v1_official_aead  0
#   test_mode: 0 no stalls, 1 stalls on inputs and outputs
# Needs Vivado's bin directory on PATH (source <Vivado>/settings64.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OPT="$(dirname "$HERE")"; REPO="$(dirname "$OPT")"
DESIGN="${1:-opt}"
KAT="$(cd "${2:-$OPT/verif/vectors/kat_v1_official_aead}" && pwd)"
MODE="${3:-0}"
HW="$REPO/hardware"
B="$HERE/xsim_build/${DESIGN}_$(basename "$KAT")_mode$MODE"
rm -rf "$B"; mkdir -p "$B"; cd "$B"

cat > LWC_TB_config.vhd <<EOF
package LWC_TB_config is
    constant G_FNAME_PDI : string := "$KAT/pdi.txt";
    constant G_FNAME_SDI : string := "$KAT/sdi.txt";
    constant G_FNAME_DO  : string := "$KAT/do.txt";
    constant G_FNAME_RDI : string := "$KAT/rdi.txt";
end package;
EOF

case "$DESIGN" in
    opt)       CORE_VHD="$OPT/rtl/crypto_core_2pass_binding_opt.vhd"
               CORE_SV=("$OPT/rtl/asconp.sv" "$OPT/rtl/crypto_core_2pass_opt.sv") ;;
    baseline)  CORE_VHD="$REPO/SystemVerilogHardware/rtl/crypto_core_2pass_binding.vhd"
               CORE_SV=("$REPO/SystemVerilogHardware/rtl/asconp.sv" "$REPO/SystemVerilogHardware/rtl/crypto_core_2pass.sv") ;;
    reference) CORE_VHD="$HW/isap_lwc/src_rtl/v1/CryptoCore.vhd"; CORE_SV=() ;;
    *) echo "usage: $0 [opt|baseline|reference] [kat_dir] [test_mode]"; exit 2 ;;
esac

if [ ${#CORE_SV[@]} -gt 0 ]; then xvlog --sv "${CORE_SV[@]}" > xvlog.log; fi
xvhdl --2008 \
    "$HW/isap_lwc/src_rtl/v1/design_pkg.vhd" "$HW/isap_lwc/src_rtl/LWC_config_32.vhd" \
    "$HW/LWC_rtl/NIST_LWAPI_pkg.vhd" "$CORE_VHD" \
    "$HW/LWC_rtl/key_piso.vhd" "$HW/LWC_rtl/FIFO.vhd" "$HW/LWC_rtl/data_sipo.vhd" \
    "$HW/LWC_rtl/data_piso.vhd" "$HW/LWC_rtl/PreProcessor.vhd" "$HW/LWC_rtl/PostProcessor.vhd" \
    "$HW/LWC_rtl/LWC_2pass.vhd" LWC_TB_config.vhd \
    "$HW/LWC_tb/LWC_TB_2pass_uut.vhd" "$HW/LWC_tb/LWC_TB.vhd" > xvhdl.log
xelab LWC_TB -s tb --timescale 1ns/1ps \
    -generic_top "G_TEST_MODE=$MODE" -generic_top "G_TIMEOUT_CYCLES=5000" > xelab.log
xsim tb -R > xsim.log 2>&1 || true
if grep -q "\[PASS\]" xsim.log; then
    echo "PASS: $DESIGN, $(basename "$KAT"), mode $MODE  ($(grep -o '\[PASS\].*' xsim.log | head -1))"
else
    echo "FAIL: $DESIGN, $(basename "$KAT"), mode $MODE - see $B/xsim.log"; exit 1
fi
