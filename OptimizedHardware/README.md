# OptimizedHardware: area-optimized ISAP-A-128A core

This folder holds the area-optimization work. Everything that existed before
is untouched:

- `SystemVerilogHardware/` stays the **baseline** (straight SV port).
- `groupProjectFPGA/` stays as it was.
- `hardware/` stays as the ISAP team's original design.

To roll back, use any snapshot in `iterations/` (or delete this folder).

## Current status

Vivado 2025.1, xc7a12tcsg325-3, core alone, placed and routed at 100 MHz:

| | Baseline (straight port) | Optimized (`rtl/`, = it7) | Change |
|---|---:|---:|---:|
| LUTs | 1,488 | 1,250 | -16.0% |
| Slices | 456 | 394 | -13.6% |
| Flip-flops | 949 | 942 | -0.7% |
| Fmax | 147.1 MHz | 146.6 MHz | -0.3% |
| Throughput (2.75 cycles/byte) | 428 Mbps | 426 Mbps | -0.3% |
| Mbps per LUT | 0.288 | 0.341 | +18.6% |

Inside the LWC wrapper: 1,653 to 1,400 LUTs (-15.3%), 513 to 457 slices
(-10.9%), 142.4 to 145.2 MHz.

Behaviour is identical to the original on every clock cycle (verified, below).
See `ITERATIONS.md` for every change, why it is safe, and its measured effect.

## Folder map

```
OptimizedHardware/
  rtl/
    asconp.sv                       Ascon-p round (unchanged copy)
    crypto_core_2pass_opt.sv        optimized core, module crypto_core_2pass_opt
    crypto_core_2pass_binding_opt.vhd  lets the VHDL LWC wrapper use it
  iterations/itN_*/                 snapshot of the core after each iteration
  ITERATIONS.md                     optimization log (fill in Vivado numbers)
  verif/
    check_core.sh                   verify a core against all golden traces
    make_golden_traces.sh           (re)create the golden traces, run once
    estimate_area.sh                quick Yosys LUT/FF estimate
    logic_depth.py                  logic-level timing proxy
    golden/                         GHDL run of the ORIGINAL VHDL design
    replay/                         Verilator trace-replay checker
    vectors/                        test vectors (official KAT + extended + forged tags)
  vivado/
    build.tcl                       synth + place + route one design, record numbers
    build_all.tcl                   all designs the report needs -> results/summary.csv
    create_project.tcl              clean GUI project for the optimized core
    core_clock.xdc                  clock-only constraint (fixes the hold issue)
    sim_kat_xsim.sh                 optional: LWC testbench in the Vivado simulator
```

## 1. Verify a core (Linux, macOS or WSL)

Install once: GHDL and Verilator (`sudo apt install ghdl verilator`, or
`brew install ghdl verilator`).

```bash
cd OptimizedHardware/verif
./make_golden_traces.sh        # once, ~3 minutes; creates verif/traces (~170 MB, git-ignored)
./check_core.sh opt            # the optimized core
./check_core.sh baseline       # the partner's straight port, for comparison
```

A pass ends with `*** opt core: ALL TRACES MATCH THE ORIGINAL DESIGN ***`.

### How this verification works

1. `make_golden_traces.sh` simulates the **original ISAP team VHDL design**
   (LWC wrapper + v1 core) in GHDL with the ISAP team's own testbench
   (`LWC_TB.vhd`), which checks every output word against the test vectors.
   A passive process added to a generated copy of the wrapper records every
   signal on the core's boundary at every rising clock edge.
2. `check_core.sh` drives the recorded core inputs into the SystemVerilog
   core (compiled with Verilator) and requires the recorded outputs on every
   cycle. Handshake signals are compared on every cycle; data outputs only
   while their valid signal is high, because the wrapper ignores them
   otherwise. If every cycle matches, the wrapper would have produced exactly
   the original, testbench-checked output stream.

Coverage (11 traces, about 1.85 million cycles):

