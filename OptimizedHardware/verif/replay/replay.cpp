// replay.cpp - Replay a golden core-boundary trace into a SystemVerilog
// CryptoCore (Verilator model "Vdut") and check its outputs every cycle.
//
// The trace was recorded from the ORIGINAL VHDL core running inside the real
// LWC wrapper and testbench (see ../golden). Each line holds the core's inputs
// and outputs sampled at one rising clock edge. We drive the recorded inputs
// and require the DUT to produce the recorded outputs. If the DUT behaves like
// the original core, every cycle matches and the wrapper would have produced
// exactly the original, KAT-checked output stream. A mismatch shows the first
// cycle where the DUT would have behaved differently.
//
// Data outputs are compared only while their valid signal is high (the wrapper
// ignores them otherwise); handshake signals are compared on every cycle.
// Golden bits recorded as X (uninitialised in the VHDL) are not compared.
//
// Usage: replay <trace file> [max_errors]
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include "Vdut.h"
#include "verilated.h"

struct Field {
    uint32_t val;   // value with X bits as 0
    uint32_t known; // mask of non-X bits
};

static Field parse(const std::string& s) {
    Field f{0, 0};
    for (char ch : s) {
        f.val <<= 4;
        f.known <<= 4;
        if (ch == 'X' || ch == 'x' || ch == 'U' || ch == 'Z' || ch == '-') continue;
        unsigned d = (ch >= '0' && ch <= '9') ? ch - '0' : (ch & 0xDF) - 'A' + 10;
        f.val |= d;
        f.known |= 0xF;
    }
    // single-bit columns use one character; keep only bit 0 known
    if (s.size() == 1 && f.known) { f.known = 1; }
    return f;
}

