# ISAP-A-128A SystemVerilog port

Stage 1 is complete: a combinational Ascon-p round and a direct comparison
against the upstream VHDL round. The AEAD controller/datapath is not yet ported.
All new RTL, test code, adapters, scripts, and generated build files belong in
this directory. Upstream files and the `hardware/isap_lwc/Makefile` are unchanged.

## Reference and interface

`hardware/isap_lwc/v1.toml` selects the 32-bit `v1` implementation. Its reference
sources are `src_rtl/v1/design_pkg.vhd` and `src_rtl/v1/CryptoCore.vhd` relative
to `hardware/isap_lwc`. The round is the `Asconp` entity and `behavior`
architecture at the start of `CryptoCore.vhd`, using `reverse_byte` from
`design_pkg.vhd`.

The synthesizable module is `asconp_sv` in `rtl/asconp.sv`:

| Port | Direction | Meaning |
| --- | --- | --- |
| `state_in[319:0]` | Input | Five 64-bit lanes, x0 in bits 63:0 |
| `rcon[3:0]` | Input | Rounds remaining; four-bit modulo arithmetic |
| `state_out[319:0]` | Output | State after one combinational round |

The round's internal bus is 320 bits even though the enclosing AEAD core's
external data and key interfaces are 32 bits. Each lane is byte-reversed on
entry and exit. There are no registers, clock, reset, or handshake ports in
the original round or this port, and no pipeline latency has been added.

The controller must supply `12,11,...,1` for sH/sK, `6,5,...,1` for sE, and
`1` for sB. The round constant is `{15-t, t}`, where `t=(12-rcon) mod 16`;
for example, rcon 12 gives 0xf0, rcon 6 gives 0x96, and rcon 1 gives 0x4b.
All 16 binary rcon values retain the VHDL behavior, although only 1..12 are
active AEAD round counts. The only helper ported so far is the 64-bit byte
reversal used by the round. Other data-format and padding helpers belong to
Stage 2. Standalone Ascon-Hash and other ISAP variants are outside the port.

## Reproduce Stage 1

From the repository root on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_round_equivalence.ps1
```

The execution policy option applies only to that PowerShell process. For a
different installation, pass `-VivadoBin 'C:/path/to/Vivado/bin'` and optionally
`-Iverilog 'C:/path/to/iverilog.exe'`. The script also discovers tools from PATH
or `XILINX_VIVADO`, with this machine's Vivado 2024.2 path as a fallback.

The script uses `xvhdl --2008`, `xvlog --sv`, `xelab`, and `xsim -runall`.
The SV testbench instantiates both `asconp_sv` and `asconp_vhdl_ref`; the VHDL
adapter binds explicitly to the original `work.Asconp(behavior)`. The complete
original `CryptoCore.vhd` is compiled unchanged, but only its Asconp entity is
elaborated. There is no second hand-translated oracle. The script compiles
`hardware/LWC_rtl/NIST_LWAPI_pkg.vhd` directly because its manifest entry is a
Git symlink that may be checked out as a text file on Windows.

Each comparison checks all 320 output bits and rejects unknown outputs. The
suite uses directed patterns, all single-set/single-clear state bits, all 32
uniform S-box lane patterns, deterministic random states, independent feedback
chains for the AEAD round schedules, and fixed-rcon state changes. It requires
exactly 81,504 comparisons and an explicit PASS marker. This is simulation
coverage, not an exhaustive formal proof over the 320-bit input space or a
comparison of VHDL's nine-state logic with SystemVerilog's four-state logic.

Build products and simulator logs are in `build/round_equivalence/` (ignored by
Git). `STAGE1_RESULTS.md` records the completed run and its limitations.

## Resume at Stage 2

Next concrete step: port the AEAD-only `CryptoCore_2pass` entity/architecture
from `hardware/isap_lwc/src_rtl/v1/CryptoCore.vhd`, starting with its exact port
list and `design_pkg` constants/helpers, and instantiate `asconp_sv` for its
one-round combinational datapath. Preserve the existing 32-bit interface,
active-high synchronous core reset, ordering, padding, handshake behavior,
round scheduling, authentication decision, and AEAD cycle counts. Exclude the
hash state paths and Keccak/other ISAP variant logic. Keep any wrapper-required
hash interface compatibility separate from implementing hash functionality.

Then add a **separate** Vivado mixed-language configuration under this directory
to reuse the VHDL LWC wrapper and testbench. Keep the VHDL adapter and SV core
names distinct to avoid accidental binding to the original core. Preserve
`cd hardware/isap_lwc; make v1` as the upstream baseline; do not overwrite its
manifest, Makefile, RTL, wrappers, or test vectors.

Two checkout details matter for that configuration:

- Resolve checked-in symlink targets when the checkout contains symlink text.
  The Stage 1 runner demonstrates this for the NIST package.
- `v1.toml` lists `src_tb/v1/LWC_config_tb.vhd`, while the actual file and
  Makefile use `src_tb/v1/LWC_TB_config.vhd`. Reference the existing actual file
  in the separate configuration without editing the upstream manifest.

Stage 3 will run original AEAD KAT inputs/expected outputs for encryption,
valid decryption, and invalid-tag rejection, followed by synthesis for
`xc7a12tcsg325-3` if available. The current round module is not the final AEAD
synthesis top. The upstream full-wrapper top is `LWC_2pass`; establish and
document the corresponding mixed-language synthesis top in the later stage.
No area optimization is included in this port.

## Attribution and license

The round translation retains attribution to Robert Primas, copyright (c)
2020 IAIK, Graz University of Technology, Austria. The byte-reversal helper
retains attribution to Michael Tempelmeier and Patrick Karl, copyright (c)
2019 Chair of Security in Information Technology, ECE Department, Technical
University of Munich, Germany. The translated source is marked as modified
on 2026-11-10 and carries the original GPL and TSU notices. See the unchanged
repository [LICENSE.txt](../LICENSE.txt) for GNU GPL v3 terms and the upstream
[README.md](../README.md) for project and LWC API acknowledgements.
