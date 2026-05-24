`ifndef GIN_CLUSTER_SV
`define GIN_CLUSTER_SV

`include "define.svh"
`include "src/PE_array/GIN/GIN_Bus.v"

// Two-level cluster GIN:
//   GLB stream -> cluster-row Y bus -> cluster-column X bus -> one valid per PE_cluster
module GIN_cluster #(
    parameter int NUMS_CLUSTER_ROW = 3,
    parameter int NUMS_CLUSTER_COL = 4,
    parameter int DATA_SIZE        = `DATA_BITS,
    parameter int CLUSTER_XID_BITS = 2,
    parameter int CLUSTER_YID_BITS = 2
)(
    input  logic                                      clk,
    input  logic                                      rst,

    // GLB side
    input  logic                                      in_valid,
    output logic                                      in_ready,
    input  logic [DATA_SIZE-1:0]                      in_data,

    // cluster destination tag
    input  logic [CLUSTER_XID_BITS-1:0]               cluster_tag_X,
    input  logic [CLUSTER_YID_BITS-1:0]               cluster_tag_Y,

    // cluster ID scan-chain config
    input  logic                                      set_cluster_XID,
    input  logic [CLUSTER_XID_BITS-1:0]               cluster_XID_scan_in,
    input  logic                                      set_cluster_YID,
    input  logic [CLUSTER_YID_BITS-1:0]               cluster_YID_scan_in,

    // PE_cluster side
    input  logic [NUMS_CLUSTER_ROW*NUMS_CLUSTER_COL-1:0] cluster_ready,
    output logic [NUMS_CLUSTER_ROW*NUMS_CLUSTER_COL-1:0] cluster_valid,
    output logic [DATA_SIZE-1:0]                         cluster_data
);

    logic [NUMS_CLUSTER_ROW-1:0] row_valid;
    logic [NUMS_CLUSTER_ROW-1:0] row_ready;
    logic [DATA_SIZE-1:0]        row_data;

    logic [CLUSTER_YID_BITS-1:0] yid_scan_out_unused;
    logic [CLUSTER_XID_BITS-1:0] xid_scan_chain [0:NUMS_CLUSTER_ROW];

    genvar r;

    assign xid_scan_chain[0] = cluster_XID_scan_in;
    assign cluster_data      = row_data;

    // First level: select cluster row.
    GIN_Bus #(
        .NUMS_SLAVE (NUMS_CLUSTER_ROW),
        .ID_SIZE    (CLUSTER_YID_BITS),
        .DATA_SIZE  (DATA_SIZE),
                .STATIC_ID_ENABLE(1'b1)
    ) u_cluster_y_bus (
        .clk          (clk),
        .rst          (rst),
        .tag          (cluster_tag_Y),
        .master_valid (in_valid),
        .master_data  (in_data),
        .master_ready (in_ready),

        .slave_ready  (row_ready),
        .slave_valid  (row_valid),
        .slave_data   (row_data),

        .set_id       (set_cluster_YID),
        .ID_scan_in   (cluster_YID_scan_in),
        .ID_scan_out  (yid_scan_out_unused)
    );

    // Second level: select cluster column inside selected cluster row.
    generate
        for (r = 0; r < NUMS_CLUSTER_ROW; r = r + 1) begin : GEN_CLUSTER_X_BUS
            GIN_Bus #(
                .NUMS_SLAVE (NUMS_CLUSTER_COL),
                .ID_SIZE    (CLUSTER_XID_BITS),
                .DATA_SIZE  (DATA_SIZE),
                .STATIC_ID_ENABLE(1'b1)
            ) u_cluster_x_bus (
                .clk          (clk),
                .rst          (rst),
                .tag          (cluster_tag_X),
                .master_valid (row_valid[r]),
                .master_data  (row_data),
                .master_ready (row_ready[r]),

                .slave_ready  (cluster_ready[r*NUMS_CLUSTER_COL +: NUMS_CLUSTER_COL]),
                .slave_valid  (cluster_valid[r*NUMS_CLUSTER_COL +: NUMS_CLUSTER_COL]),
                .slave_data   (),

                .set_id       (set_cluster_XID),
                .ID_scan_in   (xid_scan_chain[r]),
                .ID_scan_out  (xid_scan_chain[r+1])
            );
        end
    endgenerate

endmodule

`endif
