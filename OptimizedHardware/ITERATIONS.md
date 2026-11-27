# Area-optimization log: ISAP-A-128A core

Starting point: `SystemVerilogHardware/rtl/crypto_core_2pass.sv`, the
straight SystemVerilog port of the ISAP team's 32-bit v1 `CryptoCore_2pass`
(AEAD only). Each iteration below is saved under `iterations/` so any step
can be rebuilt, compared or rolled back. `rtl/crypto_core_2pass_opt.sv` is
**iteration 7**, the smallest design measured.

AI tool for iterations 1-8: Claude (claude.ai chat, configured model
`claude-opus-5-5`). Add iterations from GPT-6 Astra / Claude Sonnet 5.5 below
in the same format.

## Rules every iteration follows

- **Cycle-exact.** The core must behave exactly like the original on every
  clock cycle at its ports (same handshakes, same latency, same outputs).
  That keeps the published throughput (2.75 cycles/byte for long messages)
  and lets the trace-replay check below be exact.
- **Verified before measured.** `verif/check_core.sh opt` must report
  `ALL TRACES MATCH THE ORIGINAL DESIGN` on all 11 golden traces (about 1.85
  million clock cycles: 648 official KAT messages, 288 extra messages up to
  1,500 bytes, 23 forged-tag rejections, with and without stalls).
- **No timing regression.** Logic depth between registers must not grow.

## Vivado results (2025.1, xc7a12tcsg325-3, 100 MHz, placed and routed)

Every build met timing (positive WNS and WHS). Fmax = 1000 / (10 - WNS).
Throughput for long-message encryption = 8 x Fmax / 2.75 Mbps, since the
cycle count is unchanged. "Step" = LUT change from the iteration it was built on.

| Design | Top | LUTs | Step | FFs | Slices | WNS (ns) | Fmax (MHz) | Mbps | Mbps/LUT |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reference (ISAP team VHDL, with Ascon-Hash, 320 latches) | core | 2,359 | | 1,284 | 731 | 2.619 | 135.5 | 394 | 0.167 |
| baseline (straight SV port) | core | 1,488 | | 949 | 456 | 3.200 | 147.1 | 428 | 0.288 |
| it1 narrow counters | core | 1,518 | +30 | 943 | 471 | 3.270 | 148.6 | 432 | 0.285 |
| it2 static y | core | 1,577 | +59 | 942 | 480 | 1.691 | 120.4 | 350 | 0.222 |
| it3 shared absorb | core | 1,477 | -100 | 946 | 441 | 3.074 | 144.4 | 420 | 0.284 |
| it4 shared outputs (on it3) | core | 1,434 | -43 | 942 | 429 | 2.234 | 128.8 | 375 | 0.261 |
| it5 explicit state mux (on it3) | core | 1,308 | -169 | 942 | 412 | 3.004 | 142.9 | 416 | 0.318 |
| it6 = it5 without it2 | core | 1,327 | +19 | 943 | 426 | 3.234 | 147.8 | 430 | 0.324 |
| **it7 = it5 plus it4 = opt (final)** | core | **1,250** | **-58** | **942** | **394** | 3.177 | 146.6 | 426 | 0.341 |
| it8 = it6 plus it4 | core | 1,304 | -23 | 942 | 438 | 3.590 | **156.0** | **454** | **0.348** |
| reference | wrapper | 2,566 | | 1,360 | 808 | 2.443 | 132.3 | 385 | 0.150 |
| baseline | wrapper | 1,653 | | 1,028 | 513 | 2.978 | 142.4 | 414 | 0.251 |
| it5 (earlier opt) | wrapper | 1,431 | | 1,022 | 465 | 2.932 | 141.5 | 412 | 0.288 |
| **opt (it7, final)** | wrapper | **1,400** | | 1,022 | **457** | 3.113 | 145.2 | 422 | 0.302 |

**Core alone, baseline to final (it7): -238 LUTs (-16.0%), -62 slices
(-13.6%), Fmax essentially unchanged (146.6 vs 147.1 MHz, -0.3%), throughput
per LUT +18.6%.** Inside the LWC wrapper, baseline to final: -253 LUTs
(-15.3%), -56 slices (-10.9%), Fmax +2.0% (145.2 vs 142.4 MHz).

it8 is the best on speed and efficiency instead: 156.0 MHz (+6.1% over
baseline), 454 Mbps, 0.348 Mbps/LUT (+21.0%), with -12.4% LUTs. The project
target is area, so it7 is the final design; it8 is worth one sentence in the
report as the speed/efficiency alternative.

