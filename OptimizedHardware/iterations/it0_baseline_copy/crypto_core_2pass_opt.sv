// SPDX-License-Identifier: GPL-3.0-only
// SystemVerilog translation, 2026-11-10, of the 32-bit ISAP-A-128A
// CryptoCore_2pass in hardware/isap_lwc/src_rtl/v1/CryptoCore.vhd.
// Original author: Robert Primas.
// Copyright (c) 2020 IAIK, Graz University of Technology, Austria.
// Original notice: publicly available encryption source code falling under
// License Exception TSU (Technology and software-unrestricted).
// Data-format helpers adapted from v1/design_pkg.vhd:
// Michael Tempelmeier and Patrick Karl, copyright (c) 2019 Chair of Security
// in Information Technology, ECE Department, Technical University of Munich.
// See ../../LICENSE.txt for the GNU General Public License.

`default_nettype none

module crypto_core_2pass_opt (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] key,
    input  wire        key_valid,
    output wire        key_ready,
    input  wire [31:0] bdi,
    input  wire        bdi_valid,
    output wire        bdi_ready,
    input  wire [3:0]  bdi_pad_loc,
    input  wire [3:0]  bdi_valid_bytes,
    input  wire [2:0]  bdi_size,
    input  wire        bdi_eot,
    input  wire        bdi_eoi,
    input  wire [3:0]  bdi_type,
    input  wire        decrypt_in,
    input  wire        key_update,
    input  wire        hash_in,
    output wire [31:0] bdo,
    output wire        bdo_valid,
    input  wire        bdo_ready,
    output wire [3:0]  bdo_type,
    output wire [3:0]  bdo_valid_bytes,
    output wire        end_of_block,
    output wire        msg_auth_valid,
    input  wire        msg_auth_ready,
    output wire        msg_auth,
    input  wire [31:0] fdi_data,
    input  wire        fdi_valid,
    output wire        fdi_ready,
    output wire [31:0] fdo_data,
    output wire        fdo_valid,
    input  wire        fdo_ready
);
    // The LWC interface also serves hash-capable cores. This AEAD-only core
    // uses bdi_valid_bytes and the segment flags for padding, so bdi_pad_loc,
    // bdi_size and hash_in intentionally have no fanout.
    localparam int CCW = 32;
    localparam int p_n = 320;
    localparam int p_k = 128;
    localparam logic [2:0] NPUB_WORDS_C = 3'd4;
    localparam logic [2:0] BLOCK_WORDS_C = 3'd2;
    localparam logic [2:0] TAG_WORDS_C = 3'd4;
    localparam logic [2:0] KEY_WORDS_C = 3'd4;
    localparam logic [7:0] p_sH = 8'd12, p_sB = 8'd1, p_sE = 8'd6, p_sK = 8'd12;
    localparam logic [63:0] p_iv_a  = 64'h018040010c01060c;
    localparam logic [63:0] p_iv_ka = 64'h028040010c01060c;
    localparam logic [63:0] p_iv_ke = 64'h038040010c01060c;
    localparam logic [3:0] HDR_AD = 4'h1, HDR_PT = 4'h4, HDR_CT = 4'h5,
                           HDR_TAG = 4'h8, HDR_NPUB = 4'hd;

    typedef enum logic [4:0] {
        IDLE, STORE_KEY, STORE_NONCE, WAIT_INPUT_TYPE,
        ISAP_RK_SETUP_STATE, ISAP_RK_INITIALIZE, ISAP_RK_REKEYING, ISAP_RK_SQUEEZE,
        ISAP_ENC_INITIALIZE, ISAP_ENC_PERMUTE_PE, ISAP_ENC_SQUEEZE_BLOCK,
        ISAP_MAC_SETUP_STATE, ISAP_MAC_INITIALIZE, ISAP_MAC_WAIT_INPUT,
        ISAP_MAC_ABSORB_AD, ISAP_MAC_PROCESS_AD, ISAP_MAC_ABSORB_AD_PAD,
        ISAP_MAC_DOMAIN_SEPARATION, ISAP_MAC_ABSORB_CT, ISAP_MAC_PROCESS_CT,
        ISAP_MAC_ABSORB_CT_PAD, ISAP_MAC_FINALIZE_AFTER_RK_STATE_SETUP,
        ISAP_MAC_FINALIZE_PERMUTE_PH, EXTRACT_TAG, VERIFY_TAG, WAIT_ACK
    } state_t;
    typedef enum logic {ISAP_ENC, ISAP_MAC} isap_encmac_t;
    typedef enum logic {AUTH_ENC, AUTH_DEC} isap_auth_t;

    state_t state_s, n_state_s;
    isap_encmac_t isap_encmac_s;
    isap_auth_t isap_auth_encdec_s, n_isap_auth_encdec_s;

    logic [2:0] word_idx_s;
    logic [31:0] key_s, bdi_s, bdi_masked_s, bdo_s, isap_state_cur_word_s;
    logic [3:0] bdi_valid_bytes_s, bdo_valid_bytes_s, bdo_type_s;
    logic key_ready_s, bdi_ready_s, bdo_valid_s, end_of_block_s, msg_auth_valid_s;

    logic n_msg_auth_s, msg_auth_s, n_update_key_s, update_key_s;
    logic n_eoi_s, eoi_s, n_eot_s, eot_s, pad_added_s, bdi_partial_s;
    logic [15:0] n_fifo_words_s, fifo_words_s;

    logic [p_n-1:0] isap_state_s, isap_state_n_s, perm_in_s, perm_out_s;
    logic [p_k-1:0] isap_key_s, isap_nonce_s, isap_y_s;
    logic [p_n-p_k-1:0] isap_buf_s;
    logic [7:0] isap_cnt_s;
    logic [6:0] isap_cnt_y_s;
    logic [3:0] isap_ctrl_s;

    logic [31:0] fifo_din_s, fifo_dout_s;
    logic fifo_din_valid_s, fifo_din_ready_s, fifo_dout_valid_s, fifo_dout_ready_s;
    logic [3:0] fifo_valid_bytes_s, fifo_last_word_valid_bytes_s;
    logic fifo_eoi, fifo_partial;

    function automatic logic [31:0] reverse_byte32(input logic [31:0] word);
        return {word[7:0], word[15:8], word[23:16], word[31:24]};
    endfunction

    function automatic logic [63:0] reverse_byte64(input logic [63:0] word);
        for (int byte_idx = 0; byte_idx < 8; byte_idx++)
            reverse_byte64[8*byte_idx +: 8] = word[8*(7-byte_idx) +: 8];
    endfunction

    function automatic logic [127:0] reverse_byte128(input logic [127:0] word);
        for (int byte_idx = 0; byte_idx < 16; byte_idx++)
            reverse_byte128[8*byte_idx +: 8] = word[8*(15-byte_idx) +: 8];
    endfunction

    function automatic logic [3:0] reverse_bit4(input logic [3:0] mask);
        return {mask[0], mask[1], mask[2], mask[3]};
    endfunction

    function automatic logic [31:0] mask_zero(
        input logic [31:0] word, input logic [3:0] valid_bytes
    );
        for (int byte_idx = 0; byte_idx < 4; byte_idx++)
            mask_zero[8*byte_idx +: 8] = valid_bytes[byte_idx] ? word[8*byte_idx +: 8] : 8'h00;
    endfunction

    // Absorb valid bytes and append 0x80 after a partial word.
    function automatic logic [31:0] pad_bdi(
        input logic [31:0] word, input logic [3:0] valid_bytes,
        input logic [31:0] state_word
    );
        logic [4:0] padded_mask;
        padded_mask = {valid_bytes, 1'b0};
        pad_bdi = state_word;
        for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
            if (valid_bytes[byte_idx])
                pad_bdi[8*byte_idx +: 8] = state_word[8*byte_idx +: 8] ^ word[8*byte_idx +: 8];
            else if (padded_mask[byte_idx])
                pad_bdi[8*byte_idx +: 8] = state_word[8*byte_idx +: 8] ^ 8'h80;
        end
    endfunction

    function automatic logic [p_n-1:0] absorb_word(
        input logic [p_n-1:0] old_state, input logic [31:0] word,
        input logic [2:0] word_index, input logic eot, input logic partial
    );
        absorb_word = old_state;
        absorb_word[CCW*word_index +: CCW] = word;
        // A full first word that ends the segment leaves space for padding.
        if (word_index < BLOCK_WORDS_C - 3'd1 && eot && !partial)
            absorb_word[CCW +: 8] = old_state[CCW +: 8] ^ 8'h80;
    endfunction

    // The LWC bus is big-endian; the internal state stores each word little-endian.
    assign key_s = reverse_byte32(key);
    assign bdi_s = reverse_byte32(bdi);
    assign bdi_valid_bytes_s = reverse_bit4(bdi_valid_bytes);
    assign key_ready = key_ready_s;
    assign bdi_ready = bdi_ready_s;
    assign bdo = reverse_byte32(bdo_s);
    assign bdo_valid_bytes = reverse_bit4(bdo_valid_bytes_s);
    assign bdo_valid = bdo_valid_s;
    assign bdo_type = bdo_type_s;
    assign end_of_block = end_of_block_s;
    assign msg_auth = msg_auth_s;
    assign msg_auth_valid = msg_auth_valid_s;

    assign fdo_data = fifo_din_s;
    assign fdo_valid = fifo_din_valid_s;
    assign fifo_din_ready_s = fdo_ready;
    assign fifo_dout_s = fdi_data;
    assign fifo_dout_valid_s = fdi_valid;
    assign fdi_ready = fifo_dout_ready_s;

    assign bdi_partial_s = ~(&bdi_valid_bytes_s);
    assign bdi_masked_s = mask_zero(bdi_s, bdi_valid_bytes_s);
    assign isap_state_cur_word_s = isap_state_s[CCW*word_idx_s +: CCW];

    asconp_sv round_function (
        .state_in(perm_in_s), .rcon(isap_cnt_s[3:0]), .state_out(perm_out_s)
    );

    always_comb begin : permutation_input
        case (isap_ctrl_s)
            4'h1: perm_in_s = {isap_state_s[p_n-1:8], isap_state_s[7] ^ isap_y_s[127],
                               isap_state_s[6:0]};
            4'h2: perm_in_s = {isap_state_s[p_n-1:8], isap_state_s[7:0] ^ 8'h80};
            default: perm_in_s = isap_state_s;
        endcase
    end

    always_comb begin : fifo_byte_mask
        fifo_eoi = fifo_words_s == 16'd1;
        if (fifo_eoi)
            fifo_valid_bytes_s = fifo_last_word_valid_bytes_s;
        else if (fifo_words_s == 16'd0 || !fifo_dout_valid_s)
            fifo_valid_bytes_s = '0;
        else
            fifo_valid_bytes_s = '1;
        fifo_partial = fifo_eoi && !(&fifo_valid_bytes_s);
    end

    always_comb begin : absorption
        isap_state_n_s = isap_state_s;
        if (word_idx_s < BLOCK_WORDS_C) begin
            if (state_s == ISAP_MAC_ABSORB_CT && isap_auth_encdec_s == AUTH_ENC)
                isap_state_n_s = absorb_word(isap_state_s,
                    pad_bdi(fifo_dout_s, reverse_bit4(fifo_valid_bytes_s), isap_state_cur_word_s),
                    word_idx_s, fifo_eoi, fifo_partial);
            else if (state_s == ISAP_MAC_ABSORB_AD || state_s == ISAP_MAC_ABSORB_CT)
                isap_state_n_s = absorb_word(isap_state_s,
                    pad_bdi(bdi_s, bdi_valid_bytes_s, isap_state_cur_word_s),
                    word_idx_s, bdi_eot, bdi_partial_s);
        end
    end

    always_comb begin : fifo_interface
        fifo_din_s = '0;
        fifo_din_valid_s = 1'b0;
        fifo_dout_ready_s = 1'b0;
        case (state_s)
            ISAP_ENC_SQUEEZE_BLOCK: begin
                if (isap_auth_encdec_s == AUTH_DEC)
                    fifo_dout_ready_s = bdo_ready;
                else begin
                    fifo_din_s = bdi_masked_s ^ isap_state_cur_word_s;
                    fifo_din_valid_s = bdi_valid && bdi_ready_s;
                end
            end
            ISAP_MAC_ABSORB_CT: begin
                if (isap_auth_encdec_s == AUTH_DEC) begin
                    fifo_din_s = bdi_s;
                    fifo_din_valid_s = bdi_valid;
                end else
                    fifo_dout_ready_s = 1'b1;
            end
            default: begin end
        endcase
    end

    always_comb begin : output_interface
        bdo_s = '0;
        bdo_valid_bytes_s = 4'b0001;
        bdo_valid_s = 1'b0;
        bdo_type_s = '0;
        end_of_block_s = 1'b0;
        case (state_s)
            ISAP_ENC_SQUEEZE_BLOCK: begin
                if (isap_auth_encdec_s == AUTH_DEC) begin
                    bdo_s = fifo_dout_s ^ isap_state_cur_word_s;
                    end_of_block_s = fifo_words_s == 16'd1;
                    bdo_valid_bytes_s = end_of_block_s ?
                        reverse_bit4(fifo_last_word_valid_bytes_s) : 4'b1111;
                    bdo_valid_s = 1'b1;
                    bdo_type_s = HDR_PT;
                end else begin
                    bdo_s = bdi_masked_s ^ isap_state_cur_word_s;
                    bdo_valid_bytes_s = bdi_valid_bytes_s;
                    bdo_valid_s = bdi_valid;
                    end_of_block_s = bdi_eot;
                    bdo_type_s = HDR_CT;
                end
            end
            EXTRACT_TAG: begin
                bdo_s = isap_state_cur_word_s;
                bdo_valid_bytes_s = '1;
                bdo_valid_s = 1'b1;
                bdo_type_s = HDR_TAG;
                end_of_block_s = word_idx_s == TAG_WORDS_C - 3'd1;
            end
            default: begin end
        endcase
    end

    always_comb begin : next_state
        n_state_s = state_s;
        case (state_s)
            IDLE: begin
                if (key_valid || bdi_valid) begin
                    n_state_s = STORE_KEY;
                end
            end
            STORE_KEY: begin
                if (((key_valid && key_ready_s) || !key_update) && word_idx_s >= KEY_WORDS_C - 3'd1) begin
                    n_state_s = STORE_NONCE;
                end
            end
            STORE_NONCE: begin
                if (bdi_valid && bdi_ready_s && word_idx_s >= NPUB_WORDS_C - 3'd1) begin
                    if (bdi_eoi) begin
                        n_state_s = ISAP_MAC_SETUP_STATE;
                    end else begin
                        if (isap_auth_encdec_s == AUTH_DEC) begin
                            n_state_s = ISAP_MAC_SETUP_STATE;
                        end else begin
                            n_state_s = WAIT_INPUT_TYPE;
                        end
                    end
                end
            end
            WAIT_INPUT_TYPE: begin
                if (bdi_valid) begin
                    if (bdi_type == HDR_AD) begin
                        n_state_s = ISAP_MAC_SETUP_STATE;
                    end else if (bdi_type == HDR_PT) begin
                        n_state_s = ISAP_RK_SETUP_STATE;
                    end
                end
            end
            ISAP_RK_SETUP_STATE: n_state_s = ISAP_RK_INITIALIZE;
            ISAP_RK_INITIALIZE: begin
                if (isap_cnt_s == 8'h01) begin
                    n_state_s = ISAP_RK_REKEYING;
                end
            end
            ISAP_RK_REKEYING: begin
                if (isap_cnt_y_s == 7'd1 && isap_cnt_s == 8'h01) begin
                    n_state_s = ISAP_RK_SQUEEZE;
                end
            end
            ISAP_RK_SQUEEZE: begin
                if (isap_cnt_s == 8'h01) begin
                    if (isap_encmac_s == ISAP_ENC) begin
                        n_state_s = ISAP_ENC_INITIALIZE;
                    end else begin
                        n_state_s = ISAP_MAC_FINALIZE_AFTER_RK_STATE_SETUP;
                    end
                end
            end
            ISAP_ENC_INITIALIZE: n_state_s = ISAP_ENC_PERMUTE_PE;
            ISAP_ENC_PERMUTE_PE: begin
                if (isap_cnt_s == 8'h01) begin
                    n_state_s = ISAP_ENC_SQUEEZE_BLOCK;
                end
            end
            ISAP_ENC_SQUEEZE_BLOCK: begin
                if (isap_auth_encdec_s == AUTH_DEC) begin
                    if (fifo_dout_valid_s && fifo_dout_ready_s && bdo_ready) begin
                        if (fifo_words_s == 16'd1) begin
                            n_state_s = IDLE;
                        end else if (word_idx_s >= BLOCK_WORDS_C - 3'd1) begin
                            n_state_s = ISAP_ENC_PERMUTE_PE;
                        end
                    end
                end else begin
                    if (bdi_valid && bdi_ready_s && fifo_din_ready_s) begin
                        if (bdi_eot) begin
                            n_state_s = ISAP_MAC_SETUP_STATE;
                        end else begin
                            if (word_idx_s == BLOCK_WORDS_C - 3'd1) begin
                                n_state_s = ISAP_ENC_PERMUTE_PE;
                            end
                        end
                    end
                end
            end
            ISAP_MAC_SETUP_STATE: n_state_s = ISAP_MAC_INITIALIZE;
            ISAP_MAC_INITIALIZE: begin
                if (isap_cnt_s == 8'h01) begin
                    n_state_s = ISAP_MAC_WAIT_INPUT;
                end
            end
            ISAP_MAC_WAIT_INPUT: begin
                if (bdi_valid) begin
                    if (bdi_type == HDR_AD) begin
                        n_state_s = ISAP_MAC_ABSORB_AD;
                    end else begin
                        n_state_s = ISAP_MAC_ABSORB_AD_PAD;
                    end
                end
                if (key_valid) begin
                    n_state_s = ISAP_MAC_ABSORB_AD_PAD;
                end
            end
            ISAP_MAC_ABSORB_AD: begin
                if (bdi_valid && bdi_ready_s) begin
                    if (bdi_eot) begin
                        n_state_s = ISAP_MAC_PROCESS_AD;
                    end else begin
                        if (word_idx_s == BLOCK_WORDS_C - 3'd1) begin
                            n_state_s = ISAP_MAC_PROCESS_AD;
                        end
                    end
                end
            end
            ISAP_MAC_PROCESS_AD: begin
                if (isap_cnt_s == 8'h01) begin
                    if (isap_auth_encdec_s == AUTH_ENC) begin
                        if (eoi_s) begin
                            if (pad_added_s) begin
                                n_state_s = ISAP_MAC_DOMAIN_SEPARATION;
                            end else begin
                                n_state_s = ISAP_MAC_ABSORB_AD_PAD;
                            end
                        end else begin
                            n_state_s = ISAP_MAC_ABSORB_AD;
                        end
                    end else begin
                        if (eot_s) begin
                            if (pad_added_s) begin
                                n_state_s = ISAP_MAC_DOMAIN_SEPARATION;
                            end else begin
                                n_state_s = ISAP_MAC_ABSORB_AD_PAD;
                            end
                        end else begin
                            n_state_s = ISAP_MAC_ABSORB_AD;
                        end
                    end
                end
            end
            ISAP_MAC_ABSORB_AD_PAD: begin
                if (isap_cnt_s == 8'h01) begin
                    n_state_s = ISAP_MAC_DOMAIN_SEPARATION;
                end
            end
            ISAP_MAC_DOMAIN_SEPARATION: begin
                if (isap_auth_encdec_s == AUTH_DEC) begin
                    if (eoi_s) begin
                        n_state_s = ISAP_MAC_ABSORB_CT_PAD;
                    end else begin
                        n_state_s = ISAP_MAC_ABSORB_CT;
                    end
                end else begin
                    if (fifo_words_s > 16'd0) begin
                        n_state_s = ISAP_MAC_ABSORB_CT;
                    end else begin
                        n_state_s = ISAP_MAC_ABSORB_CT_PAD;
                    end
                end
            end
            ISAP_MAC_ABSORB_CT: begin
                if (isap_auth_encdec_s == AUTH_DEC) begin
                    if (bdi_valid && bdi_ready_s && bdi_type == HDR_CT) begin
                        if (word_idx_s == BLOCK_WORDS_C - 3'd1 || bdi_eot) begin
                            n_state_s = ISAP_MAC_PROCESS_CT;
                        end
                    end
                end else begin
                    if ((word_idx_s == BLOCK_WORDS_C - 3'd1 || fifo_words_s == 16'd1) && fifo_dout_valid_s && fifo_dout_ready_s) begin
                        n_state_s = ISAP_MAC_PROCESS_CT;
                    end
                end
            end
            ISAP_MAC_PROCESS_CT: begin
                if (isap_cnt_s == 8'h01) begin
                    if (isap_auth_encdec_s == AUTH_DEC) begin
                        if (!eoi_s) begin
                            n_state_s = ISAP_MAC_ABSORB_CT;
                        end else begin
                            if (pad_added_s) begin
                                n_state_s = ISAP_RK_SETUP_STATE;
                            end else begin
                                n_state_s = ISAP_MAC_ABSORB_CT_PAD;
                            end
                        end
                    end else begin
                        if (fifo_words_s > 16'd0) begin
                            n_state_s = ISAP_MAC_ABSORB_CT;
                        end else begin
                            if (pad_added_s) begin
                                n_state_s = ISAP_RK_SETUP_STATE;
                            end else begin
                                n_state_s = ISAP_MAC_ABSORB_CT_PAD;
                            end
                        end
                    end
                end
            end
            ISAP_MAC_ABSORB_CT_PAD: begin
                if (isap_cnt_s == 8'h01) begin
                    n_state_s = ISAP_RK_SETUP_STATE;
                end
            end
            ISAP_MAC_FINALIZE_AFTER_RK_STATE_SETUP: n_state_s = ISAP_MAC_FINALIZE_PERMUTE_PH;
            ISAP_MAC_FINALIZE_PERMUTE_PH: begin
                if (isap_cnt_s == 8'h01) begin
                    if (isap_auth_encdec_s == AUTH_DEC) begin
                        n_state_s = VERIFY_TAG;
                    end else begin
                        n_state_s = EXTRACT_TAG;
                    end
                end
            end
            EXTRACT_TAG: begin
                if (bdo_valid_s && bdo_ready && word_idx_s >= TAG_WORDS_C - 3'd1) begin
                    n_state_s = IDLE;
                end
            end
            VERIFY_TAG: begin
                if (bdi_valid && bdi_ready_s && bdi_type == HDR_TAG) begin
                    if (word_idx_s >= TAG_WORDS_C - 3'd1) begin
                        n_state_s = WAIT_ACK;
                    end
                end
            end
            WAIT_ACK: begin
                if (msg_auth_valid_s && msg_auth_ready) begin
                    if (msg_auth_s && fifo_words_s > 16'd0) begin
                        n_state_s = ISAP_RK_SETUP_STATE;
                    end else begin
                        n_state_s = IDLE;
                    end
                end
            end
            default: n_state_s = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin : control_registers
        if (rst == 1'b1) begin
            msg_auth_s <= 1'b1;
            update_key_s <= 1'b0;
            isap_auth_encdec_s <= AUTH_ENC;
            state_s <= IDLE;
            fifo_words_s <= 16'd0;
            eoi_s <= 1'b0;
            eot_s <= 1'b0;
        end else begin
            msg_auth_s <= n_msg_auth_s;
            update_key_s <= n_update_key_s;
            isap_auth_encdec_s <= n_isap_auth_encdec_s;
            state_s <= n_state_s;
            eoi_s <= n_eoi_s;
            eot_s <= n_eot_s;
            fifo_words_s <= n_fifo_words_s;
        end
    end

    always_comb begin : decode
        key_ready_s = 1'b0;
        bdi_ready_s = 1'b0;
        msg_auth_valid_s = 1'b0;
        n_msg_auth_s = msg_auth_s;
        n_update_key_s = update_key_s;
        n_isap_auth_encdec_s = isap_auth_encdec_s;
        n_fifo_words_s = fifo_words_s;
        n_eoi_s = eoi_s;
        n_eot_s = eot_s;
        isap_ctrl_s = 4'h0;
        case (state_s)
            IDLE: begin
                n_msg_auth_s = 1'b1;
                n_update_key_s = 1'b0;
                n_isap_auth_encdec_s = AUTH_ENC;
                n_eoi_s = 1'b0;
                n_eot_s = 1'b0;
                n_fifo_words_s = 16'd0;
                if (key_valid && key_update) begin
                    n_update_key_s = 1'b1;
                end
            end
            STORE_KEY: begin
                if (update_key_s) begin
                    key_ready_s = 1'b1;
                end
            end
            STORE_NONCE: begin
                bdi_ready_s = 1'b1;
                if (decrypt_in) begin
                    n_isap_auth_encdec_s = AUTH_DEC;
                end else begin
                    n_isap_auth_encdec_s = AUTH_ENC;
                end
                if (bdi_valid && bdi_type == HDR_NPUB && bdi_eoi) begin
                    n_eoi_s = 1'b1;
                end
            end
            ISAP_RK_REKEYING: begin
                if (isap_cnt_s == p_sB) begin
                    isap_ctrl_s = 4'h1;
                end
            end
            ISAP_RK_SQUEEZE: begin
                if (isap_cnt_s == p_sK) begin
                    isap_ctrl_s = 4'h1;
                end
            end
            ISAP_MAC_ABSORB_AD: begin
                if (bdi_valid && !(bdi_type == HDR_PT || bdi_type == HDR_CT)) begin
                    bdi_ready_s = 1'b1;
                end
                if (bdi_valid && bdi_type == HDR_AD) begin
                    if (bdi_eoi) begin
                        n_eoi_s = 1'b1;
                    end
                    if (bdi_eot) begin
                        n_eot_s = 1'b1;
                    end
                end
            end
            ISAP_MAC_ABSORB_AD_PAD: begin
                if (isap_cnt_s == p_sH) begin
                    isap_ctrl_s = 4'h2;
                end
                n_eot_s = 1'b0;
            end
            ISAP_MAC_ABSORB_CT: begin
                if (isap_auth_encdec_s == AUTH_DEC) begin
                    if (bdi_valid && bdi_type == HDR_CT && fifo_din_ready_s) begin
                        bdi_ready_s = 1'b1;
                        if (bdi_eoi) begin
                            n_eoi_s = 1'b1;
                        end
                        n_fifo_words_s = fifo_words_s + 16'd1;
                    end
                end else begin
                    if (fifo_dout_valid_s && fifo_dout_ready_s) begin
                        n_fifo_words_s = fifo_words_s - 16'd1;
                    end
                end
            end
            ISAP_MAC_ABSORB_CT_PAD: begin
                if (isap_cnt_s == p_sH) begin
                    isap_ctrl_s = 4'h2;
                end
            end
            ISAP_ENC_SQUEEZE_BLOCK: begin
                if (isap_auth_encdec_s == AUTH_ENC) begin
                    bdi_ready_s = bdo_ready;
                    if (bdi_valid && bdi_ready_s && bdi_type == HDR_PT && fifo_din_ready_s) begin
                        if (bdi_eoi) begin
                            n_eoi_s = 1'b1;
                        end
                        n_fifo_words_s = fifo_words_s + 16'd1;
                    end
                end else begin
                    if (fifo_dout_valid_s && fifo_dout_ready_s) begin
                        n_fifo_words_s = fifo_words_s - 16'd1;
                    end
                end
            end
            VERIFY_TAG: begin
                bdi_ready_s = 1'b1;
                if (bdi_valid && bdi_type == HDR_TAG && isap_state_cur_word_s != bdi_s) begin
                    n_msg_auth_s = 1'b0;
                end
            end
            WAIT_ACK: msg_auth_valid_s = 1'b1;
            default: begin end
        endcase
    end

    always_ff @(posedge clk) begin : word_counter
        if (rst == 1'b1) begin
            word_idx_s <= '0;
        end else begin
            case (state_s)
                IDLE: word_idx_s <= '0;
                STORE_KEY: begin
                    if (key_update) begin
                        if (key_valid && key_ready_s) begin
                            if (word_idx_s >= KEY_WORDS_C - 3'd1) begin
                                word_idx_s <= '0;
                            end else begin
                                word_idx_s <= word_idx_s + 3'd1;
                            end
                        end
                    end else begin
                        if (word_idx_s >= KEY_WORDS_C - 3'd1) begin
                            word_idx_s <= '0;
                        end else begin
                            word_idx_s <= word_idx_s + 3'd1;
                        end
                    end
                end
                STORE_NONCE: begin
                    if (bdi_valid && bdi_ready_s) begin
                        if (word_idx_s >= NPUB_WORDS_C - 3'd1) begin
                            word_idx_s <= '0;
                        end else begin
                            word_idx_s <= word_idx_s + 3'd1;
                        end
                    end
                end
                ISAP_ENC_SQUEEZE_BLOCK: begin
                    if (isap_auth_encdec_s == AUTH_DEC) begin
                        if (fifo_dout_valid_s && fifo_dout_ready_s && bdo_ready) begin
                            if (word_idx_s >= BLOCK_WORDS_C - 3'd1) begin
                                word_idx_s <= '0;
                            end else begin
                                word_idx_s <= word_idx_s + 3'd1;
                            end
                        end
                    end else begin
                        if (bdi_valid && bdi_ready_s && fifo_din_ready_s) begin
                            if (word_idx_s >= BLOCK_WORDS_C - 3'd1 && !bdi_eot) begin
                                word_idx_s <= '0;
                            end else if (bdi_eot) begin
                                word_idx_s <= '0;
                            end else begin
                                word_idx_s <= word_idx_s + 3'd1;
                            end
                        end
                    end
                end
                ISAP_MAC_SETUP_STATE: word_idx_s <= '0;
                ISAP_MAC_ABSORB_AD: begin
                    if (bdi_valid && bdi_ready_s && bdi_type == HDR_AD) begin
                        if (word_idx_s >= BLOCK_WORDS_C - 3'd1) begin
                            word_idx_s <= '0;
                        end else if (bdi_eot) begin
                            word_idx_s <= '0;
                        end else begin
                            word_idx_s <= word_idx_s + 3'd1;
                        end
                    end
                end
                ISAP_MAC_DOMAIN_SEPARATION: word_idx_s <= '0;
                EXTRACT_TAG: begin
                    if (bdo_valid_s && bdo_ready) begin
                        if (word_idx_s >= TAG_WORDS_C - 3'd1) begin
                            word_idx_s <= '0;
                        end else begin
                            word_idx_s <= word_idx_s + 3'd1;
                        end
                    end
                end
                ISAP_MAC_ABSORB_CT: begin
                    if (isap_auth_encdec_s == AUTH_DEC) begin
                        if (bdi_valid && bdi_ready_s && bdi_type == HDR_CT) begin
                            if (word_idx_s >= BLOCK_WORDS_C - 3'd1 && !bdi_eot) begin
                                word_idx_s <= '0;
                            end else if (bdi_eot) begin
                                word_idx_s <= '0;
                            end else begin
                                word_idx_s <= word_idx_s + 3'd1;
                            end
                        end
                    end else begin
                        if (fifo_dout_valid_s && fifo_dout_ready_s) begin
                            if (word_idx_s >= BLOCK_WORDS_C - 3'd1 || fifo_words_s == 16'd1) begin
                                word_idx_s <= '0;
                            end else begin
                                word_idx_s <= word_idx_s + 3'd1;
                            end
                        end
                    end
                end
                VERIFY_TAG: begin
                    if (bdi_valid && bdi_ready_s && bdi_type == HDR_TAG) begin
                        if (word_idx_s >= TAG_WORDS_C - 3'd1) begin
                            word_idx_s <= '0;
                        end else begin
                            word_idx_s <= word_idx_s + 3'd1;
                        end
                    end
                end
                default: begin end
            endcase
        end
    end

    always_ff @(posedge clk) begin : datapath_registers
        if (rst == 1'b1) begin
            isap_encmac_s <= ISAP_ENC;
        end else begin
            case (state_s)
                IDLE: begin
                    pad_added_s <= 1'b0;
                    fifo_last_word_valid_bytes_s <= '0;
                end
                STORE_KEY: begin
                    if (key_update) begin
                        if (key_valid && key_ready_s) begin
                            isap_key_s[CCW * word_idx_s +: CCW] <= key_s;
                        end
                    end
                end
                STORE_NONCE: begin
                    if (bdi_valid && bdi_ready_s) begin
                        isap_nonce_s[CCW * word_idx_s +: CCW] <= bdi_s;
                        if (word_idx_s >= NPUB_WORDS_C - 3'd1) begin
                            if (isap_auth_encdec_s == AUTH_DEC) begin
                                isap_encmac_s <= ISAP_MAC;
                            end else begin
                                isap_encmac_s <= ISAP_ENC;
                            end
                        end
                    end
                end
                // Initialize re-keying with the encryption or authentication IV.
                ISAP_RK_SETUP_STATE: begin
                    isap_state_s[p_k - 1:0] <= isap_key_s;
                    isap_state_s[p_n - 1:p_k + 64] <= '0;
                    isap_cnt_s <= p_sK;
                    if (isap_encmac_s == ISAP_ENC) begin
                        isap_state_s[p_k + 63:p_k] <= reverse_byte64(p_iv_ke);
                        isap_y_s <= reverse_byte128(isap_nonce_s);
                    end else begin
                        isap_state_s[p_k + 63:p_k] <= reverse_byte64(p_iv_ka);
                        isap_y_s <= reverse_byte128(isap_state_s[p_k - 1:0]);
                        isap_buf_s[p_n - p_k - 1:0] <= isap_state_s[p_n - 1:p_k];
                    end
                end
                ISAP_RK_INITIALIZE: begin
                    if (isap_cnt_s == 8'h01) begin
                        isap_cnt_s <= p_sB;
                        isap_cnt_y_s <= 7'd127;
                    end else begin
                        isap_cnt_s <= isap_cnt_s - 8'd1;
                    end
                    isap_state_s <= perm_out_s;
                end
                // Absorb the remaining Y bits one at a time.
                ISAP_RK_REKEYING: begin
                    if (isap_cnt_y_s == 7'd1 && isap_cnt_s == 8'h01) begin
                        isap_cnt_s <= p_sK;
                    end else if (isap_cnt_s == 8'h01) begin
                        isap_cnt_s <= p_sB;
                    end
                    isap_cnt_y_s <= isap_cnt_y_s - 7'd1;
                    isap_y_s <= {isap_y_s[126:0], isap_y_s[127]};
                    isap_state_s <= perm_out_s;
                end
                // Absorb the final Y bit and finish the re-keying permutation.
                ISAP_RK_SQUEEZE: begin
                    isap_cnt_s <= isap_cnt_s - 8'd1;
                    isap_state_s <= perm_out_s;
                end
                ISAP_ENC_INITIALIZE: begin
                    isap_cnt_s <= p_sE;
                    isap_state_s[p_n - 1:p_n - p_k] <= isap_nonce_s[p_k - 1:0];
                end
                ISAP_ENC_PERMUTE_PE: begin
                    isap_cnt_s <= isap_cnt_s - 8'd1;
                    isap_state_s <= perm_out_s;
                end
                ISAP_ENC_SQUEEZE_BLOCK: begin
                    if (isap_auth_encdec_s == AUTH_DEC) begin
                        if (n_state_s == ISAP_ENC_PERMUTE_PE) begin
                            isap_cnt_s <= p_sE;
                        end
                    end else begin
                        if (bdi_valid && bdi_ready_s && fifo_din_ready_s) begin
                            if (bdi_eot) begin
                                fifo_last_word_valid_bytes_s <= bdi_valid_bytes;
                            end
                        end
                        if (n_state_s == ISAP_ENC_PERMUTE_PE) begin
                            isap_cnt_s <= p_sE;
                        end
                    end
                end
                ISAP_MAC_SETUP_STATE: begin
                    isap_state_s[p_k - 1:0] <= isap_nonce_s;
                    isap_state_s[p_k + 63:p_k] <= reverse_byte64(p_iv_a);
                    isap_state_s[p_n - 1:p_k + 64] <= '0;
                    isap_cnt_s <= p_sH;
                    isap_encmac_s <= ISAP_MAC;
                end
                ISAP_MAC_INITIALIZE: begin
                    isap_state_s <= perm_out_s;
                    if (n_state_s == ISAP_MAC_ABSORB_AD_PAD) begin
                        isap_cnt_s <= p_sH;
                    end else begin
                        isap_cnt_s <= isap_cnt_s - 8'd1;
                    end
                end
                ISAP_MAC_WAIT_INPUT: begin
                    if (n_state_s != ISAP_MAC_WAIT_INPUT) begin
                        isap_cnt_s <= p_sH;
                    end
                end
                ISAP_MAC_ABSORB_AD: begin
                    if (bdi_valid && bdi_ready_s && bdi_type == HDR_AD) begin
                        isap_state_s <= isap_state_n_s;
                        if (bdi_eot && bdi_partial_s) begin
                            pad_added_s <= 1'b1;
                        end else if (bdi_eot && !bdi_partial_s) begin
                            if (word_idx_s < BLOCK_WORDS_C - 3'd1) begin
                                pad_added_s <= 1'b1;
                            end else begin
                                pad_added_s <= 1'b0;
                            end
                        end
                    end
                    if (n_state_s == ISAP_MAC_PROCESS_AD) begin
                        isap_cnt_s <= p_sH;
                    end
                end
                ISAP_MAC_PROCESS_AD: begin
                    isap_cnt_s <= isap_cnt_s - 8'd1;
                    isap_state_s <= perm_out_s;
                    if (n_state_s == ISAP_MAC_ABSORB_AD_PAD) begin
                        isap_cnt_s <= p_sH;
                    end
                end
                ISAP_MAC_ABSORB_AD_PAD: begin
                    isap_cnt_s <= isap_cnt_s - 8'd1;
                    isap_state_s <= perm_out_s;
                    pad_added_s <= 1'b1;
                end
                // Separate associated data from ciphertext absorption.
                ISAP_MAC_DOMAIN_SEPARATION: begin
                    pad_added_s <= 1'b0;
                    isap_state_s[p_n - 8] <= isap_state_s[p_n - 8] ^ 1'b1;
                    if (n_state_s == ISAP_MAC_ABSORB_CT_PAD) begin
                        isap_cnt_s <= p_sH;
                    end
                end
                ISAP_MAC_ABSORB_CT: begin
                    if (n_state_s == ISAP_MAC_PROCESS_CT) begin
                        isap_cnt_s <= p_sH;
                    end
                    if (isap_auth_encdec_s == AUTH_DEC) begin
                        if (bdi_valid && bdi_ready_s && bdi_type == HDR_CT) begin
                            if (bdi_eot) begin
                                fifo_last_word_valid_bytes_s <= bdi_valid_bytes;
                            end
                            isap_state_s <= isap_state_n_s;
                            if (bdi_eot) begin
                                if ((&bdi_valid_bytes) == 1'b1) begin
                                    if (word_idx_s < BLOCK_WORDS_C - 3'd1) begin
                                        pad_added_s <= 1'b1;
                                    end else begin
                                        pad_added_s <= 1'b0;
                                    end
                                end else begin
                                    pad_added_s <= 1'b1;
                                end
                            end
                        end
                    end else begin
                        if (fifo_dout_valid_s && fifo_dout_ready_s) begin
                            isap_state_s <= isap_state_n_s;
                            if (fifo_words_s == 16'd1) begin
                                if ((&fifo_last_word_valid_bytes_s) == 1'b1) begin
                                    if (word_idx_s < BLOCK_WORDS_C - 3'd1) begin
                                        pad_added_s <= 1'b1;
                                    end else begin
                                        pad_added_s <= 1'b0;
                                    end
                                end else begin
                                    pad_added_s <= 1'b1;
                                end
                            end
                        end
                    end
                end
                ISAP_MAC_PROCESS_CT: begin
                    isap_cnt_s <= isap_cnt_s - 8'd1;
                    isap_state_s <= perm_out_s;
                    if (n_state_s == ISAP_MAC_ABSORB_CT_PAD) begin
                        isap_cnt_s <= p_sH;
                    end
                end
                ISAP_MAC_ABSORB_CT_PAD: begin
                    isap_cnt_s <= isap_cnt_s - 8'd1;
                    isap_state_s <= perm_out_s;
                end
                // Restore the saved upper portion of the MAC state.
                ISAP_MAC_FINALIZE_AFTER_RK_STATE_SETUP: begin
                    isap_state_s[p_n - 1:p_k] <= isap_buf_s[p_n - p_k - 1:0];
                    isap_cnt_s <= p_sH;
                end
                ISAP_MAC_FINALIZE_PERMUTE_PH: begin
                    isap_cnt_s <= isap_cnt_s - 8'd1;
                    isap_state_s <= perm_out_s;
                end
                // Decryption begins only after successful authentication is acknowledged.
                WAIT_ACK: begin
                    if (n_state_s == ISAP_RK_SETUP_STATE) begin
                        isap_encmac_s <= ISAP_ENC;
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule

`default_nettype wire
