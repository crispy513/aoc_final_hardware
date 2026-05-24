`ifndef TOP_WITH_CONTROLLER_SV
`define TOP_WITH_CONTROLLER_SV

`include "define.svh"
`include "src/controller.sv"
`include "src/top.sv"

module top_with_controller #(
    parameter int NUMS_PE_ROW = `NUMS_PE_ROW,
    parameter int NUMS_PE_COL = `NUMS_PE_COL,
    parameter int XID_BITS    = `XID_BITS,
    parameter int YID_BITS    = `YID_BITS,
    parameter int DATA_SIZE   = `DATA_BITS,
    parameter int CONFIG_SIZE = `CONFIG_SIZE,

    parameter int PE_ROW_PER_CLUSTER = 2,
    parameter int PE_COL_PER_CLUSTER = 2,

    parameter int IFMAP_DEPTH  = 4096,
    parameter int FILTER_DEPTH = 4096,
    parameter int IPSUM_DEPTH  = 4096,
    parameter int OPSUM_DEPTH  = 4096,

    parameter int IFMAP_AW  = (IFMAP_DEPTH  <= 1) ? 1 : $clog2(IFMAP_DEPTH),
    parameter int FILTER_AW = (FILTER_DEPTH <= 1) ? 1 : $clog2(FILTER_DEPTH),
    parameter int IPSUM_AW  = (IPSUM_DEPTH  <= 1) ? 1 : $clog2(IPSUM_DEPTH),
    parameter int OPSUM_AW  = (OPSUM_DEPTH  <= 1) ? 1 : $clog2(OPSUM_DEPTH),
    parameter int ADDR_W    = ((IFMAP_AW > FILTER_AW) ?
                              ((IFMAP_AW > IPSUM_AW) ?
                              ((IFMAP_AW > OPSUM_AW) ? IFMAP_AW : OPSUM_AW) :
                              ((IPSUM_AW > OPSUM_AW) ? IPSUM_AW : OPSUM_AW)) :
                              ((FILTER_AW > IPSUM_AW) ?
                              ((FILTER_AW > OPSUM_AW) ? FILTER_AW : OPSUM_AW) :
                              ((IPSUM_AW > OPSUM_AW) ? IPSUM_AW : OPSUM_AW))),

    parameter int SPARSE_BLOCK_SIZE = 8,
    parameter int SPARSE_COUNT_W    = (SPARSE_BLOCK_SIZE <= 1) ? 1 : $clog2(SPARSE_BLOCK_SIZE + 1),

    parameter int IFMAP_BMAP_DEPTH  = (IFMAP_DEPTH  + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,
    parameter int FILTER_BMAP_DEPTH = (FILTER_DEPTH + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,
    parameter int IPSUM_BMAP_DEPTH  = (IPSUM_DEPTH  + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,
    parameter int OPSUM_BMAP_DEPTH  = (OPSUM_DEPTH  + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,

    parameter int IFMAP_BMAP_AW  = (IFMAP_BMAP_DEPTH  <= 1) ? 1 : $clog2(IFMAP_BMAP_DEPTH),
    parameter int FILTER_BMAP_AW = (FILTER_BMAP_DEPTH <= 1) ? 1 : $clog2(FILTER_BMAP_DEPTH),
    parameter int IPSUM_BMAP_AW  = (IPSUM_BMAP_DEPTH  <= 1) ? 1 : $clog2(IPSUM_BMAP_DEPTH),
    parameter int OPSUM_BMAP_AW  = (OPSUM_BMAP_DEPTH  <= 1) ? 1 : $clog2(OPSUM_BMAP_DEPTH),
    parameter int BMAP_ADDR_W    = ((IFMAP_BMAP_AW > FILTER_BMAP_AW) ?
                                  ((IFMAP_BMAP_AW > IPSUM_BMAP_AW) ?
                                  ((IFMAP_BMAP_AW > OPSUM_BMAP_AW) ? IFMAP_BMAP_AW : OPSUM_BMAP_AW) :
                                  ((IPSUM_BMAP_AW > OPSUM_BMAP_AW) ? IPSUM_BMAP_AW : OPSUM_BMAP_AW)) :
                                  ((FILTER_BMAP_AW > IPSUM_BMAP_AW) ?
                                  ((FILTER_BMAP_AW > OPSUM_BMAP_AW) ? FILTER_BMAP_AW : OPSUM_BMAP_AW) :
                                  ((IPSUM_BMAP_AW > OPSUM_BMAP_AW) ? IPSUM_BMAP_AW : OPSUM_BMAP_AW)))
)(
    input  logic clk,
    input  logic rst,

    // Host writes/reads compressed GLB data.
    input  logic                 wr_en,
    input  logic [1:0]           wr_sel,
    input  logic [ADDR_W-1:0]    wr_addr,
    input  logic [DATA_SIZE-1:0] wr_data,
    input  logic                 rd_en,
    input  logic [1:0]           rd_sel,
    input  logic [ADDR_W-1:0]    rd_addr,
    output logic [DATA_SIZE-1:0] rd_data,

    // Host writes/reads bitmap metadata.
    input  logic                         bitmap_wr_en,
    input  logic [1:0]                   bitmap_wr_sel,
    input  logic [BMAP_ADDR_W-1:0]       bitmap_wr_addr,
    input  logic [SPARSE_BLOCK_SIZE-1:0] bitmap_wr_data,
    input  logic [SPARSE_COUNT_W-1:0]    bitmap_wr_nz_count,
    input  logic                         bitmap_rd_en,
    input  logic [1:0]                   bitmap_rd_sel,
    input  logic [BMAP_ADDR_W-1:0]       bitmap_rd_addr,
    output logic [SPARSE_BLOCK_SIZE-1:0] bitmap_rd_data,
    output logic [SPARSE_COUNT_W-1:0]    bitmap_rd_nz_count,

    // Software-visible command and layer settings.
    input  logic sw_start,
    output logic controller_busy,
    output logic controller_done,
    output logic controller_error,

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

    // Software supplies descriptors after loading GLB and bitmap memories.
    input  logic [IFMAP_AW-1:0]  ifmap_base_i,
    input  logic [IFMAP_AW:0]    ifmap_len_i,
    input  logic [FILTER_AW-1:0] filter_base_i,
    input  logic [FILTER_AW:0]   filter_len_i,
    input  logic [IPSUM_AW-1:0]  ipsum_base_i,
    input  logic [IPSUM_AW:0]    ipsum_len_i,

    input  logic [IFMAP_BMAP_AW-1:0]  ifmap_bitmap_base_i,
    input  logic [IFMAP_BMAP_AW:0]    ifmap_bitmap_len_i,
    input  logic [FILTER_BMAP_AW-1:0] filter_bitmap_base_i,
    input  logic [FILTER_BMAP_AW:0]   filter_bitmap_len_i,
    input  logic [IPSUM_BMAP_AW-1:0]  ipsum_bitmap_base_i,
    input  logic [IPSUM_BMAP_AW:0]    ipsum_bitmap_len_i,

    input  logic [OPSUM_AW:0]        opsum_dense_len_i,
    input  logic [OPSUM_AW-1:0]      opsum_base_i,
    input  logic [OPSUM_BMAP_AW-1:0] opsum_bitmap_base_i,

    // Useful completion counters for software checks.
    output logic [OPSUM_AW:0] opsum_encoded_dense_count,
    output logic [OPSUM_AW:0] opsum_encoded_cmp_count,
    output logic [OPSUM_AW:0] opsum_encoded_bitmap_count,
    output logic [OPSUM_AW:0] opsum_captured_count,

    // Debug: compressed GLB side and dense PE side.
    output logic                 GLB_ifmap_valid_dbg,
    output logic                 GLB_ifmap_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_ifmap_data_dbg,
    output logic                 PE_ifmap_valid_dbg,
    output logic                 PE_ifmap_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_ifmap_data_dbg,
    output logic                 GLB_filter_valid_dbg,
    output logic                 GLB_filter_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_filter_data_dbg,
    output logic                 PE_filter_valid_dbg,
    output logic                 PE_filter_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_filter_data_dbg,
    output logic                 GLB_ipsum_valid_dbg,
    output logic                 GLB_ipsum_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_ipsum_data_dbg,
    output logic                 PE_ipsum_valid_dbg,
    output logic                 PE_ipsum_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_ipsum_data_dbg,
    output logic                 PE_opsum_valid_dbg,
    output logic                 PE_opsum_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_opsum_data_dbg,
    output logic                 GLB_opsum_valid_dbg,
    output logic                 GLB_opsum_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_opsum_data_dbg
);

    logic start_ifmap;
    logic [IFMAP_AW-1:0] ifmap_base;
    logic [IFMAP_AW:0] ifmap_len;
    logic ifmap_busy;
    logic ifmap_done;

    logic start_filter;
    logic [FILTER_AW-1:0] filter_base;
    logic [FILTER_AW:0] filter_len;
    logic filter_busy;
    logic filter_done;

    logic start_ipsum;
    logic [IPSUM_AW-1:0] ipsum_base;
    logic [IPSUM_AW:0] ipsum_len;
    logic ipsum_busy;
    logic ipsum_done;

    logic start_ifmap_bitmap;
    logic [IFMAP_BMAP_AW-1:0] ifmap_bitmap_base;
    logic [IFMAP_BMAP_AW:0] ifmap_bitmap_len;
    logic ifmap_bitmap_busy;
    logic ifmap_bitmap_done;

    logic start_filter_bitmap;
    logic [FILTER_BMAP_AW-1:0] filter_bitmap_base;
    logic [FILTER_BMAP_AW:0] filter_bitmap_len;
    logic filter_bitmap_busy;
    logic filter_bitmap_done;

    logic start_ipsum_bitmap;
    logic [IPSUM_BMAP_AW-1:0] ipsum_bitmap_base;
    logic [IPSUM_BMAP_AW:0] ipsum_bitmap_len;
    logic ipsum_bitmap_busy;
    logic ipsum_bitmap_done;

    logic start_encode_opsum;
    logic [OPSUM_AW:0] opsum_dense_len;
    logic opsum_encode_busy;
    logic opsum_encode_done;

    logic start_capture_opsum;
    logic [OPSUM_AW-1:0] opsum_base;
    logic [OPSUM_AW:0] opsum_len;
    logic opsum_busy;
    logic opsum_done;

    logic start_capture_opsum_bitmap;
    logic [OPSUM_BMAP_AW-1:0] opsum_bitmap_base;
    logic [OPSUM_BMAP_AW:0] opsum_bitmap_len;
    logic opsum_bitmap_busy;
    logic opsum_bitmap_done;

    logic set_XID;
    logic [XID_BITS-1:0] ifmap_XID_scan_in;
    logic [XID_BITS-1:0] filter_XID_scan_in;
    logic [XID_BITS-1:0] ipsum_XID_scan_in;
    logic [XID_BITS-1:0] opsum_XID_scan_in;
    logic set_YID;
    logic [YID_BITS-1:0] ifmap_YID_scan_in;
    logic [YID_BITS-1:0] filter_YID_scan_in;
    logic [YID_BITS-1:0] ipsum_YID_scan_in;
    logic [YID_BITS-1:0] opsum_YID_scan_in;
    logic set_LN;
    logic [NUMS_PE_ROW-2:0] LN_config_in;

    logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] PE_en;
    logic [CONFIG_SIZE-1:0] PE_config;
    logic [XID_BITS-1:0] ifmap_tag_X;
    logic [YID_BITS-1:0] ifmap_tag_Y;
    logic [XID_BITS-1:0] filter_tag_X;
    logic [YID_BITS-1:0] filter_tag_Y;
    logic [XID_BITS-1:0] ipsum_tag_X;
    logic [YID_BITS-1:0] ipsum_tag_Y;
    logic [XID_BITS-1:0] opsum_tag_X;
    logic [YID_BITS-1:0] opsum_tag_Y;

    controller #(
        .NUMS_PE_ROW       (NUMS_PE_ROW),
        .NUMS_PE_COL       (NUMS_PE_COL),
        .XID_BITS          (XID_BITS),
        .YID_BITS          (YID_BITS),
        .CONFIG_SIZE       (CONFIG_SIZE),
        .PE_ROW_PER_CLUSTER(PE_ROW_PER_CLUSTER),
        .PE_COL_PER_CLUSTER(PE_COL_PER_CLUSTER),
        .IFMAP_AW          (IFMAP_AW),
        .FILTER_AW         (FILTER_AW),
        .IPSUM_AW          (IPSUM_AW),
        .OPSUM_AW          (OPSUM_AW),
        .IFMAP_BMAP_AW     (IFMAP_BMAP_AW),
        .FILTER_BMAP_AW    (FILTER_BMAP_AW),
        .IPSUM_BMAP_AW     (IPSUM_BMAP_AW),
        .OPSUM_BMAP_AW     (OPSUM_BMAP_AW),
        .SPARSE_BLOCK_SIZE (SPARSE_BLOCK_SIZE)
    ) u_controller (
        .clk(clk),
        .rst(rst),
        .sw_start(sw_start),
        .busy(controller_busy),
        .done(controller_done),
        .error(controller_error),
        .p_i(p_i),
        .f_i(f_i),
        .q_i(q_i),
        .conv_mode_i(conv_mode_i),
        .active_pe_mask_i(active_pe_mask_i),
        .ifmap_tag_X_i(ifmap_tag_X_i),
        .ifmap_tag_Y_i(ifmap_tag_Y_i),
        .filter_tag_X_i(filter_tag_X_i),
        .filter_tag_Y_i(filter_tag_Y_i),
        .ipsum_tag_X_i(ipsum_tag_X_i),
        .ipsum_tag_Y_i(ipsum_tag_Y_i),
        .opsum_tag_X_i(opsum_tag_X_i),
        .opsum_tag_Y_i(opsum_tag_Y_i),
        .ifmap_base_i(ifmap_base_i),
        .ifmap_len_i(ifmap_len_i),
        .filter_base_i(filter_base_i),
        .filter_len_i(filter_len_i),
        .ipsum_base_i(ipsum_base_i),
        .ipsum_len_i(ipsum_len_i),
        .ifmap_bitmap_base_i(ifmap_bitmap_base_i),
        .ifmap_bitmap_len_i(ifmap_bitmap_len_i),
        .filter_bitmap_base_i(filter_bitmap_base_i),
        .filter_bitmap_len_i(filter_bitmap_len_i),
        .ipsum_bitmap_base_i(ipsum_bitmap_base_i),
        .ipsum_bitmap_len_i(ipsum_bitmap_len_i),
        .opsum_dense_len_i(opsum_dense_len_i),
        .opsum_base_i(opsum_base_i),
        .opsum_bitmap_base_i(opsum_bitmap_base_i),
        .ifmap_busy(ifmap_busy),
        .ifmap_done(ifmap_done),
        .filter_busy(filter_busy),
        .filter_done(filter_done),
        .ipsum_busy(ipsum_busy),
        .ipsum_done(ipsum_done),
        .ifmap_bitmap_busy(ifmap_bitmap_busy),
        .ifmap_bitmap_done(ifmap_bitmap_done),
        .filter_bitmap_busy(filter_bitmap_busy),
        .filter_bitmap_done(filter_bitmap_done),
        .ipsum_bitmap_busy(ipsum_bitmap_busy),
        .ipsum_bitmap_done(ipsum_bitmap_done),
        .opsum_encode_busy(opsum_encode_busy),
        .opsum_encode_done(opsum_encode_done),
        .opsum_busy(opsum_busy),
        .opsum_done(opsum_done),
        .opsum_bitmap_busy(opsum_bitmap_busy),
        .opsum_bitmap_done(opsum_bitmap_done),
        .start_ifmap(start_ifmap),
        .ifmap_base(ifmap_base),
        .ifmap_len(ifmap_len),
        .start_filter(start_filter),
        .filter_base(filter_base),
        .filter_len(filter_len),
        .start_ipsum(start_ipsum),
        .ipsum_base(ipsum_base),
        .ipsum_len(ipsum_len),
        .start_ifmap_bitmap(start_ifmap_bitmap),
        .ifmap_bitmap_base(ifmap_bitmap_base),
        .ifmap_bitmap_len(ifmap_bitmap_len),
        .start_filter_bitmap(start_filter_bitmap),
        .filter_bitmap_base(filter_bitmap_base),
        .filter_bitmap_len(filter_bitmap_len),
        .start_ipsum_bitmap(start_ipsum_bitmap),
        .ipsum_bitmap_base(ipsum_bitmap_base),
        .ipsum_bitmap_len(ipsum_bitmap_len),
        .start_encode_opsum(start_encode_opsum),
        .opsum_dense_len(opsum_dense_len),
        .start_capture_opsum(start_capture_opsum),
        .opsum_base(opsum_base),
        .opsum_len(opsum_len),
        .start_capture_opsum_bitmap(start_capture_opsum_bitmap),
        .opsum_bitmap_base(opsum_bitmap_base),
        .opsum_bitmap_len(opsum_bitmap_len),
        .set_XID(set_XID),
        .ifmap_XID_scan_in(ifmap_XID_scan_in),
        .filter_XID_scan_in(filter_XID_scan_in),
        .ipsum_XID_scan_in(ipsum_XID_scan_in),
        .opsum_XID_scan_in(opsum_XID_scan_in),
        .set_YID(set_YID),
        .ifmap_YID_scan_in(ifmap_YID_scan_in),
        .filter_YID_scan_in(filter_YID_scan_in),
        .ipsum_YID_scan_in(ipsum_YID_scan_in),
        .opsum_YID_scan_in(opsum_YID_scan_in),
        .set_LN(set_LN),
        .LN_config_in(LN_config_in),
        .PE_en(PE_en),
        .PE_config(PE_config),
        .ifmap_tag_X(ifmap_tag_X),
        .ifmap_tag_Y(ifmap_tag_Y),
        .filter_tag_X(filter_tag_X),
        .filter_tag_Y(filter_tag_Y),
        .ipsum_tag_X(ipsum_tag_X),
        .ipsum_tag_Y(ipsum_tag_Y),
        .opsum_tag_X(opsum_tag_X),
        .opsum_tag_Y(opsum_tag_Y)
    );

    top_with_glb #(
        .NUMS_PE_ROW       (NUMS_PE_ROW),
        .NUMS_PE_COL       (NUMS_PE_COL),
        .XID_BITS          (XID_BITS),
        .YID_BITS          (YID_BITS),
        .DATA_SIZE         (DATA_SIZE),
        .CONFIG_SIZE       (CONFIG_SIZE),
        .PE_ROW_PER_CLUSTER(PE_ROW_PER_CLUSTER),
        .PE_COL_PER_CLUSTER(PE_COL_PER_CLUSTER),
        .IFMAP_DEPTH       (IFMAP_DEPTH),
        .FILTER_DEPTH      (FILTER_DEPTH),
        .IPSUM_DEPTH       (IPSUM_DEPTH),
        .OPSUM_DEPTH       (OPSUM_DEPTH),
        .SPARSE_BLOCK_SIZE (SPARSE_BLOCK_SIZE)
    ) u_top (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .wr_sel(wr_sel),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_sel(rd_sel),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .bitmap_wr_en(bitmap_wr_en),
        .bitmap_wr_sel(bitmap_wr_sel),
        .bitmap_wr_addr(bitmap_wr_addr),
        .bitmap_wr_data(bitmap_wr_data),
        .bitmap_wr_nz_count(bitmap_wr_nz_count),
        .bitmap_rd_en(bitmap_rd_en),
        .bitmap_rd_sel(bitmap_rd_sel),
        .bitmap_rd_addr(bitmap_rd_addr),
        .bitmap_rd_data(bitmap_rd_data),
        .bitmap_rd_nz_count(bitmap_rd_nz_count),
        .start_ifmap(start_ifmap),
        .ifmap_base(ifmap_base),
        .ifmap_len(ifmap_len),
        .ifmap_busy(ifmap_busy),
        .ifmap_done(ifmap_done),
        .start_filter(start_filter),
        .filter_base(filter_base),
        .filter_len(filter_len),
        .filter_busy(filter_busy),
        .filter_done(filter_done),
        .start_ipsum(start_ipsum),
        .ipsum_base(ipsum_base),
        .ipsum_len(ipsum_len),
        .ipsum_busy(ipsum_busy),
        .ipsum_done(ipsum_done),
        .start_ifmap_bitmap(start_ifmap_bitmap),
        .ifmap_bitmap_base(ifmap_bitmap_base),
        .ifmap_bitmap_len(ifmap_bitmap_len),
        .ifmap_bitmap_busy(ifmap_bitmap_busy),
        .ifmap_bitmap_done(ifmap_bitmap_done),
        .start_filter_bitmap(start_filter_bitmap),
        .filter_bitmap_base(filter_bitmap_base),
        .filter_bitmap_len(filter_bitmap_len),
        .filter_bitmap_busy(filter_bitmap_busy),
        .filter_bitmap_done(filter_bitmap_done),
        .start_ipsum_bitmap(start_ipsum_bitmap),
        .ipsum_bitmap_base(ipsum_bitmap_base),
        .ipsum_bitmap_len(ipsum_bitmap_len),
        .ipsum_bitmap_busy(ipsum_bitmap_busy),
        .ipsum_bitmap_done(ipsum_bitmap_done),
        .start_encode_opsum(start_encode_opsum),
        .opsum_dense_len(opsum_dense_len),
        .opsum_encode_busy(opsum_encode_busy),
        .opsum_encode_done(opsum_encode_done),
        .opsum_encoded_dense_count(opsum_encoded_dense_count),
        .opsum_encoded_cmp_count(opsum_encoded_cmp_count),
        .opsum_encoded_bitmap_count(opsum_encoded_bitmap_count),
        .start_capture_opsum(start_capture_opsum),
        .opsum_base(opsum_base),
        .opsum_len(opsum_len),
        .opsum_captured_count(opsum_captured_count),
        .opsum_busy(opsum_busy),
        .opsum_done(opsum_done),
        .start_capture_opsum_bitmap(start_capture_opsum_bitmap),
        .opsum_bitmap_base(opsum_bitmap_base),
        .opsum_bitmap_len(opsum_bitmap_len),
        .opsum_bitmap_busy(opsum_bitmap_busy),
        .opsum_bitmap_done(opsum_bitmap_done),
        .set_XID(set_XID),
        .ifmap_XID_scan_in(ifmap_XID_scan_in),
        .filter_XID_scan_in(filter_XID_scan_in),
        .ipsum_XID_scan_in(ipsum_XID_scan_in),
        .opsum_XID_scan_in(opsum_XID_scan_in),
        .set_YID(set_YID),
        .ifmap_YID_scan_in(ifmap_YID_scan_in),
        .filter_YID_scan_in(filter_YID_scan_in),
        .ipsum_YID_scan_in(ipsum_YID_scan_in),
        .opsum_YID_scan_in(opsum_YID_scan_in),
        .set_LN(set_LN),
        .LN_config_in(LN_config_in),
        .PE_en(PE_en),
        .PE_config(PE_config),
        .ifmap_tag_X(ifmap_tag_X),
        .ifmap_tag_Y(ifmap_tag_Y),
        .filter_tag_X(filter_tag_X),
        .filter_tag_Y(filter_tag_Y),
        .ipsum_tag_X(ipsum_tag_X),
        .ipsum_tag_Y(ipsum_tag_Y),
        .opsum_tag_X(opsum_tag_X),
        .opsum_tag_Y(opsum_tag_Y),
        .GLB_ifmap_valid_dbg(GLB_ifmap_valid_dbg),
        .GLB_ifmap_ready_dbg(GLB_ifmap_ready_dbg),
        .GLB_ifmap_data_dbg(GLB_ifmap_data_dbg),
        .PE_ifmap_valid_dbg(PE_ifmap_valid_dbg),
        .PE_ifmap_ready_dbg(PE_ifmap_ready_dbg),
        .PE_ifmap_data_dbg(PE_ifmap_data_dbg),
        .GLB_filter_valid_dbg(GLB_filter_valid_dbg),
        .GLB_filter_ready_dbg(GLB_filter_ready_dbg),
        .GLB_filter_data_dbg(GLB_filter_data_dbg),
        .PE_filter_valid_dbg(PE_filter_valid_dbg),
        .PE_filter_ready_dbg(PE_filter_ready_dbg),
        .PE_filter_data_dbg(PE_filter_data_dbg),
        .GLB_ipsum_valid_dbg(GLB_ipsum_valid_dbg),
        .GLB_ipsum_ready_dbg(GLB_ipsum_ready_dbg),
        .GLB_ipsum_data_dbg(GLB_ipsum_data_dbg),
        .PE_ipsum_valid_dbg(PE_ipsum_valid_dbg),
        .PE_ipsum_ready_dbg(PE_ipsum_ready_dbg),
        .PE_ipsum_data_dbg(PE_ipsum_data_dbg),
        .PE_opsum_valid_dbg(PE_opsum_valid_dbg),
        .PE_opsum_ready_dbg(PE_opsum_ready_dbg),
        .PE_opsum_data_dbg(PE_opsum_data_dbg),
        .GLB_opsum_valid_dbg(GLB_opsum_valid_dbg),
        .GLB_opsum_ready_dbg(GLB_opsum_ready_dbg),
        .GLB_opsum_data_dbg(GLB_opsum_data_dbg)
    );

endmodule

`endif // TOP_WITH_CONTROLLER_SV