enum {
    I_RST, I_KEY, I_KEY_VALID, I_KEY_UPDATE, I_BDI, I_BDI_VALID, I_PAD_LOC, I_VALID_BYTES,
    I_SIZE, I_EOT, I_EOI, I_TYPE, I_DECRYPT, I_HASH, I_BDO_READY, I_AUTH_READY, I_FDI_DATA,
    I_FDI_VALID, I_FDO_READY,
    O_KEY_READY, O_BDI_READY, O_BDO, O_BDO_VALID, O_BDO_TYPE, O_BDO_VB, O_EOB, O_AUTH_VALID,
    O_AUTH, O_FDI_READY, O_FDO_DATA, O_FDO_VALID, N_COLS
};
static const char* NAMES[N_COLS] = {
    "rst", "key", "key_valid", "key_update", "bdi", "bdi_valid", "bdi_pad_loc", "bdi_valid_bytes",
    "bdi_size", "bdi_eot", "bdi_eoi", "bdi_type", "decrypt_in", "hash_in", "bdo_ready",
    "msg_auth_ready", "fdi_data", "fdi_valid", "fdo_ready",
    "key_ready", "bdi_ready", "bdo", "bdo_valid", "bdo_type", "bdo_valid_bytes", "end_of_block",
    "msg_auth_valid", "msg_auth", "fdi_ready", "fdo_data", "fdo_valid"};

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <trace> [max_errors]\n", argv[0]);
        return 2;
    }
    long max_err = argc > 2 ? atol(argv[2]) : 10;
    std::ifstream in(argv[1]);
    if (!in) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }

    VerilatedContext ctx;
    Vdut dut(&ctx);
    dut.clk = 0;
    dut.eval();

    std::string line;
    long cycle = 0, errors = 0, checked = 0;
    long n_bdo = 0, n_fdo = 0, n_auth = 0, n_auth_fail = 0;
    Field c[N_COLS];
    while (std::getline(in, line)) {
        std::istringstream ss(line);
        std::string tok;
        int n = 0;
        while (n < N_COLS && ss >> tok) c[n++] = parse(tok);
        if (n != N_COLS) { fprintf(stderr, "bad trace line %ld\n", cycle + 1); return 2; }

        // 1) apply this cycle's inputs (clock low) and settle combinational logic
        dut.rst = c[I_RST].val & 1;
        dut.key = c[I_KEY].val;
        dut.key_valid = c[I_KEY_VALID].val & 1;
        dut.key_update = c[I_KEY_UPDATE].val & 1;
        dut.bdi = c[I_BDI].val;
        dut.bdi_valid = c[I_BDI_VALID].val & 1;
        dut.bdi_pad_loc = c[I_PAD_LOC].val & 0xF;
        dut.bdi_valid_bytes = c[I_VALID_BYTES].val & 0xF;
        dut.bdi_size = c[I_SIZE].val & 0x7;
        dut.bdi_eot = c[I_EOT].val & 1;
        dut.bdi_eoi = c[I_EOI].val & 1;
        dut.bdi_type = c[I_TYPE].val & 0xF;
        dut.decrypt_in = c[I_DECRYPT].val & 1;
        dut.hash_in = c[I_HASH].val & 1;
        dut.bdo_ready = c[I_BDO_READY].val & 1;
        dut.msg_auth_ready = c[I_AUTH_READY].val & 1;
        dut.fdi_data = c[I_FDI_DATA].val;
        dut.fdi_valid = c[I_FDI_VALID].val & 1;
        dut.fdo_ready = c[I_FDO_READY].val & 1;
        dut.eval();

        // 2) compare outputs with the golden core
        uint32_t got[N_COLS] = {0};
        got[O_KEY_READY] = dut.key_ready;   got[O_BDI_READY] = dut.bdi_ready;
        got[O_BDO] = dut.bdo;               got[O_BDO_VALID] = dut.bdo_valid;
        got[O_BDO_TYPE] = dut.bdo_type;     got[O_BDO_VB] = dut.bdo_valid_bytes;
        got[O_EOB] = dut.end_of_block;      got[O_AUTH_VALID] = dut.msg_auth_valid;
        got[O_AUTH] = dut.msg_auth;         got[O_FDI_READY] = dut.fdi_ready;
        got[O_FDO_DATA] = dut.fdo_data;     got[O_FDO_VALID] = dut.fdo_valid;

        bool in_reset = (c[I_RST].known & 1) == 0 || (c[I_RST].val & 1);
        if (!in_reset) {
            bool bdo_v = c[O_BDO_VALID].val & 1, fdo_v = c[O_FDO_VALID].val & 1;
            bool auth_v = c[O_AUTH_VALID].val & 1;
            for (int k = O_KEY_READY; k < N_COLS; k++) {
                bool active = true;
                if (k == O_BDO || k == O_BDO_TYPE || k == O_BDO_VB || k == O_EOB) active = bdo_v;
                if (k == O_AUTH) active = auth_v;
                if (k == O_FDO_DATA) active = fdo_v;
                if (!active) continue;
                uint32_t m = c[k].known;
                if ((got[k] & m) != (c[k].val & m)) {
                    if (errors < max_err)
                        fprintf(stderr, "MISMATCH cycle %ld %s: got %08X expected %08X (known %08X)\n",
                                cycle, NAMES[k], got[k], c[k].val, m);
                    errors++;
                }
            }
            checked++;
            // coverage counters (handshakes that the wrapper accepts)
            if (bdo_v && (c[I_BDO_READY].val & 1)) n_bdo++;
            if (fdo_v && (c[I_FDO_READY].val & 1)) n_fdo++;
            if (auth_v && (c[I_AUTH_READY].val & 1)) {
                n_auth++;
                if (!(c[O_AUTH].val & 1)) n_auth_fail++;
            }
        }

        // 3) rising clock edge
        dut.clk = 1; dut.eval();
        dut.clk = 0; dut.eval();
        cycle++;
    }
    dut.final();
    printf("%s: %ld cycles, %ld checked, %ld output words, %ld FIFO words, "
           "%ld tag checks (%ld rejected) -> %s (%ld mismatches)\n",
           argv[1], cycle, checked, n_bdo, n_fdo, n_auth, n_auth_fail,
           errors ? "FAIL" : "PASS", errors);
    return errors ? 1 : 0;
}
