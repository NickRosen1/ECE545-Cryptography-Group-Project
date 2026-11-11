# Stage 3 results - 2026-11-10

The full AEAD regression, invalid-tag tests, per-message cycle comparison, and
Artix-7 synthesis have been executed for both the original VHDL and SV port.
All valid AEAD vectors and cycle comparisons pass. Invalid tags release no
plaintext, but an inherited wrapper defect prevents failure-status completion
for nonempty rejected messages. Synthesis completes; post-synthesis hold timing
is not closed, and the original VHDL infers 320 latches. These are limitations,
not passing checks or missing tool dependencies.

No core RTL correction was required in Stage 3: no port-introduced functional
or cycle-count discrepancy was found. Upstream sources, vectors, license, and
`hardware/isap_lwc/Makefile` remain unchanged. Stage 2's existing absorption
default already avoids the latches found in the original source.

## Tool, commands, and saved state

Vivado/XSim **2024.2**, SW build **5239630**, installed at
`C:/Xilinx/Vivado/2024.2/bin`. Device support and synthesis licensing for
`xc7a12tcsg325-3` were available. Runs used native Windows tools outside the
sandbox because of the simulator execution failures established in Stages 1–2.
No new tools were installed. Final-audit Git HEAD:
`dc336d1d7151d5f0c2409df552c2d1f2b2e1be55`.

These commands were actually run from the repository root; the final successful
versions produced the saved reports:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_regression.ps1 *> ./SystemVerilogHardware/build/stage3/regression-console.txt
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_invalid_tags.ps1 *> ./SystemVerilogHardware/build/stage3/tags-console.txt
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_stage3_synthesis.ps1 *> ./SystemVerilogHardware/build/stage3/synthesis-console.txt
```

The scripts create their own build directories; omit the redirections on a
fresh checkout if `build/stage3/` does not exist. All scripts accept
`-VivadoBin`; synthesis accepts `-ClockPeriodNs`, default 10 ns. Every simulator
and synthesis command, including absolute source paths and options, is saved
in the `*-commands.txt` files under `reports/stage3/` and in each synthesis
report directory's `commands.txt`.

Additional diagnostic invocations actually run included:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_regression.ps1 -Designs systemverilog -Modes 4 *> ./SystemVerilogHardware/build/stage3/sv-mode4-diagnostic.txt
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_stage3_synthesis.ps1 -Designs systemverilog *> ./SystemVerilogHardware/build/stage3/synthesis-sv-console.txt
git diff --exit-code -- hardware LICENSE.txt README.md
git diff --check
git status --short
```

The first, earlier regression invocation used an initial default that included
mode 4 and exposed the reference timeout described below. The final runner
defaults to modes 0 and 1. Reported final synthesis numbers come from the last
**both-design** run with corrected I/O constraints, not the preliminary runs.

On resume, the saved logs showed that the four regression runs, both core and
wrapper tag suites, and both corrected synthesis jobs had finished. Their
explicit completion markers and reports were inspected rather than repeating
already completed checks. This report and README were then completed. Files
are saved in the working tree; no commit was made by this Stage 3 work.

## Full AEAD regression

Source dataset: `hardware/isap_lwc/KAT/v1/{pdi,sdi,do}.txt`, identified by
`hardware/isap_lwc/v1.toml`. Of 1,296 original messages:

| Class | Count |
| --- | ---: |
| ISAP-A-128A encryption | 324 |
| ISAP-A-128A decryption | 324 |
| Excluded standalone Ascon-Hash | 648 |

The selected records cover AD and plaintext/ciphertext lengths from 0 through
32 bytes as represented in the upstream set, including partial words/blocks.
Selection uses the original `#### MsgID` records and actual operation words,
not the overflowing encoded testbench comments. Each PDI record must have a
matching SDI and DO record with the same original key ID and an Activate Key
instruction. This dataset has no key reuse; every selected message has its
original key load. Original order and all bus words are preserved and checked
by the runner. No expected ciphertext, plaintext, tag, or status is regenerated.

The upstream generator allows its nominal eight-bit message/key IDs to grow
beyond eight bits in `# TB :` comments; the VHDL bench only reads 20 bits.
The runner changes only these diagnostic comments to encode the correct
operation and message/key IDs modulo 256. Full original IDs remain authoritative
in [selection.csv](reports/stage3/selection.csv), the timing metadata, and
per-message result CSVs. [excluded_hash.csv](reports/stage3/excluded_hash.csv)
lists all 648 excluded hash IDs.

