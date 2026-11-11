// SPDX-License-Identifier: GPL-3.0-only
// Added 2026-11-10. See ../../LICENSE.txt.
`timescale 1ns/1ps
`default_nettype none

module tb_asconp_equiv;
    logic [319:0] state_sv = '0;
    logic [319:0] state_vhdl = '0;
    logic [3:0] rcon = '0;
    wire [319:0] result_sv, result_vhdl;
    logic [31:0] rng = 32'h1a128a20;
    integer checks = 0;
    integer count_per_rcon [0:15];
    logic [319:0] pattern;

    asconp_sv dut (.state_in(state_sv), .rcon(rcon), .state_out(result_sv));
    asconp_vhdl_ref oracle (
        .state_in(state_vhdl), .rcon(rcon), .state_out(result_vhdl)
    );

    // Explicit PRNG makes the stimulus independent of simulator RNG behavior.
    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] v;
        v = value ^ (value << 13);
        v = v ^ (v >> 17);
        return v ^ (v << 5);
    endfunction

    task automatic random_state(output logic [319:0] value);
        for (int word_idx = 0; word_idx < 10; word_idx++) begin
            rng = next_random(rng);
            value[32*word_idx +: 32] = rng;
        end
    endtask

    task automatic compare_round;
        // Allow both languages' combinational processes and adapter to settle.
        #1;
        if ($isunknown(result_sv) || $isunknown(result_vhdl) ||
            result_sv !== result_vhdl) begin
            $display("FAIL check=%0d rcon=%0d SV_input=%080h VHDL_input=%080h",
                     checks, rcon, state_sv, state_vhdl);
            $display("SV=%080h VHDL=%080h", result_sv, result_vhdl);
            $fatal(1, "Ascon-p round mismatch or unknown output");
        end
        checks++;
        count_per_rcon[rcon]++;
    endtask

    task automatic check_all_constants(input logic [319:0] value);
        state_sv = value;
        state_vhdl = value;
        for (int rc = 0; rc < 16; rc++) begin
            rcon = rc[3:0];
            compare_round();
        end
    endtask

    task automatic check_chain(input logic [319:0] value, input int rounds);
        state_sv = value;
        state_vhdl = value;
        for (int rc = rounds; rc > 0; rc--) begin
            rcon = rc[3:0];
            compare_round();
            // Independent feedback, checking every intermediate round.
            state_sv = result_sv;
            state_vhdl = result_vhdl;
        end
    endtask

    initial begin
        for (int rc = 0; rc < 16; rc++) count_per_rcon[rc] = 0;
        check_all_constants('0);
        check_all_constants('1);
        check_all_constants({40{8'haa}});
        check_all_constants({40{8'h55}});
        for (int b = 0; b < 40; b++) pattern[8*b +: 8] = 8'(b);
        check_all_constants(pattern);
        check_all_constants(~pattern);

        // Every state bit and its complement, including lane/byte boundaries.
        for (int bit_idx = 0; bit_idx < 320; bit_idx++) begin
            pattern = '0;
            pattern[bit_idx] = 1'b1;
            check_all_constants(pattern);
            check_all_constants(~pattern);
        end

        // Exercise all five S-box input bits at all 64 bit positions in parallel.
        for (int sbox = 0; sbox < 32; sbox++) begin
            for (int lane = 0; lane < 5; lane++)
                pattern[64*lane +: 64] = {64{sbox[lane]}};
            check_all_constants(pattern);
        end

        for (int sample_idx = 0; sample_idx < 4096; sample_idx++) begin
            random_state(pattern);
            check_all_constants(pattern);
        end
        for (int sample_idx = 0; sample_idx < 256; sample_idx++) begin
            random_state(pattern);
            check_chain(pattern, 1);  // sB
            check_chain(pattern, 6);  // sE
            check_chain(pattern, 12); // sH and sK
        end

        // Check input sensitivity while rcon stays unchanged across vectors.
        rcon = 4'd6;
        for (int sample_idx = 0; sample_idx < 256; sample_idx++) begin
            random_state(pattern);
            state_sv = pattern;
            state_vhdl = pattern;
            compare_round();
        end
        for (int rc = 0; rc < 16; rc++)
            $display("rcon=%0d comparisons=%0d", rc, count_per_rcon[rc]);
        if (checks != 81504) $fatal(1, "Unexpected comparison count: %0d", checks);
        $display("PASS: %0d Ascon-p comparisons against original VHDL; seed=1a128a20", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Equivalence test timed out");
    end
endmodule

`default_nettype wire
