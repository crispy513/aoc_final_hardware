`ifndef EYERISS_CONTROLLER_SV
`define EYERISS_CONTROLLER_SV

`include "define.svh"

module controller #(
    parameter int NUMS_PE_ROW = `NUMS_PE_ROW,
    parameter int NUMS_PE_COL = `NUMS_PE_COL,
    parameter int XID_BITS    = `XID_BITS,
    parameter int YID_BITS    = `YID_BITS,
    parameter int CONFIG_SIZE = `CONFIG_SIZE,

    parameter int PE_ROW_PER_CLUSTER = 2,
    parameter int PE_COL_PER_CLUSTER = 2,
    parameter int NUMS_CLUSTER_ROW   = NUMS_PE_ROW / PE_ROW_PER_CLUSTER,
    parameter int NUMS_CLUSTER_COL   = NUMS_PE_COL / PE_COL_PER_CLUSTER,

    parameter int LOCAL_XID_BITS   = (PE_COL_PER_CLUSTER <= 1) ? 1 : $clog2(PE_COL_PER_CLUSTER),
    parameter int LOCAL_YID_BITS   = (PE_ROW_PER_CLUSTER <= 1) ? 1 : $clog2(PE_ROW_PER_CLUSTER),
    parameter int CLUSTER_XID_BITS = (NUMS_CLUSTER_COL   <= 1) ? 1 : $clog2(NUMS_CLUSTER_COL),
    parameter int CLUSTER_YID_BITS = (NUMS_CLUSTER_ROW   <= 1) ? 1 : $clog2(NUMS_CLUSTER_ROW),

    parameter int IFMAP_AW  = 12,
    parameter int FILTER_AW = 12,
    parameter int IPSUM_AW  = 12,
    parameter int OPSUM_AW  = 12,

    parameter int IFMAP_BMAP_AW  = 9,
    parameter int FILTER_BMAP_AW = 9,
    parameter int IPSUM_BMAP_AW  = 9,
    parameter int OPSUM_BMAP_AW  = 9,
    parameter int SPARSE_BLOCK_SIZE = 8
)(
    input  logic clk,
    input  logic rst,

    // Software command.
    input  logic sw_start,
    output logic busy,
    output logic done,
    output logic error,

    // Layer/control configuration from software.
    input  logic [2:0] p_i,
    input  logic [5:0] f_i,
    input  logic [2:0] q_i,
    input  logic       conv_mode_i,
    input  logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] active_pe_mask_i,

    input  logic [XID_BITS-1:0] ifmap_tag_X_i,
    input  logic [YID_BITS-1:0] ifmap_tag_Y_i,
    input  logic [XID_BITS-1:0] filter_tag_X_i,
    input  logic [YID_BITS-1:0] filter_tag_Y_i,
    input  logic [XID_BITS-1:0] ipsum_tag_X_i,
    input  logic [YID_BITS-1:0] ipsum_tag_Y_i,
    input  logic [XID_BITS-1:0] opsum_tag_X_i,
    input  logic [YID_BITS-1:0] opsum_tag_Y_i,

    // GLB compressed stream descriptors. Software fills the memories first.
    input  logic [IFMAP_AW-1:0]  ifmap_base_i,
    input  logic [IFMAP_AW:0]    ifmap_len_i,
    input  logic [FILTER_AW-1:0] filter_base_i,
    input  logic [FILTER_AW:0]   filter_len_i,
    input  logic [IPSUM_AW-1:0]  ipsum_base_i,
    input  logic [IPSUM_AW:0]    ipsum_len_i,

    // Bitmap stream descriptors for the three input streams.
    input  logic [IFMAP_BMAP_AW-1:0]  ifmap_bitmap_base_i,
    input  logic [IFMAP_BMAP_AW:0]    ifmap_bitmap_len_i,
    input  logic [FILTER_BMAP_AW-1:0] filter_bitmap_base_i,
    input  logic [FILTER_BMAP_AW:0]   filter_bitmap_len_i,
    input  logic [IPSUM_BMAP_AW-1:0]  ipsum_bitmap_base_i,
    input  logic [IPSUM_BMAP_AW:0]    ipsum_bitmap_len_i,

    // Opsum capture descriptors.
    input  logic [OPSUM_AW:0]         opsum_dense_len_i,
    input  logic [OPSUM_AW-1:0]       opsum_base_i,
    input  logic [OPSUM_BMAP_AW-1:0]  opsum_bitmap_base_i,

    // Busy/done feedback from top_with_glb.
    input  logic ifmap_busy,
    input  logic ifmap_done,
    input  logic filter_busy,
    input  logic filter_done,
    input  logic ipsum_busy,
    input  logic ipsum_done,

    input  logic ifmap_bitmap_busy,
    input  logic ifmap_bitmap_done,
    input  logic filter_bitmap_busy,
    input  logic filter_bitmap_done,
    input  logic ipsum_bitmap_busy,
    input  logic ipsum_bitmap_done,

    input  logic opsum_encode_busy,
    input  logic opsum_encode_done,
    input  logic opsum_busy,
    input  logic opsum_done,
    input  logic opsum_bitmap_busy,
    input  logic opsum_bitmap_done,

    // Commands to top_with_glb.
    output logic start_ifmap,
    output logic [IFMAP_AW-1:0] ifmap_base,
    output logic [IFMAP_AW:0]   ifmap_len,

    output logic start_filter,
    output logic [FILTER_AW-1:0] filter_base,
    output logic [FILTER_AW:0]   filter_len,

    output logic start_ipsum,
    output logic [IPSUM_AW-1:0] ipsum_base,
    output logic [IPSUM_AW:0]   ipsum_len,

    output logic start_ifmap_bitmap,
    output logic [IFMAP_BMAP_AW-1:0] ifmap_bitmap_base,
    output logic [IFMAP_BMAP_AW:0]   ifmap_bitmap_len,

    output logic start_filter_bitmap,
    output logic [FILTER_BMAP_AW-1:0] filter_bitmap_base,
    output logic [FILTER_BMAP_AW:0]   filter_bitmap_len,

    output logic start_ipsum_bitmap,
    output logic [IPSUM_BMAP_AW-1:0] ipsum_bitmap_base,
    output logic [IPSUM_BMAP_AW:0]   ipsum_bitmap_len,

    output logic start_encode_opsum,
    output logic [OPSUM_AW:0] opsum_dense_len,

    output logic start_capture_opsum,
    output logic [OPSUM_AW-1:0] opsum_base,
    output logic [OPSUM_AW:0]   opsum_len,

    output logic start_capture_opsum_bitmap,
    output logic [OPSUM_BMAP_AW-1:0] opsum_bitmap_base,
    output logic [OPSUM_BMAP_AW:0]   opsum_bitmap_len,

    // PE_array configuration and routing.
    output logic set_XID,
    output logic [XID_BITS-1:0] ifmap_XID_scan_in,
    output logic [XID_BITS-1:0] filter_XID_scan_in,
    output logic [XID_BITS-1:0] ipsum_XID_scan_in,
    output logic [XID_BITS-1:0] opsum_XID_scan_in,

    output logic set_YID,
    output logic [YID_BITS-1:0] ifmap_YID_scan_in,
    output logic [YID_BITS-1:0] filter_YID_scan_in,
    output logic [YID_BITS-1:0] ipsum_YID_scan_in,
    output logic [YID_BITS-1:0] opsum_YID_scan_in,

    output logic set_LN,
    output logic [NUMS_PE_ROW-2:0] LN_config_in,

    output logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] PE_en,
    output logic [CONFIG_SIZE-1:0] PE_config,

    output logic [XID_BITS-1:0] ifmap_tag_X,
    output logic [YID_BITS-1:0] ifmap_tag_Y,
    output logic [XID_BITS-1:0] filter_tag_X,
    output logic [YID_BITS-1:0] filter_tag_Y,
    output logic [XID_BITS-1:0] ipsum_tag_X,
    output logic [YID_BITS-1:0] ipsum_tag_Y,
    output logic [XID_BITS-1:0] opsum_tag_X,
    output logic [YID_BITS-1:0] opsum_tag_Y
);

    function automatic int max2(input int a, input int b);
        max2 = (a > b) ? a : b;
    endfunction

    localparam int X_SCAN_CYCLES = max2(PE_COL_PER_CLUSTER, NUMS_CLUSTER_COL);
    localparam int Y_SCAN_CYCLES = max2(PE_ROW_PER_CLUSTER, NUMS_CLUSTER_ROW);
    localparam int SCAN_CYCLES   = max2(X_SCAN_CYCLES, Y_SCAN_CYCLES);
    localparam int SCAN_CNT_W    = (SCAN_CYCLES <= 1) ? 1 : $clog2(SCAN_CYCLES);

    typedef enum logic [2:0] {
        S_IDLE,
        S_WAIT_IDLE,
        S_SCAN,
        S_KICK,
        S_RUN,
        S_DONE,
        S_ERROR
    } state_t;

    state_t state_q, state_d;

    logic [SCAN_CNT_W-1:0] scan_count_q, scan_count_d;

    logic saw_ifmap_q, saw_ifmap_d;
    logic saw_filter_q, saw_filter_d;
    logic saw_ipsum_q, saw_ipsum_d;
    logic saw_ifmap_bitmap_q, saw_ifmap_bitmap_d;
    logic saw_filter_bitmap_q, saw_filter_bitmap_d;
    logic saw_ipsum_bitmap_q, saw_ipsum_bitmap_d;
    logic saw_opsum_encode_q, saw_opsum_encode_d;
    logic saw_opsum_q, saw_opsum_d;
    logic saw_opsum_bitmap_q, saw_opsum_bitmap_d;

    logic resource_idle;
    logic config_valid;
    logic run_complete;
    logic [OPSUM_BMAP_AW:0] computed_opsum_bitmap_len;
    logic [1:0] p_m1;
    logic [4:0] f_m1;
    logic [1:0] q_m1;

    function automatic logic [XID_BITS-1:0] scan_x_value(
        input logic [SCAN_CNT_W-1:0] scan_idx
    );
        int rem;
        logic [LOCAL_XID_BITS-1:0] local_id;
        logic [CLUSTER_XID_BITS-1:0] cluster_id;
        logic [XID_BITS-1:0] packed_id;
    begin
        rem = SCAN_CYCLES - 1 - scan_idx;
        local_id   = (rem < PE_COL_PER_CLUSTER) ? rem[LOCAL_XID_BITS-1:0] : '0;
        cluster_id = (rem < NUMS_CLUSTER_COL)   ? rem[CLUSTER_XID_BITS-1:0] : '0;
        packed_id = '0;
        packed_id[LOCAL_XID_BITS-1:0] = local_id;
        packed_id[LOCAL_XID_BITS +: CLUSTER_XID_BITS] = cluster_id;
        scan_x_value = packed_id;
    end
    endfunction

    function automatic logic [YID_BITS-1:0] scan_y_value(
        input logic [SCAN_CNT_W-1:0] scan_idx
    );
        int rem;
        logic [LOCAL_YID_BITS-1:0] local_id;
        logic [CLUSTER_YID_BITS-1:0] cluster_id;
        logic [YID_BITS-1:0] packed_id;
    begin
        rem = SCAN_CYCLES - 1 - scan_idx;
        local_id   = (rem < PE_ROW_PER_CLUSTER) ? rem[LOCAL_YID_BITS-1:0] : '0;
        cluster_id = (rem < NUMS_CLUSTER_ROW)   ? rem[CLUSTER_YID_BITS-1:0] : '0;
        packed_id = '0;
        packed_id[LOCAL_YID_BITS-1:0] = local_id;
        packed_id[LOCAL_YID_BITS +: CLUSTER_YID_BITS] = cluster_id;
        scan_y_value = packed_id;
    end
    endfunction

    assign resource_idle = !(ifmap_busy || filter_busy || ipsum_busy ||
                             ifmap_bitmap_busy || filter_bitmap_busy || ipsum_bitmap_busy ||
                             opsum_encode_busy || opsum_busy || opsum_bitmap_busy);

    assign config_valid = (p_i >= 3'd1) && (p_i <= 3'd4) &&
                          (f_i >= 6'd1) && (f_i <= 6'd32) &&
                          (q_i >= 3'd1) && (q_i <= 3'd4) &&
                          (active_pe_mask_i != '0);

    assign computed_opsum_bitmap_len =
        (opsum_dense_len_i + (SPARSE_BLOCK_SIZE - 1)) / SPARSE_BLOCK_SIZE;

    assign run_complete =
        (saw_ifmap_q        || ifmap_done        || (ifmap_len_i == '0)) &&
        (saw_filter_q       || filter_done       || (filter_len_i == '0)) &&
        (saw_ipsum_q        || ipsum_done        || (ipsum_len_i == '0)) &&
        (saw_ifmap_bitmap_q || ifmap_bitmap_done || (ifmap_bitmap_len_i == '0)) &&
        (saw_filter_bitmap_q || filter_bitmap_done || (filter_bitmap_len_i == '0)) &&
        (saw_ipsum_bitmap_q || ipsum_bitmap_done || (ipsum_bitmap_len_i == '0)) &&
        (saw_opsum_encode_q || opsum_encode_done || (opsum_dense_len_i == '0)) &&
        (saw_opsum_q        || opsum_done        || (opsum_dense_len_i == '0)) &&
        (saw_opsum_bitmap_q || opsum_bitmap_done || (computed_opsum_bitmap_len == '0));

    always_comb begin
        state_d = state_q;
        scan_count_d = scan_count_q;

        unique case (state_q)
            S_IDLE: begin
                scan_count_d = '0;
                if (sw_start) begin
                    if (config_valid) begin
                        state_d = S_WAIT_IDLE;
                    end
                    else begin
                        state_d = S_ERROR;
                    end
                end
            end

            S_WAIT_IDLE: begin
                if (resource_idle) begin
                    state_d = S_SCAN;
                end
            end

            S_SCAN: begin
                if (scan_count_q == (SCAN_CYCLES - 1)) begin
                    scan_count_d = '0;
                    state_d = S_KICK;
                end
                else begin
                    scan_count_d = scan_count_q + 1'b1;
                end
            end

            S_KICK: begin
                state_d = S_RUN;
            end

            S_RUN: begin
                if (run_complete) begin
                    state_d = S_DONE;
                end
            end

            S_DONE: begin
                if (!sw_start) begin
                    state_d = S_IDLE;
                end
            end

            S_ERROR: begin
                if (!sw_start) begin
                    state_d = S_IDLE;
                end
            end

            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    always_comb begin
        saw_ifmap_d = saw_ifmap_q;
        saw_filter_d = saw_filter_q;
        saw_ipsum_d = saw_ipsum_q;
        saw_ifmap_bitmap_d = saw_ifmap_bitmap_q;
        saw_filter_bitmap_d = saw_filter_bitmap_q;
        saw_ipsum_bitmap_d = saw_ipsum_bitmap_q;
        saw_opsum_encode_d = saw_opsum_encode_q;
        saw_opsum_d = saw_opsum_q;
        saw_opsum_bitmap_d = saw_opsum_bitmap_q;

        if (state_q == S_KICK) begin
            saw_ifmap_d = (ifmap_len_i == '0);
            saw_filter_d = (filter_len_i == '0);
            saw_ipsum_d = (ipsum_len_i == '0);
            saw_ifmap_bitmap_d = (ifmap_bitmap_len_i == '0);
            saw_filter_bitmap_d = (filter_bitmap_len_i == '0);
            saw_ipsum_bitmap_d = (ipsum_bitmap_len_i == '0);
            saw_opsum_encode_d = (opsum_dense_len_i == '0);
            saw_opsum_d = (opsum_dense_len_i == '0);
            saw_opsum_bitmap_d = (computed_opsum_bitmap_len == '0);
        end
        else if (state_q == S_RUN) begin
            saw_ifmap_d |= ifmap_done;
            saw_filter_d |= filter_done;
            saw_ipsum_d |= ipsum_done;
            saw_ifmap_bitmap_d |= ifmap_bitmap_done;
            saw_filter_bitmap_d |= filter_bitmap_done;
            saw_ipsum_bitmap_d |= ipsum_bitmap_done;
            saw_opsum_encode_d |= opsum_encode_done;
            saw_opsum_d |= opsum_done;
            saw_opsum_bitmap_d |= opsum_bitmap_done;
        end
        else if (state_q == S_IDLE) begin
            saw_ifmap_d = 1'b0;
            saw_filter_d = 1'b0;
            saw_ipsum_d = 1'b0;
            saw_ifmap_bitmap_d = 1'b0;
            saw_filter_bitmap_d = 1'b0;
            saw_ipsum_bitmap_d = 1'b0;
            saw_opsum_encode_d = 1'b0;
            saw_opsum_d = 1'b0;
            saw_opsum_bitmap_d = 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q <= S_IDLE;
            scan_count_q <= '0;
            saw_ifmap_q <= 1'b0;
            saw_filter_q <= 1'b0;
            saw_ipsum_q <= 1'b0;
            saw_ifmap_bitmap_q <= 1'b0;
            saw_filter_bitmap_q <= 1'b0;
            saw_ipsum_bitmap_q <= 1'b0;
            saw_opsum_encode_q <= 1'b0;
            saw_opsum_q <= 1'b0;
            saw_opsum_bitmap_q <= 1'b0;
        end
        else begin
            state_q <= state_d;
            scan_count_q <= scan_count_d;
            saw_ifmap_q <= saw_ifmap_d;
            saw_filter_q <= saw_filter_d;
            saw_ipsum_q <= saw_ipsum_d;
            saw_ifmap_bitmap_q <= saw_ifmap_bitmap_d;
            saw_filter_bitmap_q <= saw_filter_bitmap_d;
            saw_ipsum_bitmap_q <= saw_ipsum_bitmap_d;
            saw_opsum_encode_q <= saw_opsum_encode_d;
            saw_opsum_q <= saw_opsum_d;
            saw_opsum_bitmap_q <= saw_opsum_bitmap_d;
        end
    end

    always_comb begin
        p_m1 = (p_i == '0) ? 2'd0 : (p_i - 3'd1);
        f_m1 = (f_i == '0) ? 5'd0 : (f_i - 6'd1);
        q_m1 = (q_i == '0) ? 2'd0 : (q_i - 3'd1);

        PE_config = '0;
        PE_config[9:0] = {conv_mode_i, p_m1, f_m1, q_m1};
    end

    assign busy  = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
    assign done  = (state_q == S_DONE);
    assign error = (state_q == S_ERROR);

    assign start_ifmap = (state_q == S_KICK) && (ifmap_len_i != '0);
    assign start_filter = (state_q == S_KICK) && (filter_len_i != '0);
    assign start_ipsum = (state_q == S_KICK) && (ipsum_len_i != '0);
    assign start_ifmap_bitmap = (state_q == S_KICK) && (ifmap_bitmap_len_i != '0);
    assign start_filter_bitmap = (state_q == S_KICK) && (filter_bitmap_len_i != '0);
    assign start_ipsum_bitmap = (state_q == S_KICK) && (ipsum_bitmap_len_i != '0);
    assign start_encode_opsum = (state_q == S_KICK) && (opsum_dense_len_i != '0);
    assign start_capture_opsum = (state_q == S_KICK) && (opsum_dense_len_i != '0);
    assign start_capture_opsum_bitmap = (state_q == S_KICK) && (computed_opsum_bitmap_len != '0);

    assign ifmap_base = ifmap_base_i;
    assign ifmap_len = ifmap_len_i;
    assign filter_base = filter_base_i;
    assign filter_len = filter_len_i;
    assign ipsum_base = ipsum_base_i;
    assign ipsum_len = ipsum_len_i;

    assign ifmap_bitmap_base = ifmap_bitmap_base_i;
    assign ifmap_bitmap_len = ifmap_bitmap_len_i;
    assign filter_bitmap_base = filter_bitmap_base_i;
    assign filter_bitmap_len = filter_bitmap_len_i;
    assign ipsum_bitmap_base = ipsum_bitmap_base_i;
    assign ipsum_bitmap_len = ipsum_bitmap_len_i;

    assign opsum_dense_len = opsum_dense_len_i;
    assign opsum_base = opsum_base_i;
    assign opsum_len = opsum_dense_len_i;
    assign opsum_bitmap_base = opsum_bitmap_base_i;
    assign opsum_bitmap_len = computed_opsum_bitmap_len;

    assign set_XID = (state_q == S_SCAN);
    assign set_YID = (state_q == S_SCAN);
    assign set_LN  = (state_q == S_SCAN) && (scan_count_q == '0);

    assign ifmap_XID_scan_in = scan_x_value(scan_count_q);
    assign filter_XID_scan_in = scan_x_value(scan_count_q);
    assign ipsum_XID_scan_in = scan_x_value(scan_count_q);
    assign opsum_XID_scan_in = scan_x_value(scan_count_q);

    assign ifmap_YID_scan_in = scan_y_value(scan_count_q);
    assign filter_YID_scan_in = scan_y_value(scan_count_q);
    assign ipsum_YID_scan_in = scan_y_value(scan_count_q);
    assign opsum_YID_scan_in = scan_y_value(scan_count_q);

    assign LN_config_in = '1;

    assign PE_en = ((state_q == S_KICK) || (state_q == S_RUN)) ? active_pe_mask_i : '0;

    assign ifmap_tag_X = ifmap_tag_X_i;
    assign ifmap_tag_Y = ifmap_tag_Y_i;
    assign filter_tag_X = filter_tag_X_i;
    assign filter_tag_Y = filter_tag_Y_i;
    assign ipsum_tag_X = ipsum_tag_X_i;
    assign ipsum_tag_Y = ipsum_tag_Y_i;
    assign opsum_tag_X = opsum_tag_X_i;
    assign opsum_tag_Y = opsum_tag_Y_i;

endmodule

`endif // EYERISS_CONTROLLER_SV