Each configuration uses the existing VHDL `LWC_TB`, `LWC_2pass`, PreProcessor,
PostProcessor, and payload FIFO. The original UUT source is copied into the
isolated build with only a passive monitor instance appended; the original
file is untouched. The SV build substitutes the Stage 2 VHDL binding entity
for the original core. Sources behind Windows Git symlink-text files are read
from their real upstream locations.

| Design | Mode | Cases passed | Output words matched | Total bench cycles |
| --- | --- | ---: | ---: | ---: |
| Original VHDL | 0, normal | 648 | 5,184 | 269,948 |
| SystemVerilog | 0, normal | 648 | 5,184 | 269,948 |
| Original VHDL | 1, stalls | 648 | 5,184 | 301,115 |
| SystemVerilog | 1, stalls | 648 | 5,184 | 301,115 |

Thus 2,592 message executions and 20,736 expected output-word comparisons pass
across these four runs. Each run checks original expected CT/PT, encryption
tags, and success status (`E0000000`) including `do_last` on status words.
The invalid-tag suite separately verifies rejection behavior.

Settings are identical: 10 ns clock, 1 ps simulation resolution, seed 1,
deterministic stalls of three cycles on PDI valid, SDI valid, and DO ready in
mode 1. Mode 0 has no deliberate stalls. The bench resets the wrapper and the
external FIFO before the stream. The payload FIFO is 1,024 x 32 bits (4 KiB).

Every run uses a new GUID-named build directory. Passing requires the explicit
bench PASS marker, no error/failure markers, exactly 648 cases and 5,184 matched
words, empty `failed_testvectors.txt`, result code 0, and the passive monitor's
648-row completion marker. The upstream inactivity watchdog is 10,000 cycles;
the Tcl run is bounded at 100 ms. A timeout, stale file, or partial stream cannot
satisfy these checks. See [regression.json](reports/stage3/regression.json) for
the successful run directories and `*-mode0.log` / `*-mode1.log` for raw output.

## Cycle comparison and isolated timing limitation

The passive monitor measures from acceptance of each original message's first
PDI word (Activate Key) to acceptance of its status (`do_valid && do_ready &&
do_last`). It reads original message IDs and PDI word counts from generated
metadata and checks all input/output transactions complete. It does not delay
or modify any handshake. Transactions may overlap; these are stream-observed
transaction latencies, not isolated single-message benchmark times.

| Settings | Messages compared | Nonzero SV-minus-VHDL deltas | Latency range, both designs |
| --- | ---: | ---: | ---: |
| Normal stream | 648 | 0 | 251–739 cycles |
| Stalled stream | 648 | 0 | 296–811 cycles |

Every original message ID and both measured cycle counts are saved in
[mode0-cycle-comparison.csv](reports/stage3/mode0-cycle-comparison.csv) and
[mode1-cycle-comparison.csv](reports/stage3/mode1-cycle-comparison.csv).
The sums of individual latencies are 391,605 and 427,135 cycles respectively;
because transactions overlap, these differ from total bench elapsed cycles.
No port-introduced timing differences were found.

**Upstream isolated mode 4 does not complete the full dataset.** Both designs
time out at original message **20**, the 11th selected AEAD record (AD length 0,
PT length 31), after ten completed messages and 95 matched output words.
Both stop at simulation time 142,350 ns after 10,000 inactive cycles. Saved
evidence: `reference-mode4-limitation.log` and
`systemverilog-mode4-limitation.log` under `reports/stage3/`.

Source diagnosis: `ISAP_MAC_WAIT_INPUT` waits for `bdi_valid` or `key_valid` to
decide whether to absorb AD or padding. With empty AD, later input/key activity
can supply this indication in a continuous stream. Mode 4 blocks the next
transaction until the preceding status arrives, producing a circular wait.
This behavior is present in the original VHDL and was preserved by the port.
The final full comparison therefore uses the passive stream measurement above.
Stage 2's eight isolated timing cases remain historical results; they do not
cover this failing message.

## Invalid-tag rejection and backpressure

`run_invalid_tags.ps1` extracts its fixtures directly from original message 7
(KeyID 3, AD 1 byte, CT/PT 15 bytes) and message 6 (KeyID 2, empty CT/PT). A
128-bit tag is represented with bit 127 first on the wire. Each negative case
flips exactly one of bits **127**, **64**, or **0**, near the beginning, middle,
and end; nonce, key, AD, and ciphertext stay unchanged.

