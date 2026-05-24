`ifndef PE_CLUSTER_SV
`define PE_CLUSTER_SV

`include "define.svh"
`include "src/PE_array/PE.sv"
`include "src/PE_array/GIN/GIN_local.v"
`include "src/PE_array/GON/GON_local.v"

module PE_cluster #(
    parameter int PE_ROW_PER_CLUSTER = 2,
    parameter int PE_COL_PER_CLUSTER = 2,
    parameter int DATA_SIZE          = `DATA_BITS,
    parameter int CONFIG_SIZE        = `CONFIG_SIZE,
    parameter int LOCAL_XID_BITS     = 1,
    parameter int LOCAL_YID_BITS     = 1
)(
    input  logic clk,
    input  logic rst,

    input  logic cluster_en,

    input  logic [PE_ROW_PER_CLUSTER*PE_COL_PER_CLUSTER-1:0] PE_en,
    input  logic [CONFIG_SIZE-1:0] PE_config,

    input  logic [LOCAL_XID_BITS-1:0] ifmap_local_tag_X,
    input  logic [LOCAL_YID_BITS-1:0] ifmap_local_tag_Y,
    input  logic [LOCAL_XID_BITS-1:0] filter_local_tag_X,
    input  logic [LOCAL_YID_BITS-1:0] filter_local_tag_Y,
    input  logic [LOCAL_XID_BITS-1:0] ipsum_local_tag_X,
    input  logic [LOCAL_YID_BITS-1:0] ipsum_local_tag_Y,

    input  logic [LOCAL_XID_BITS-1:0] opsum_local_tag_X,
    input  logic [LOCAL_YID_BITS-1:0] opsum_local_tag_Y,

    input  logic                      set_XID,
    input  logic [LOCAL_XID_BITS-1:0] ifmap_XID_scan_in,
    input  logic [LOCAL_XID_BITS-1:0] filter_XID_scan_in,
    input  logic [LOCAL_XID_BITS-1:0] ipsum_XID_scan_in,
    input  logic [LOCAL_XID_BITS-1:0] opsum_XID_scan_in,

    input  logic                      set_YID,
    input  logic [LOCAL_YID_BITS-1:0] ifmap_YID_scan_in,
    input  logic [LOCAL_YID_BITS-1:0] filter_YID_scan_in,
    input  logic [LOCAL_YID_BITS-1:0] ipsum_YID_scan_in,
    input  logic [LOCAL_YID_BITS-1:0] opsum_YID_scan_in,

    input  logic                 ifmap_valid_i,
    output logic                 ifmap_ready_o,
    input  logic [DATA_SIZE-1:0] ifmap_data_i,

    input  logic                 filter_valid_i,
    output logic                 filter_ready_o,
    input  logic [DATA_SIZE-1:0] filter_data_i,

    input  logic                 ipsum_valid_i,
    output logic                 ipsum_ready_o,
    input  logic [DATA_SIZE-1:0] ipsum_data_i,

    output logic                 opsum_valid_o,
    input  logic                 opsum_ready_i,
    output logic [DATA_SIZE-1:0] opsum_data_o
);

    localparam int NUMS_LOCAL_PE = PE_ROW_PER_CLUSTER * PE_COL_PER_CLUSTER;

    logic [NUMS_LOCAL_PE-1:0] ifmap_pe_valid;
    logic [NUMS_LOCAL_PE-1:0] ifmap_pe_ready;
    logic [DATA_SIZE-1:0]     ifmap_pe_data;

    logic [NUMS_LOCAL_PE-1:0] filter_pe_valid;
    logic [NUMS_LOCAL_PE-1:0] filter_pe_ready;
    logic [DATA_SIZE-1:0]     filter_pe_data;

    logic [NUMS_LOCAL_PE-1:0] ipsum_pe_valid;
    logic [NUMS_LOCAL_PE-1:0] ipsum_pe_ready;
    logic [DATA_SIZE-1:0]     ipsum_pe_data;

    logic [NUMS_LOCAL_PE-1:0] pe_opsum_valid;
    logic [NUMS_LOCAL_PE-1:0] pe_opsum_ready;
    logic [DATA_SIZE*NUMS_LOCAL_PE-1:0] pe_opsum_data;

    logic ifmap_local_ready;
    logic filter_local_ready;
    logic ipsum_local_ready;

    assign ifmap_ready_o  = cluster_en ? ifmap_local_ready  : 1'b1;
    assign filter_ready_o = cluster_en ? filter_local_ready : 1'b1;
    assign ipsum_ready_o  = cluster_en ? ipsum_local_ready  : 1'b1;

    GIN_local #(
        .NUMS_PE_ROW (PE_ROW_PER_CLUSTER),
        .NUMS_PE_COL (PE_COL_PER_CLUSTER),
        .DATA_SIZE   (DATA_SIZE),
        .XID_BITS    (LOCAL_XID_BITS),
        .YID_BITS    (LOCAL_YID_BITS)
    ) u_ifmap_local_gin (
        .clk         (clk),
        .rst         (rst),
        .GIN_valid   (ifmap_valid_i & cluster_en),
        .GIN_ready   (ifmap_local_ready),
        .GIN_data    (ifmap_data_i),
        .tag_X       (ifmap_local_tag_X),
        .tag_Y       (ifmap_local_tag_Y),
        .set_XID     (set_XID),
        .XID_scan_in (ifmap_XID_scan_in),
        .set_YID     (set_YID),
        .YID_scan_in (ifmap_YID_scan_in),
        .PE_ready    (ifmap_pe_ready),
        .PE_valid    (ifmap_pe_valid),
        .PE_data     (ifmap_pe_data)
    );

    GIN_local #(
        .NUMS_PE_ROW (PE_ROW_PER_CLUSTER),
        .NUMS_PE_COL (PE_COL_PER_CLUSTER),
        .DATA_SIZE   (DATA_SIZE),
        .XID_BITS    (LOCAL_XID_BITS),
        .YID_BITS    (LOCAL_YID_BITS)
    ) u_filter_local_gin (
        .clk         (clk),
        .rst         (rst),
        .GIN_valid   (filter_valid_i & cluster_en),
        .GIN_ready   (filter_local_ready),
        .GIN_data    (filter_data_i),
        .tag_X       (filter_local_tag_X),
        .tag_Y       (filter_local_tag_Y),
        .set_XID     (set_XID),
        .XID_scan_in (filter_XID_scan_in),
        .set_YID     (set_YID),
        .YID_scan_in (filter_YID_scan_in),
        .PE_ready    (filter_pe_ready),
        .PE_valid    (filter_pe_valid),
        .PE_data     (filter_pe_data)
    );

    GIN_local #(
        .NUMS_PE_ROW (PE_ROW_PER_CLUSTER),
        .NUMS_PE_COL (PE_COL_PER_CLUSTER),
        .DATA_SIZE   (DATA_SIZE),
        .XID_BITS    (LOCAL_XID_BITS),
        .YID_BITS    (LOCAL_YID_BITS)
    ) u_ipsum_local_gin (
        .clk         (clk),
        .rst         (rst),
        .GIN_valid   (ipsum_valid_i & cluster_en),
        .GIN_ready   (ipsum_local_ready),
        .GIN_data    (ipsum_data_i),
        .tag_X       (ipsum_local_tag_X),
        .tag_Y       (ipsum_local_tag_Y),
        .set_XID     (set_XID),
        .XID_scan_in (ipsum_XID_scan_in),
        .set_YID     (set_YID),
        .YID_scan_in (ipsum_YID_scan_in),
        .PE_ready    (ipsum_pe_ready),
        .PE_valid    (ipsum_pe_valid),
        .PE_data     (ipsum_pe_data)
    );

    genvar r, c;
    generate
        for (r = 0; r < PE_ROW_PER_CLUSTER; r = r + 1) begin : GEN_LOCAL_ROW
            for (c = 0; c < PE_COL_PER_CLUSTER; c = c + 1) begin : GEN_LOCAL_COL
                localparam int LIDX = r * PE_COL_PER_CLUSTER + c;

                PE u_pe (
                    .clk          (clk),
                    .rst          (rst),
                    .PE_en        (PE_en[LIDX]),
                    .i_config     (PE_config),
                    .ifmap        (ifmap_pe_data),
                    .filter       (filter_pe_data),
                    .ipsum        (ipsum_pe_data),
                    .ifmap_valid  (ifmap_pe_valid[LIDX]),
                    .filter_valid (filter_pe_valid[LIDX]),
                    .ipsum_valid  (ipsum_pe_valid[LIDX]),
                    .opsum_ready  (pe_opsum_ready[LIDX]),
                    .opsum        (pe_opsum_data[LIDX*DATA_SIZE +: DATA_SIZE]),
                    .ifmap_ready  (ifmap_pe_ready[LIDX]),
                    .filter_ready (filter_pe_ready[LIDX]),
                    .ipsum_ready  (ipsum_pe_ready[LIDX]),
                    .opsum_valid  (pe_opsum_valid[LIDX])
                );
            end
        end
    endgenerate

    GON_local #(
        .NUMS_PE_ROW (PE_ROW_PER_CLUSTER),
        .NUMS_PE_COL (PE_COL_PER_CLUSTER),
        .DATA_SIZE   (DATA_SIZE),
        .XID_BITS    (LOCAL_XID_BITS),
        .YID_BITS    (LOCAL_YID_BITS)
    ) u_opsum_local_gon (
        .clk         (clk),
        .rst         (rst),
        .tag_X       (opsum_local_tag_X),
        .tag_Y       (opsum_local_tag_Y),
        .set_XID     (set_XID),
        .XID_scan_in (opsum_XID_scan_in),
        .set_YID     (set_YID),
        .YID_scan_in (opsum_YID_scan_in),
        .PE_valid    (cluster_en ? pe_opsum_valid : '0),
        .PE_ready    (pe_opsum_ready),
        .PE_data     (pe_opsum_data),
        .GON_valid   (opsum_valid_o),
        .GON_ready   (opsum_ready_i),
        .GON_data    (opsum_data_o)
    );

endmodule

`endif
