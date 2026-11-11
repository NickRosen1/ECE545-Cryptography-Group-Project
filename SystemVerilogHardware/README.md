# ISAP-A-128A SystemVerilog port

Stages 1 and 2 are complete. Stage 3 regression, rejection testing, cycle
comparison, and synthesis have run; inherited upstream limitations are recorded
in [STAGE3_RESULTS.md](STAGE3_RESULTS.md). The 32-bit ISAP-A-128A core and its
Ascon-p round are implemented in SystemVerilog and tested through the VHDL wrapper.
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
active AEAD round counts. The round uses the 64-bit byte
reversal helper. Other data-format and padding helpers are included in the
Stage 2 core. Standalone Ascon-Hash and other ISAP variants are outside the port.

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

## Reproduce Stage 2

The 32-bit AEAD core is `crypto_core_2pass_sv`. The separate Vivado build
uses `rtl/crypto_core_2pass_binding.vhd` in place of the original core.
The upstream wrapper binds to that adapter and the adapter binds to the
SystemVerilog module. Each design uses a separate work directory.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_smoke.ps1 -Reference
```

The runner reuses the VHDL testbench and a subset of the original AEAD test
vectors. Default mode 4 emits per-message cycle counts. Use `-TestMode 1`
for stalls on both stimulus and output, or `-VivadoBin` for another Vivado
installation. See [STAGE2_RESULTS.md](STAGE2_RESULTS.md) for results.

## Reproduce Stage 3

Run these commands from the repository root with Vivado 2024.2 installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_invalid_tags.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_stage3_synthesis.ps1
```

Each command defaults to both `reference` and `systemverilog`. Pass
`-Designs reference` or `-Designs systemverilog` to run one configuration.
All three accept `-VivadoBin 'C:/Xilinx/Vivado/2024.2/bin'`. Synthesis accepts
`-ClockPeriodNs 10.0` (the default). These runs needed execution outside the
Codex sandbox, as established in Stages 1 and 2.

The regression selects all 648 AEAD records (324 encryptions, 324 decryptions)
by original message ID, validates their SDI key associations, and excludes
648 standalone hashes. It preserves all original INS/HDR/DAT/STT words and
original order; only overflowing diagnostic `# TB :` comments are normalized
to the bench's fixed-width fields. `reports/stage3/selection.csv` retains the
full original IDs; `excluded_hash.csv` lists every excluded message.

Default modes are 0 (normal handshakes) and 1 (three-cycle PDI, SDI, and DO
stalls). An added passive monitor records cycles from each message's accepted
first PDI word to its accepted status word, without serializing transactions.
The original LWC testbench checks all expected outputs. All 648 per-message
cycle counts match between designs in both modes. `-Modes 4` remains available
as a diagnostic, but the upstream isolated timing mode deadlocks at message 20
in both implementations; it is not part of the passing full regression.

The invalid-tag runner uses original messages 7 (15-byte plaintext) and 6
(empty plaintext), flipping tag bits 127, 64, and 0. Both cores reject all
three modifications without releasing plaintext, including seven cycles of
authentication acknowledgement backpressure. The unchanged wrapper returns
failure status for empty messages but stalls after the plaintext header for
nonempty rejected messages. The runner explicitly reports this as
`WRAPPER_LIMITATION`, not successful protocol completion. Both core and
external FIFO are reset between cases; rejected ciphertext is not flushed
automatically. See the results report before integrating this wrapper.

The synthesis top is `LWC_2pass` for both designs, with identical part,
out-of-context synthesis settings, and clock/I/O constraints. The external
payload FIFO is **excluded**; the wrapper's internal header FIFO is included.
The unchanged reference also retains its standalone hash logic; the SV core
is AEAD-only, so utilization differences are not solely a language comparison.
Reports are **post-synthesis**, with no placement or routing. Both builds have
positive setup slack but negative hold slack under the zero-delay I/O model;
the reference also has 320 inferred latches and unconstrained latch endpoints.

Builds use unique directories under `build/stage3/` to avoid stale results and
mixed-language binding collisions. Reproducible command logs, selected-ID maps,
per-message cycle CSVs, simulation logs, utilization, timing, and DRC reports
are saved under `reports/stage3/`. The regression requires explicit completion,
648 cases, 5,184 matched output words, empty failure output, and 648 timing rows;
timeouts and partial runs cannot pass.

Next concrete follow-up: repair nonempty authentication-failure completion and
FIFO flushing in a separately derived integration, and resolve the upstream
empty-AD dependency before treating isolated timing mode as a full benchmark.
Keep the preserved baseline available for comparison. Physical timing closure
requires board/top-level I/O and clock assumptions followed by implementation.

## Attribution and license

The round translation retains attribution to Robert Primas, copyright (c)
2020 IAIK, Graz University of Technology, Austria. The byte-reversal helper
retains attribution to Michael Tempelmeier and Patrick Karl, copyright (c)
2019 Chair of Security in Information Technology, ECE Department, Technical
University of Munich, Germany. The translated source is marked as modified
on 2026-11-10 and carries the original GPL and TSU notices. See the unchanged
repository [LICENSE.txt](../LICENSE.txt) for GNU GPL v3 terms and the upstream
[README.md](../README.md) for project and LWC API acknowledgements.