The direct core test uses the real upstream 1,024-word FIFO via
`stage3_core_dut.vhd`. Each case asserts active-high synchronous reset for four
clock edges on **both core and FIFO**, then loads the original key and inputs.
An assertion checks that no plaintext-valid signal occurs anywhere before
successful authentication acknowledgement. `msg_auth_ready` stays low for
seven full rising edges after `msg_auth_valid`; status/valid must remain stable
and no plaintext may appear. Ready is then asserted for acknowledgement.

Results are identical for VHDL and SV:

| Case | Authentication | Plaintext released | FIFO after case |
| --- | --- | --- | --- |
| Valid message 7 control | Success | 4 words, 15 valid bytes; matches original PT | Empty, 4 reads |
| Tag bit 127 flipped | Failure | 0 words | 4 ciphertext words, 0 reads |
| Tag bit 64 flipped | Failure | 0 words | 4 ciphertext words, 0 reads |
| Tag bit 0 flipped | Failure | 0 words | 4 ciphertext words, 0 reads |

Negative cases monitor another 64 cycles after acknowledgement. The FIFO is
not automatically drained on rejection, so resetting only the core would be
insufficient preparation for a fresh independent test. These tests reset both
between every case; they do not claim recovery without reset.

The wrapper test also uses the unchanged `LWC_TB_2pass_uut` and actual FIFO,
with output ready asserted only once in four cycles. It sends original PDI/SDI
words, changing only the chosen tag bit, and observes 2,000 cycles per case:

- Valid message 7 emits the exact original plaintext and `E0000000` status.
- All three corrupted message-6 tags emit the zero-length plaintext header
  and **`F0000000` failure status**, with no plaintext.
- All three corrupted message-7 tags emit only header `4300000F`, **no plaintext
  data and no failure status**. Both implementations exhibit this limitation.

The source explains the nonempty failure: the shared PostProcessor's
`S_OUT_MSG` acknowledges `auth_valid` but only advances when the last plaintext
flit transfers. A rejecting core intentionally produces no plaintext. That
state also does not capture the failed `auth_success` value; `S_VERIFY_TAG`
does, explaining why the empty-message path returns failure correctly. This
upstream integration defect was diagnosed, not changed or disguised as a pass.

Per design, 4 core cases and 7 wrapper cases ran: 22 dedicated executions total
across both designs. Their completion markers distinguish successful checks
from the 6 observed nonempty-wrapper limitations. A 1 ms simulation watchdog
and required final markers detect hangs in the test drivers. Raw evidence is
in `*-invalid-tags.log`, `*-invalid-tags-wrapper.log`, and their command logs.

## Artix-7 synthesis

Both designs synthesized successfully with matching settings:

- Top **`LWC_2pass`**, part **`xc7a12tcsg325-3`**.
- `synth_design -flatten_hierarchy rebuilt -mode out_of_context`; two tool
  threads, VHDL 2008, SystemVerilog enabled for the port. No area tuning.
- Configurable clock period, **10 ns default and used**. No applicable project
  XDC was reused. Both runs use the same generated clock/I/O constraints:

```tcl
create_clock -name clk -period 10 [get_ports clk]
set_input_delay -clock clk 0.0 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 0.0 [all_outputs]
```

The I/O delays are comparison assumptions, not board timing specifications.
The script now verifies that no input/output delays are missing. No pins,
board voltage, or physical clock-buffer location are assumed.

**The external payload FIFO is excluded from BOTH utilization reports.** Both
include the identical PreProcessor, PostProcessor, key/data width adapters,
and internal one-entry header FIFO beneath `LWC_2pass`. The SV core has its
VHDL language-binding hierarchy beneath `Inst_Cipher`; both use the same
flattening policy and wrapper boundary. The original reference retains its
hash logic; the SV core is AEAD-only. This is not a pure language-efficiency
or area-optimization comparison.

| Post-synthesis measurement | Original VHDL | SystemVerilog |
| --- | ---: | ---: |
| Slice LUTs | 2,573 | 1,670 |
| Flip-flops | 1,047 | 1,028 |
| Latches | 320 | 0 |
| Total slice registers | 1,367 | 1,028 |
| Occupied slices | Not available before placement | Not available before placement |
| BRAM tiles / RAMB18 / RAMB36 | 0 / 0 / 0 | 0 / 0 / 0 |
| DSPs | 0 | 0 |
| Black boxes | 0 | 0 |
| Worst setup slack, ns | +3.535 | +3.543 |
| Total negative setup slack, ns | 0.000 | 0.000 |
| Worst hold slack, ns | **-0.224** | **-0.224** |
| Total negative hold slack, ns | -71.847 | -72.555 |
| Hold-failing endpoints | 371 | 363 |
| Unconstrained internal endpoints | 320 | 0 |

