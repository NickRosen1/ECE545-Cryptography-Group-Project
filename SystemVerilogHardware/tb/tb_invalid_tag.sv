// SPDX-License-Identifier: GPL-3.0-only
// Added 2026-11-10. See ../../LICENSE.txt.
`timescale 1ns/1ps
`default_nettype none
module tb_invalid_tag;
    `include "invalid_vectors.svh"
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic [31:0] key='0, bdi='0;
    logic key_valid=0, key_update=0, bdi_valid=0;
    wire key_ready, bdi_ready;
    logic [3:0] bdi_valid_bytes=0, bdi_type=0;
    logic bdi_eot=0, bdi_eoi=0;
    wire [31:0] bdo;
    wire bdo_valid;
    logic bdo_ready=1, msg_auth_ready=0;
    wire [3:0] bdo_valid_bytes;
    wire msg_auth, msg_auth_valid;
    wire signed [31:0] queued_words, read_words;
    stage3_core_dut dut (.*);
    logic authenticated=0;
    always @(posedge clk) begin
        if(rst) authenticated <= 0;
        else begin
            if(!authenticated && bdo_valid !== 1'b0)
                $fatal(1,"Plaintext valid before successful authentication acknowledgement");
            if(msg_auth_valid && msg_auth_ready && msg_auth) authenticated <= 1;
        end
    end

    task automatic send_key(input logic [31:0] value);
        @(negedge clk); key=value; key_valid=1; key_update=1;
        do @(posedge clk); while (key_ready !== 1'b1);
        @(negedge clk); key_valid=0;
    endtask
    task automatic send_data(input logic [31:0] value, input logic [3:0] typ,
        input logic [3:0] valid_bytes, input logic eot, input logic eoi);
        @(negedge clk); bdi=value; bdi_type=typ; bdi_valid_bytes=valid_bytes;
        bdi_eot=eot; bdi_eoi=eoi; bdi_valid=1;
        do @(posedge clk); while (bdi_ready !== 1'b1);
        @(negedge clk); bdi_valid=0;
    endtask
    task automatic run_case(input int flip_bit);
        logic [127:0] tag;
        logic [31:0] mask;
        int emitted;
        @(negedge clk); rst=1; key_valid=0; bdi_valid=0; msg_auth_ready=0;
        repeat(4) @(posedge clk);
        @(negedge clk); rst=0;
        // A reset flushes the external FIFO as well as the core before every case.
        for(int i=0;i<4;i++) send_key(KEY_VALUE[127-32*i -:32]);
        key_update=0;
        for(int i=0;i<4;i++) send_data(NONCE_VALUE[127-32*i -:32],4'hd,4'hf,i==3,0);
        send_data(AD_VALUE,4'h1,4'h8,1,0);
        for(int i=0;i<4;i++) send_data(CT_VALUE[127-32*i -:32],4'h5,i==3?4'he:4'hf,i==3,i==3);
        tag=TAG_VALUE;
        if(flip_bit>=0) tag[flip_bit]=~tag[flip_bit];
        for(int i=0;i<4;i++) send_data(tag[127-32*i -:32],4'h8,4'hf,i==3,0);
        while(msg_auth_valid !== 1'b1) begin
            @(negedge clk);
            if(bdo_valid !== 1'b0) $fatal(1,"Plaintext before authentication");
        end
        // Hold acknowledgement low for seven full clock edges after valid.
        repeat(7) begin
            @(posedge clk);
            if(msg_auth_valid !== 1'b1 || msg_auth !== (flip_bit<0) || bdo_valid !== 1'b0)
                $fatal(1,"Authentication/backpressure failure flip=%0d",flip_bit);
        end
        @(negedge clk); msg_auth_ready=1;
        @(posedge clk);
        @(negedge clk); msg_auth_ready=0;
        emitted=0;
        if(flip_bit<0) begin
            while(emitted<4) begin
                @(posedge clk);
                if(bdo_valid===1'b1) begin
                    mask=emitted==3?32'hffffff00:32'hffffffff;
                    if((bdo & mask) !== (PT_VALUE[127-32*emitted -:32] & mask) ||
                       bdo_valid_bytes !== (emitted==3?4'he:4'hf))
                        $fatal(1,"Positive control plaintext mismatch");
                    emitted++;
                end
            end
            @(negedge clk);
            if(queued_words!==0 || read_words!==4) $fatal(1,"Positive control FIFO mismatch");
        end else begin
            repeat(64) begin
                @(posedge clk);
                if(bdo_valid !== 1'b0) $fatal(1,"Plaintext released on invalid tag");
            end
            if(queued_words!==4 || read_words!==0) $fatal(1,"Invalid-tag FIFO unexpectedly read/flushed");
        end
        $display("TAG_CASE flip_bit=%0d auth=%0d ack_stall=7 plaintext_words=%0d fifo_remaining=%0d",flip_bit,flip_bit<0,emitted,queued_words);
    endtask
    initial begin
        run_case(-1); // Valid control ensures the fixture exercises real decryption.
        run_case(127); // First bit in wire order.
        run_case(64);  // Middle of the tag.
        run_case(0);   // Last bit in wire order.
        $display("STAGE3_TAG_PASS cases=4 invalid=3");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Invalid-tag test timeout"); end
endmodule
`default_nettype wire