- The ISAP team's official v1 KAT, AEAD records only (648 messages, 0-32 bytes).
  The golden run takes 269,948 cycles, the same count the partner's Vivado
  run reported.
- 288 extra messages from the ISAP team's own generator script
  (`vectors/gen_vectors.py`): every block-boundary length, random lengths to
  200 bytes, messages up to 1,500 bytes, with and without key reuse. The
  original design passes all of them, which cross-checks the vectors.
- 23 forged tags (`vectors/corrupt_tags.py`); the core must reject each one
  and release no plaintext.
- Each set both without stalls (mode 0) and with stalls on inputs and
  outputs (mode 1).

The checker was itself tested by planting three bugs in the core (missing
domain separation, a missing padding bit, accepting any tag). Each one was
caught.

**Limit:** this check requires the core to be cycle-exact with the original.
That holds for every iteration so far. A change that alters the cycle count
(for example a smaller round that takes more cycles) needs the full
testbench instead: `vivado/sim_kat_xsim.sh` or the partner's PowerShell
`run_aead_regression.ps1`.

## 2. Get the real numbers in Vivado

From the repository root:

```bash
vivado -mode batch -source OptimizedHardware/vivado/build_all.tcl
```

On Windows, run the same line in the Vivado Tcl Shell. This builds the
reference VHDL, the baseline port, every iteration and the final core (core
alone and inside the LWC wrapper). Each build is synthesized, placed and
routed for xc7a12tcsg325-3 at 100 MHz. The script writes
`vivado/results/summary.csv` (LUTs, FFs, slices, WNS, WHS, Fmax) and the full
reports per design. Copy the numbers into `ITERATIONS.md`.

A single design: `vivado -mode batch -source OptimizedHardware/vivado/build.tcl -tclargs opt core`,
or in the Vivado Tcl Shell: `source OptimizedHardware/vivado/build.tcl`, then
`build_one opt core` (repeat `build_one` for more designs).

**About timing.** The old `core_area.xdc` gave every core port a zero input
and output delay. That caused the "timing constraints are not met" critical
warning: paths straight from an input port into a register failed hold
by 0.379 ns. These scripts constrain only the clock, so all
register-to-register paths inside the core are fully timed. The core's ports
are timed in the `wrapper` builds, where they are internal. The scripts stop
with an error if a routed design has negative setup or hold slack.

## 3. GUI project

In Vivado: Tools > Run Tcl Script > `OptimizedHardware/vivado/create_project.tcl`.
Then open `OptimizedHardware/vivado/isap_opt/isap_opt.xpr` and Run
Implementation.

This project contains only the optimized sources. The old project listed both
the original `CryptoCore.vhd` and the SV binding, which define the same
entity name `CryptoCore_2pass`. Simulation could pick either one.

## 4. The iteration loop

1. Ask the AI tool for one specific change to `rtl/crypto_core_2pass_opt.sv`.
   Give it the "Rules" section of `ITERATIONS.md`.
2. `verif/check_core.sh opt`. It must pass every trace. If it fails, the
   first `MISMATCH` line names the cycle and signal.
3. `verif/estimate_area.sh opt` for a quick LUT/FF estimate and the
   register-to-register logic depth (optional; needs `sv2v` and Yosys, e.g.
   `pip install yowasp-yosys`). Depth must not exceed the baseline's 11.
4. Keep it? `mkdir iterations/it6_<name>`, copy the `.sv` there, add it to
   the `runs` list in `vivado/build_all.tcl`, and log it in `ITERATIONS.md`.
   Drop it? Copy the previous snapshot back into `rtl/`.
5. Vivado numbers: `build.tcl -tclargs it6_<name> core`.

## Tools used here

GHDL 4.1, Verilator 5.020, Yosys 0.71 (yowasp), sv2v 0.0.13, and cryptotvgen
from `software/cryptotvgen` (only needed to regenerate `vectors/kat_extended`).
Vivado was not available while preparing this folder; the Vivado scripts
were dry-run for control flow only, so run `build.tcl` once on one design
before relying on `build_all.tcl`.