These are **post-synthesis**, unplaced/unrouted estimates. The tool reports
that timing constraints are **not met** because of hold violations; positive
setup slack is not timing closure. The worst hold path in each design runs
from `sdi_data[24]` to key-state bit 0, with zero input delay, no intervening
logic, and estimated clock skew. Physical clock and I/O timing plus placement,
routing, and hold repair are needed before drawing board-level conclusions.
`HD.CLK_SRC` is unset in this out-of-context build, so clock delay/skew is not
anchored to a physical top-level clock buffer.

The VHDL latches are `Inst_Cipher/isap_state_n_s_reg[0..319]`. In upstream
`CryptoCore.vhd` process `p_CASE2`, the AD/CT branches do not assign the candidate
state when `word_idx_s >= BLOCK_WORDS_C`, inferring level-sensitive storage.
Those latch enables derive from state logic, not a defined clock: the timing
report has 320 unconstrained internal endpoints and 1,920 no-clock checks.
The quoted VHDL setup slack therefore excludes a fully constrained analysis of
that logic. The Stage 2 SV absorption process supplies the current state as
default and only absorbs within the rate, producing zero latches. Active AEAD
data/cycle equivalence is supported by the simulations, not a formal netlist
equivalence proof or post-synthesis functional simulation.

Other warnings were reviewed:

- Original core sensitivity lists omit some read signals; the shared
  PostProcessor omits `nx_decrypt`. Synthesis includes the combinational
  dependencies, so these are potential RTL/synthesis simulation differences
  in upstream code. No discrepancy appeared in the executed regressions.
- Unused width-adapter clock/reset ports, reserved fields, `bdi_pad_loc`,
  and AEAD-only `hash_in`/`bdi_size` are expected for this configuration.
- DRC reports `CFGBVS-1` because no board configuration voltage was supplied.
- Final runs contain no critical warnings or errors. Empty latch/black-box
  queries and unavailable parallel-synthesis opportunities produce benign
  tool warnings. The script requires zero SV latches and zero black boxes;
  the diagnosed 320 reference latches remain explicitly recorded.

Raw reports are in `reports/stage3/synthesis/{reference,systemverilog}/`:
`utilization.rpt`, `hierarchy.rpt`, `post_synth_timing.rpt`,
`post_synth_paths.rpt`, `post_synth_drc.rpt`, `latches.txt`,
`constraints.xdc`, `synthesis_summary.txt`, `vivado.log`, and `commands.txt`.
Checkpoints remain in separate ignored `build/stage3/synthesis/` directories.

## Development failures, limitations, and handoff

Intermediate verification/build issues were corrected and affected checks
rerun: Tcl source paths containing spaces needed list quoting; a mixed-language
diagnostic integer port was changed to a 32-bit vector; a nested timing-monitor
architecture was replaced by a directly attached passive instance after it
disturbed simulation; a PowerShell log-pattern argument was made explicit.
The first synthesis constraints used `remove_from_collection`, which Vivado
rejected inside XDC. The final runs use `get_ports -filter` above and check
that all I/O delay constraints apply. Preliminary unconstrained-I/O timing
reports were superseded; this table uses only the corrected run.

There is no outstanding simulator/device/license blocker. Implementation and
post-route checks were not requested or run. `make v1`, standalone hash tests,
other ISAP variants, formal equivalence, and post-synthesis functional
simulation were not run in Stage 3. No area optimization was performed.

New Stage 3 files comprise `stage3_common.ps1`, `run_aead_regression.ps1`,
`run_invalid_tags.ps1`, `run_stage3_synthesis.ps1`, `synth_stage3.tcl`,
`tb/lwc_timing_monitor.vhd`, `tb/stage3_core_dut.vhd`,
`tb/tb_invalid_tag.sv`, `tb/tb_invalid_tag_wrapper.sv`, this report, and
`reports/stage3/`. README is updated. Generated adapters, vectors, SV includes,
and build products stay under `SystemVerilogHardware/build/`.
Source fingerprints are saved in
[source_fingerprints.csv](reports/stage3/source_fingerprints.csv).

**Next concrete follow-up:** implement a separately derived wrapper failure
path that emits failure status without awaiting plaintext, and explicitly
flushes rejected ciphertext before another transaction; retain the original
configuration as the baseline. Separately repair the empty-AD completion
dependency before requiring full isolated mode-4 timing. For FPGA deployment,
establish board/top-level timing and clock assumptions, then place/route and
resolve hold timing. The current work does not claim these inherited issues
are fixed.