The reference-to-baseline drop (2,359 to 1,488) is NOT optimization. It comes
from removing Ascon-Hash and from the port not reproducing the 320 latches
the original VHDL infers. Report it separately.

### What Vivado showed that the quick estimates did not

The Yosys estimates got the direction right for it3 and it5 only. For it1
and it2, Yosys predicted savings but Vivado measured increases (it2 also cost
about 28 MHz). For it4, Yosys predicted an increase but Vivado measured a saving
(at a cost of about 16 MHz). Lesson for the AI-analysis section: an AI tool's
"this saves area" claim, and even a free synthesis tool's estimate, must be
confirmed with the vendor tool on the real device.

The changes also **interact**: a change's effect depends on what else is in
the design. it2 (static y) measured +59 LUTs on its own, yet in the final
design removing it costs area (it5 to it6: +19 LUTs; it7 to it8: +54 LUTs and
+44 slices), while removing it speeds the design up (+4.9 and +9.4 MHz). it4
(shared outputs) cost 16 MHz on it3 but almost nothing on it5 (it5 to it7:
+3.7 MHz). So the order of measurements matters, and a step that looks bad
alone can be part of the best combination.

To see why it2 and it4 lowered Fmax, open
`vivado/results/it2_static_y_core/critical_paths.rpt` and
`vivado/results/it4_shared_outputs_core/critical_paths.rpt`.

## Quick Yosys estimates (for comparing iterations before running Vivado)

Yosys `synth_xilinx` estimates, used only to compare iterations quickly.
Vivado numbers (`vivado/build_all.tcl`) are the ones to report: Yosys counted
2,055 LUTs for the baseline where Vivado reported 1,505.

| Iteration | Change | Est. LUTs | vs baseline | Est. FFs | Max logic levels (reg to reg) | Traces |
|---|---|---:|---:|---:|---:|---|
| it0 | baseline copy | 2,055 | - | 972 | 11 | all match |
| it1 | narrower counters, 1-bit pad logic | 1,977 | -3.8% | 967 | 10 | all match |
| it2 | static y + 128:1 bit select | 1,965 | -4.4% | 968 | 10 | all match |
| it3 | one shared absorb datapath | 1,851 | -9.9% | 968 | 9 | all match |
| it4 | shared output XOR (set aside) | 1,906 | (+55 vs it3) | 968 | 9 | all match |
| it5 | explicit state-register mux | **1,772** | **-13.8%** | 943 | **9** | all match |
| it6 | it5 without it2 | 1,775 | -13.6% | 942 | 9 | all match |
| it7 | it5 plus it4 | 1,780 | -13.4% | 943 | 9 | all match |
| it8 | it5 without it2, plus it4 | 1,824 | -11.2% | 942 | 10 | all match |

(With Yosys's `-widemux 5` option, which uses MUXF7/F8 more like Vivado:
baseline 2,054, it5 1,718 = -16.4%.)

---

## it1: narrower counters (`iterations/it1_narrow_counters`)

**Change.** `word_idx_s` 3 bits to 2, `isap_cnt_s` 8 bits to 4, and the
permutation-input logic reduced to the single bit it actually changes.

**Why it is safe.** `word_idx_s` wraps at 3 at the latest (key, nonce and tag
are 4 words, a block 2), so it never reaches 4. `isap_cnt_s` is only ever
loaded with 12, 6 or 1 and every state that decrements it leaves when it
reaches 1, so its upper 4 bits were always 0. The "absorb 0x80" control case
XORs `0x80` into a byte, which only flips bit 7, the same bit the re-keying
case flips.

**Effect.** The state-word select (`isap_state_cur_word_s`, 32 bits) becomes
a 4:1 instead of an 8:1 multiplexer; counter compare and decrement logic shrinks.
Yosys estimated -78 LUTs, but **Vivado measured +30 LUTs** (Fmax unchanged).
Vivado was probably already trimming the unused counter bits and select
inputs, so the RTL change mostly reshuffled its mapping.

## it2: static y with bit select (`iterations/it2_static_y`)

**Change.** Re-keying absorbs a 128-bit value y one bit per permutation round.
The original copied y into a register and rotated it every round, so all 128
bits had a 3-input multiplexer (load nonce / load MAC state / rotate). Now
nothing moves: for the encryption key y is the nonce, read in place; for the
MAC key, y is captured once in `isap_ymac_s` (a plain load). The existing
round counter `isap_cnt_y_s` equals the index of the bit to absorb, so a
128:1 select picks it. The selected bit is registered one cycle early
(`ybit_q`) so the select is not added to the permutation's timing path.

