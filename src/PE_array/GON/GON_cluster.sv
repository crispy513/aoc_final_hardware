`ifndef GON_CLUSTER_SV
`define GON_CLUSTER_SV

`include "define.svh"
`include "src/PE_array/GON/GON_Bus.v"

// Two-level cluster GON:
//   PE_cluster outputs -> cluster-column X bus -> cluster-row Y bus -> GLB output
module GON_cluster #(
    parameter int NUMS_CLUSTER_ROW = 3,
    parameter int NUMS_CLUSTER_COL = 4,
    parameter int DATA_SIZE        = `DATA_BITS,
    parameter int CLUSTER_XID_BITS = 2,
    parameter int CLUSTER_YID_BITS = 2
)(
    input  logic                                      clk,
    input  logic                                      rst,

    // cluster source tag: which cluster should send opsum
    input  logic [CLUSTER_XID_BITS-1:0]               cluster_tag_X,
    input  logic [CLUSTER_YID_BITS-1:0]               cluster_tag_Y,

    // cluster ID scan-chain config
    input  logic                                      set_cluster_XID,
    input  logic [CLUSTER_XID_BITS-1:0]               cluster_XID_scan_in,
    input  logic                                      set_cluster_YID,
    input  logic [CLUSTER_YID_BITS-1:0]               cluster_YID_scan_in,

    // PE_cluster side
    input  logic [NUMS_CLUSTER_ROW*NUMS_CLUSTER_COL-1:0]       cluster_valid,
    output logic [NUMS_CLUSTER_ROW*NUMS_CLUSTER_COL-1:0]       cluster_ready,
    input  logic [DATA_SIZE*NUMS_CLUSTER_ROW*NUMS_CLUSTER_COL-1:0] cluster_data,

    // GLB side
    output logic                                      out_valid,
    input  logic                                      out_ready,
    output logic [DATA_SIZE-1:0]                      out_data
);

    logic [NUMS_CLUSTER_ROW-1:0]           row_valid;
    logic [NUMS_CLUSTER_ROW-1:0]           row_ready;
    logic [DATA_SIZE*NUMS_CLUSTER_ROW-1:0] row_data;

    logic [CLUSTER_YID_BITS-1:0] yid_scan_out_unused;
    logic [CLUSTER_XID_BITS-1:0] xid_scan_chain [0:NUMS_CLUSTER_ROW];

    genvar r;

    assign xid_scan_chain[0] = cluster_XID_scan_in;

    // First level: each cluster row selects one cluster column.
    generate
        for (r = 0; r < NUMS_CLUSTER_ROW; r = r + 1) begin : GEN_CLUSTER_X_BUS
            GON_Bus #(
                .NUMS_MASTER      (NUMS_CLUSTER_COL),
                .ID_SIZE          (CLUSTER_XID_BITS),
                .DATA_SIZE        (DATA_SIZE),
                .STATIC_ID_ENABLE (1'b1)
            ) u_x_bus (
                .clk          (clk),
                .rst          (rst),
                .tag          (cluster_tag_X),

                .master_valid (cluster_valid[r*NUMS_CLUSTER_COL +: NUMS_CLUSTER_COL]),
                .master_data  (cluster_data[r*(NUMS_CLUSTER_COL*DATA_SIZE) +: (NUMS_CLUSTER_COL*DATA_SIZE)]),
                .master_ready (cluster_ready[r*NUMS_CLUSTER_COL +: NUMS_CLUSTER_COL]),

                .slave_valid  (row_valid[r]),
                .slave_ready  (row_ready[r]),
                .slave_data   (row_data[r*DATA_SIZE +: DATA_SIZE]),

                .set_id       (set_cluster_XID),
                .ID_scan_in   (xid_scan_chain[r]),
                .ID_scan_out  (xid_scan_chain[r+1])
            );
        end
    endgenerate

    // Second level: select cluster row.
    GON_Bus #(
        .NUMS_MASTER      (NUMS_CLUSTER_ROW),
        .ID_SIZE          (CLUSTER_YID_BITS),
        .DATA_SIZE        (DATA_SIZE),
        .STATIC_ID_ENABLE (1'b1)
    ) u_y_bus (
        .clk          (clk),
        .rst          (rst),
        .tag          (cluster_tag_Y),

        .master_valid (row_valid),
        .master_data  (row_data),
        .master_ready (row_ready),

        .slave_valid  (out_valid),
        .slave_ready  (out_ready),
        .slave_data   (out_data),

        .set_id       (set_cluster_YID),
        .ID_scan_in   (cluster_YID_scan_in),
        .ID_scan_out  (yid_scan_out_unused)
    );

endmodule

`endif
