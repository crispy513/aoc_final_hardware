`ifndef GIN_LOCAL_V
`define GIN_LOCAL_V

`include "define.svh"
`include "src/PE_array/GIN/GIN_Bus.v"

// Two-level local GIN inside one PE_cluster:
//   input stream -> Y bus selects local row -> X bus selects local column -> PE valid bits
module GIN_local #(
    parameter int NUMS_PE_ROW = 2,
    parameter int NUMS_PE_COL = 2,
    parameter int DATA_SIZE   = `DATA_BITS,
    parameter int XID_BITS    = 1,
    parameter int YID_BITS    = 1
)(
    input  logic                              clk,
    input  logic                              rst,

    // upstream cluster pipeline register <-> local GIN
    input  logic                              GIN_valid,
    output logic                              GIN_ready,
    input  logic [DATA_SIZE-1:0]              GIN_data,

    // local destination tag
    input  logic [XID_BITS-1:0]               tag_X,
    input  logic [YID_BITS-1:0]               tag_Y,

    // local ID scan-chain config
    input  logic                              set_XID,
    input  logic [XID_BITS-1:0]               XID_scan_in,
    input  logic                              set_YID,
    input  logic [YID_BITS-1:0]               YID_scan_in,

    // local PE side
    input  logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] PE_ready,
    output logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] PE_valid,
    output logic [DATA_SIZE-1:0]               PE_data
);

    logic [NUMS_PE_ROW-1:0] row_valid;
    logic [NUMS_PE_ROW-1:0] row_ready;
    logic [DATA_SIZE-1:0]   row_data;

    logic [YID_BITS-1:0] yid_scan_out_unused;
    logic [XID_BITS-1:0] xid_scan_chain [0:NUMS_PE_ROW];

    genvar r;

    assign xid_scan_chain[0] = XID_scan_in;
    assign PE_data           = row_data;

    // First level: select local PE row.
    GIN_Bus #(
        .NUMS_SLAVE (NUMS_PE_ROW),
        .ID_SIZE    (YID_BITS),
        .DATA_SIZE  (DATA_SIZE),
                .STATIC_ID_ENABLE(1'b1)
    ) u_y_bus (
        .clk          (clk),
        .rst          (rst),
        .tag          (tag_Y),
        .master_valid (GIN_valid),
        .master_data  (GIN_data),
        .master_ready (GIN_ready),

        .slave_ready  (row_ready),
        .slave_valid  (row_valid),
        .slave_data   (row_data),

        .set_id       (set_YID),
        .ID_scan_in   (YID_scan_in),
        .ID_scan_out  (yid_scan_out_unused)
    );

    // Second level: inside selected row, select local PE column.
    generate
        for (r = 0; r < NUMS_PE_ROW; r = r + 1) begin : GEN_X_BUS
            GIN_Bus #(
                .NUMS_SLAVE (NUMS_PE_COL),
                .ID_SIZE    (XID_BITS),
                .DATA_SIZE  (DATA_SIZE),
                .STATIC_ID_ENABLE(1'b1)
            ) u_x_bus (
                .clk          (clk),
                .rst          (rst),
                .tag          (tag_X),
                .master_valid (row_valid[r]),
                .master_data  (row_data),
                .master_ready (row_ready[r]),

                .slave_ready  (PE_ready[r*NUMS_PE_COL +: NUMS_PE_COL]),
                .slave_valid  (PE_valid [r*NUMS_PE_COL +: NUMS_PE_COL]),
                .slave_data   (),

                .set_id       (set_XID),
                .ID_scan_in   (xid_scan_chain[r]),
                .ID_scan_out  (xid_scan_chain[r+1])
            );
        end
    endgenerate

endmodule

`endif
