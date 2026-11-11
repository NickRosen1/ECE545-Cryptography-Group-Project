// SPDX-License-Identifier: GPL-3.0-only
// Added 2026-11-10. Checks the unchanged upstream wrapper's rejection behavior.
`timescale 1ns/1ps
`default_nettype none
module tb_invalid_tag_wrapper;
    `include "invalid_vectors.svh"
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic [31:0] pdi_data=0,sdi_data=0;
    logic pdi_valid=0,sdi_valid=0,do_ready=0;
    wire pdi_ready,sdi_ready,do_valid,do_last;
    wire [31:0] do_data;
    int phase=0;
    always @(negedge clk) begin
        phase=phase+1;
        do_ready=!rst && (phase%4==0); // Three-cycle output stalls.
    end
    lwc_tb_2pass_uut dut(.*);
    task automatic send_pdi(input bit empty_payload, input int flip_bit);
        logic [31:0] value;
        int count,word_index;
        count=empty_payload?PDI_EMPTY_COUNT:PDI_NONEMPTY_COUNT;
        for(int i=0;i<count;i++) begin
            value=empty_payload?PDI_EMPTY[i]:PDI_NONEMPTY[i];
            word_index=(127-flip_bit)/32;
            if(flip_bit>=0 && i==count-4+word_index) value=value^(32'b1<<(flip_bit%32));
            @(negedge clk); pdi_data=value; pdi_valid=1;
            do @(posedge clk); while(pdi_ready!==1'b1);
            @(negedge clk); pdi_valid=0;
        end
    endtask
    task automatic send_sdi(input bit empty_payload);
        for(int i=0;i<6;i++) begin
            @(negedge clk); sdi_data=empty_payload?SDI_EMPTY[i]:SDI_NONEMPTY[i]; sdi_valid=1;
            do @(posedge clk); while(sdi_ready!==1'b1);
            @(negedge clk); sdi_valid=0;
        end
    endtask
    task automatic run_case(input bit empty_payload,input int flip_bit);
        int count, statuses;
        logic [31:0] expected_word;
        @(negedge clk); rst=1; pdi_valid=0;sdi_valid=0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst=0;
        count=0;statuses=0;
        fork
            send_pdi(empty_payload,flip_bit);
            send_sdi(empty_payload);
            begin
                // Bounded observation after enough time for the valid control.
                // Missing failure status is explicitly a limitation, never a KAT PASS.
                repeat(2000) begin
                    @(posedge clk);
                    if(do_valid && do_ready) begin
                        if(flip_bit<0) begin
                            if(count>=DO_NONEMPTY_COUNT) $fatal(1,"Extra valid-control output");
                            expected_word=DO_NONEMPTY[count];
                        end else if(empty_payload) begin
                            if(count>=2) $fatal(1,"Extra empty-rejection output");
                            expected_word=count==0?32'h43000000:32'hf0000000;
                        end else begin
                            if(count>0) $fatal(1,"Unexpected payload/status on known wrapper failure path");
                            expected_word=32'h4300000f;
                        end
                        if(do_data !== expected_word) $fatal(1,"Wrapper output mismatch received=%h expected=%h",do_data,expected_word);
                        if(do_last) statuses++;
                        count++;
                    end
                end
            end
        join
        if(flip_bit<0) begin
            if(count!=DO_NONEMPTY_COUNT || statuses!=1) $fatal(1,"Valid wrapper control incomplete");
            $display("WRAPPER_VALID_PASS plaintext_bytes=15 status=E");
        end else if(empty_payload) begin
            if(count!=2 || statuses!=1) $fatal(1,"Empty rejection incomplete");
            $display("WRAPPER_EMPTY_REJECTION_PASS flip_bit=%0d plaintext_bytes=0 status=F",flip_bit);
        end else begin
            if(count!=1 || statuses!=0) $fatal(1,"Unexpected nonempty rejection behavior");
            $display("WRAPPER_LIMITATION flip_bit=%0d plaintext_words=0 failure_status=missing observation_cycles=2000",flip_bit);
        end
    endtask
    initial begin
        run_case(0,-1);
        run_case(0,127);run_case(0,64);run_case(0,0);
        run_case(1,127);run_case(1,64);run_case(1,0);
        $display("STAGE3_WRAPPER_CHECKS_COMPLETE valid=1 empty_rejections=3 nonempty_limitations=3");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Wrapper tag test timeout");end
endmodule
`default_nettype wire