**Effect.** Small in Yosys (-12 LUTs), but **worse in Vivado: +59 LUTs and
Fmax 148.6 to 120.4 MHz.** Two 128:1 selects plus a 7-bit next-count path
cost more than the 128 three-input multiplexers they replaced, and the new
select logic ended up on a slower path. Undone in it6.

## it3: one shared absorb datapath (`iterations/it3_shared_absorb`)

**Change.** The original built two complete pad-and-absorb datapaths (input
word from the FIFO during encryption's MAC, or from `bdi`), each producing a
full 320-bit candidate state, and chose between them. Now the 32-bit input
word and its flags (valid bytes, end of segment, partial) are chosen first,
and one pad-and-absorb datapath writes just the 64-bit rate.

**Effect.** Largest single LUT drop so far (-114) and one logic level shorter.

## it4: shared output XOR (`iterations/it4_shared_outputs`), set aside, then re-tested

**Change tried.** Compute `input word XOR state word` once and share it
between `bdo` (to the wrapper) and `fdo_data` (to the FIFO), and stop forcing
those data outputs to zero when their valid signal is low (the wrapper
ignores them then).

**Result.** Passed every trace. Yosys estimated it **larger** (+55 LUTs vs
it3), so it was not carried forward at first and it5 is built on it3. Vivado
measured it **smaller** (-43 LUTs) but slower (Fmax 144.4 to 128.8 MHz).
Re-tested on top of it5 as it7 and it8.

## it5: explicit state-register multiplexer (`iterations/it5_explicit_state_mux`)

**Change.** The 320-bit state register was written in 16 branches of the
FSM `case` statement, with different slices assigned in different states.
It is now updated in one separate `always_ff` block with one priority mux
per region and one-hot select signals computed once from the FSM state:

| Region | Sources |
|---|---|
| `[63:0]` | permutation, absorb, key, nonce |
| `[127:64]` | permutation, key, nonce |
| `[191:128]` | permutation, IV constant, saved MAC state |
| `[319:192]` | permutation, zero, saved MAC state, nonce, domain bit |

Every load and hold condition is exactly the original's, only written
differently, so synthesis sees a small mux per bit instead of a select chain
through the FSM decoding.

**Effect.** Vivado: **-169 LUTs vs it3, the largest single saving**, with
Fmax 142.9 MHz. (Yosys: -79, or -146 with `-widemux`.)

## it6: it5 without the static-y change (`iterations/it6_no_static_y`)

**Change.** The it2 change reversed on top of it5: y is again a 128-bit
register that is loaded and rotated, exactly as in it1. Everything else is it5.

**Why.** Vivado measured it2 as +59 LUTs and about -28 MHz on its own.
Verified: all traces match.

**Result.** Faster (147.8 MHz, +4.9) but **larger** (+19 LUTs, +14 slices)
than it5. In the full design the static y saves area after all.

## it7: it5 plus shared outputs (`iterations/it7_with_shared_outputs`)

**Change.** The it4 change (shared output XOR, no zero-forcing of data
outputs) applied on top of it5.

**Why.** Vivado measured it4 as -43 LUTs on it3. Watch Fmax: it4 alone cost
about 16 MHz. Verified: all traces match.

**Result. Smallest design measured: 1,250 LUTs, 394 slices, 146.6 MHz.**
-58 LUTs vs it5, and Fmax went *up* 3.7 MHz. Chosen as the final design.

## it8: both (`iterations/it8_no_static_y_shared_outputs`)

**Change.** it6 plus the it4 change. Verified: all traces match. Yosys rated
it the worst of the three.

**Result.** The **fastest** design (156.0 MHz) and the best throughput per
LUT (0.348), but 54 LUTs and 44 slices larger than it7.

## Ideas not yet tried

- Tool settings instead of RTL: Vivado `synth_design -directive
  AreaOptimized_high` and `opt_design -directive ExploreArea`, and
  `-fsm_extraction sequential` instead of one-hot. No RTL change and no
  re-verification needed; report it as a separate "tool-only" row.
- A narrower datapath for the round (for example half the S-boxes per cycle)
  would cut the ~650-LUT round function substantially but changes the cycle
  count. That breaks the exact trace replay, so verify it with the full KAT
  flow (`vivado/sim_kat_xsim.sh` or the partner's PowerShell regression).
- `fifo_words_s` is 16 bits (65,535-word messages); a smaller limit saves a
  little but changes the supported message length.
