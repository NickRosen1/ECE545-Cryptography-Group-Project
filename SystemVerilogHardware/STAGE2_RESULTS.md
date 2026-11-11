# Stage 2 results

Ported the 32-bit, one-round-per-cycle ISAP-A-128A `CryptoCore_2pass`
controller and datapath. The core instantiates the Stage 1 `asconp_sv`
round. The original VHDL LWC wrapper, two-pass FIFO, and testbench are
used to verify the port. The AEAD core has a synchronous active-high reset.

| File | Purpose |
| --- | --- |
| `rtl/crypto_core_2pass.sv` | AEAD controller, datapath, and format helpers |
| `rtl/crypto_core_2pass_binding.vhd` | Binds the original LWC wrapper to the SystemVerilog module |
| `run_aead_smoke.ps1` | Isolated Vivado builds and smoke tests for the port and VHDL baseline |

Standalone Ascon-Hash and other ISAP variants are outside this port. The
core accepts the existing wrapper's port list, including compatibility
inputs. The absorption logic updates the candidate state only for a word
index within the rate. It uses the current state as the combinational
default outside that range.

## Reproduce

Run from the repository root using Vivado Simulator 2024.2.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_smoke.ps1 -Reference
powershell -NoProfile -ExecutionPolicy Bypass -File ./SystemVerilogHardware/run_aead_smoke.ps1 -TestMode 1
```

The runner selects eight original AEAD records by message ID, preserving their
PDI, SDI, and expected DO words. Mode 4 is the upstream testbench's timing
mode. Mode 1 stalls both stimulus and output. The runner uses `xvhdl --2008`,
`xvlog --sv` for the port, `xelab`, and `xsim -runall`. Logs and timing files
are under `build/aead_smoke/`. Use `-VivadoBin` to point to another installation.

## Verification

The port and the upstream VHDL baseline each passed the same eight AEAD
cases in mode 4, comprising five encryptions and three decryptions. The
per-message timing files matched byte for byte. The testbench finished each
timing run in 3,066 cycles.

| Message ID | Cycles in each design |
| ---: | ---: |
| 3 | 473 |
| 6 | 279 |
| 7 | 409 |
| 8 | 409 |
| 11 | 227 |
| 12 | 437 |
| 14 | 401 |
| 16 | 414 |

Mode 1 also passed all eight cases for both the SystemVerilog port and the VHDL baseline with stalls on input and output.
Vivado completed the runs outside the sandbox. Sandboxed elaboration failed
when XSim compiled generated C. The optional sandboxed Icarus compile of
the full core crashed after constant-select sensitivity warnings.

Stage 3 covers the full AEAD KAT regression, dedicated invalid-tag rejection,
and Artix-7 synthesis. The candidate full-wrapper top is `LWC_2pass`, which
exposes the two-pass FIFO interface. The payload FIFO in the testbench is
outside this top. `crypto_core_2pass_sv` is the core-only top.
