# Stage 1 results — 2026-11-10

Completed only the Ascon-p round port. Repository baseline HEAD:
`a2616361a81f208c131ba32095e7fa25a6aa4d63`.

## Saved files

| New file | Purpose |
| --- | --- |
| `rtl/asconp.sv` | Synthesizable combinational `asconp_sv` and byte-reversal helper |
| `tb/asconp_vhdl_ref.vhd` | Adapter instantiating the original VHDL round |
| `tb/tb_asconp_equiv.sv` | Direct mixed-language comparison suite |
| `run_round_equivalence.ps1` | Isolated Vivado run and optional Icarus RTL compile |
| `.gitignore` | Excludes generated `build/` artifacts |
| `README.md` | Interface, reproduction, attribution, and Stage 2 handoff |
| `STAGE1_RESULTS.md` | This saved validation record |

No upstream files were modified. Changes are saved in the working tree; no
Git commit was made. No new SystemVerilog files were placed outside this tree.

## Commands and outcomes

Read the `v1.toml` manifest, `v1/design_pkg.vhd`, `v1/CryptoCore.vhd`, upstream
Makefile, configuration/packages, README, and license. Used `rg --files`,
`Get-Command`, and installation-directory searches to locate simulators.

```powershell
& C:/iverilog/bin/iverilog.exe -V
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_round_equivalence.ps1
git diff --exit-code -- hardware LICENSE.txt README.md
git status --short
```

The successful runner invoked, from `SystemVerilogHardware/build/round_equivalence/`:

```text
xvhdl --2008 <v1/design_pkg.vhd> <LWC_config_32.vhd> <hardware/LWC_rtl/NIST_LWAPI_pkg.vhd> <v1/CryptoCore.vhd> <tb/asconp_vhdl_ref.vhd>
xvlog --sv <rtl/asconp.sv> <tb/tb_asconp_equiv.sv>
xelab work.tb_asconp_equiv -s asconp_equiv --timescale 1ns/1ps
xsim asconp_equiv -runall -log equivalence.log
iverilog -g2012 -Wall -s asconp_sv -t null <rtl/asconp.sv>
```

The runner supplies absolute paths for the abbreviated source paths above.

- **PASS:** Vivado Simulator/XSim 2024.2, SW build 5239630; compilation,
  mixed-language elaboration, and 81,504 bit-for-bit comparisons. No mismatches
  or unknown outputs. The test finished at simulation time 81,504 ns.
- **PASS:** Icarus Verilog 14.0 (devel) parsed/elaborated the RTL with SystemVerilog
  2012 enabled. It reported constant-select sensitivity limitations for
  `always_comb`, broadening sensitivity to whole vectors. This was a compile
  check, not a second equivalence simulation or synthesis run.
- **PASS:** `git diff --exit-code -- hardware LICENSE.txt README.md` was empty;
  the only new working-tree content was `SystemVerilogHardware/`.

Coverage breakdown:

| Stimulus | Comparisons |
| --- | ---: |
| Zero, ones, 0xaa, 0x55, ascending byte pattern and complement × 16 rcon values | 96 |
| 320 single-set and 320 single-clear states × 16 rcon values | 10,240 |
| 32 uniform S-box lane patterns × 16 rcon values | 512 |
| 4,096 deterministic random states × 16 rcon values | 65,536 |
| 256 initial states × (1 + 6 + 12) chained rounds | 4,864 |
| 256 changing random states at fixed rcon 6 | 256 |
| **Total** | **81,504** |

PRNG: xorshift32, seed `0x1a128a20`. Saved simulator log:
`build/round_equivalence/equivalence.log` (local ignored build artifact).
Its completion marker is:

```text
PASS: 81504 Ascon-p comparisons against original VHDL; seed=1a128a20
```

## Environment issues and checks not run

- Direct PowerShell script invocation was initially blocked by the machine's
  execution policy; running a separate PowerShell process with the shown
  `-ExecutionPolicy Bypass` option worked without a persistent policy change.
- The first sandboxed run compiled and elaborated successfully, but XSim Tcl
  initialization resolved the working directory with the `Desktop` component
  missing and failed before simulation. The same runner succeeded outside the
  sandbox after approval. No installation files were changed.
- GHDL and Verilator were not found on PATH. `wsl --list --quiet` was denied
  by the sandbox; WSL tools were not needed because native Vivado completed
  the reference comparison.
- `make v1` and full AEAD simulation were not run in Stage 1. The baseline
  flow is untouched. AEAD ready/valid/reset behavior, padding, cycle counts,
  encryption/decryption KATs, and invalid-tag rejection remain unverified
  until the controller/datapath is ported and integrated in Stages 2–3.
- Synthesis, implementation, timing, area, and availability of the target
  device support/license were not checked. Vivado is installed, but Stage 3
  must still synthesize the integrated design for `xc7a12tcsg325-3` and name
  its top. No standalone Ascon-Hash or other ISAP variant was ported.

## Source fingerprints (SHA-256)

These identify the exact working-tree bytes used in the successful run:

```text
hardware/isap_lwc/v1.toml
4FAEBA1CF372229602D910BD3329A74425AC5CF33A0AD4DF92DFBA758FC7B6AA
hardware/isap_lwc/src_rtl/v1/CryptoCore.vhd
62405DB85EC2507B694103BDF31902360434D7B70963E2AFAB98BF3828A49D12
hardware/isap_lwc/src_rtl/v1/design_pkg.vhd
FE75C69532764B9BA0AC95975045F78EA08F7D83959D1574D0422EB64DB4F078
SystemVerilogHardware/rtl/asconp.sv
03785EE21242956CD45981D4114D8DF80200A3BD63EF536C42FB688033E226C3
```

**Next concrete step:** port the AEAD-only `CryptoCore_2pass` port list,
constants/helpers, controller, and datapath into this directory, using
`asconp_sv`, then add the separate Vivado configuration that reuses the
upstream VHDL wrapper/testbench. See `README.md` for binding and checkout
details. Stop at this Stage 1 boundary until Stage 2 is requested.
