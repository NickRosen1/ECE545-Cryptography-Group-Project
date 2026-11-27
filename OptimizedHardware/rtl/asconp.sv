// SPDX-License-Identifier: GPL-3.0-only
// SystemVerilog translation, 2026-11-10, of the Asconp entity in
// hardware/isap_lwc/src_rtl/v1/CryptoCore.vhd.
// Original author: Robert Primas.
// Copyright (c) 2020 IAIK, Graz University of Technology, AUSTRIA
// All rights Reserved.
// The original project is released under the GNU Public License;
// see ../../LICENSE.txt or http://www.gnu.org/licenses/gpl-3.0.txt.
// Original note: publicly available encryption source code falling under
// License Exception TSU (Technology and software-unrestricted).
//
// The byte-reversal helper is adapted from design_pkg.vhd:
// Michael Tempelmeier <michael.tempelmeier@tum.de>
// Patrick Karl <patrick.karl@tum.de>
// Copyright (c) 2019 Chair of Security in Information Technology,
// ECE Department, Technical University of Munich, GERMANY.
// All rights Reserved. Same GNU Public License as above.

`default_nettype none

// One combinational round. No clock, reset, enable, or added pipeline stage.
// Lane x0 is state_in[63:0]; each lane is byte-reversed on entry and exit.
// rcon is the number of rounds remaining, NOT an encoded round constant:
// p12 uses 12..1, p6 uses 6..1, and p1 uses 1.
module asconp_sv (
    input  wire [319:0] state_in,
    input  wire [3:0]   rcon,
    output logic [319:0] state_out
);
    function automatic logic [63:0] reverse_byte64(input logic [63:0] value);
        for (int i = 0; i < 8; i = i + 1)
            reverse_byte64[8*i +: 8] = value[8*(7-i) +: 8];
    endfunction

    logic [63:0] x0, x1, x2, x3, x4;
    logic [63:0] t0, t1;
    logic [3:0] t2, constant_hi;

    always_comb begin
        x0 = reverse_byte64(state_in[  0 +: 64]);
        x1 = reverse_byte64(state_in[ 64 +: 64]);
        x2 = reverse_byte64(state_in[128 +: 64]);
        x3 = reverse_byte64(state_in[192 +: 64]);
        x4 = reverse_byte64(state_in[256 +: 64]);

        // Explicit four-bit arithmetic preserves VHDL modulo-16 subtraction,
        // including rcon values outside the controller's active range 1..12.
        t2 = 4'hc - rcon;
        constant_hi = 4'hf - t2;
        x0 = x0 ^ x4;
        x2[7:0] = x2[7:0] ^ x1[7:0] ^ {constant_hi, t2};
        x2[63:8] = x2[63:8] ^ x1[63:8];
        x4 = x4 ^ x3;

        // Blocking assignment order matches the VHDL process variables.
        t0 = x0;
        t1 = x1;
        x0 = x0 ^ (~x1 & x2);
        x1 = x1 ^ (~x2 & x3);
        x2 = x2 ^ (~x3 & x4);
        x3 = x3 ^ (~x4 & t0);
        x4 = x4 ^ (~t0 & t1);

        x1 = x1 ^ x0;
        x3 = x3 ^ x2;
        x0 = x0 ^ x4;
        x2 = ~x2;

        x0 = x0 ^ {x0[18:0], x0[63:19]} ^ {x0[27:0], x0[63:28]};
        x1 = x1 ^ {x1[60:0], x1[63:61]} ^ {x1[38:0], x1[63:39]};
        x2 = x2 ^ {x2[ 0:0], x2[63: 1]} ^ {x2[ 5:0], x2[63: 6]};
        x3 = x3 ^ {x3[ 9:0], x3[63:10]} ^ {x3[16:0], x3[63:17]};
        x4 = x4 ^ {x4[ 6:0], x4[63: 7]} ^ {x4[40:0], x4[63:41]};

        state_out = {reverse_byte64(x4), reverse_byte64(x3),
                     reverse_byte64(x2), reverse_byte64(x1),
                     reverse_byte64(x0)};
    end
endmodule

`default_nettype wire
