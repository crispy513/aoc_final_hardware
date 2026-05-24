`ifndef GON_LOCAL_V
`define GON_LOCAL_V

`include "define.svh"
`include "src/PE_array/GON/GON_Bus.v"

// Two-level local GON inside one PE_cluster:
//   PE outputs -> X bus selects local column -> Y bus selects local row -> one cluster output
module GON_local #(
    parameter int NUMS_PE_ROW = 2,
    parameter int NUMS_PE_COL = 2,
    parameter int DATA_SIZE   = `DATA_BITS,
    parameter int XID_BITS    = 1,
    parameter int YID_BITS    = 1
)(
    input  logic                              clk,
    input  logic                              rst,

    // local source tag: which PE inside this cluster should send opsum
    input  logic [XID_BITS-1:0]               tag_X,
    input  logic [YID_BITS-1:0]               tag_Y,

    // local ID scan-chain config
    input  logic                              set_XID,
    input  logic [XID_BITS-1:0]               XID_scan_in,
    input  logic                              set_YID,
    input  logic [YID_BITS-1:0]               YID_scan_in,

    // PE side
    input  logic [NUMS_PE_ROW*NUMS_PE_COL-1:0]       PE_valid,
    output logic [NUMS_PE_ROW*NUMS_PE_COL-1:0]       PE_ready,
    input  logic [DATA_SIZE*NUMS_PE_ROW*NUMS_PE_COL-1:0] PE_data,

    // cluster-output side
    output logic                              GON_valid,
    input  logic                              GON_ready,
    output logic [DATA_SIZE-1:0]              GON_data
);

    logic [NUMS_PE_ROW-1:0]          row_valid;
    logic [NUMS_PE_ROW-1:0]          row_ready;
    logic [DATA_SIZE*NUMS_PE_ROW-1:0] row_data;

    logic [YID_BITS-1:0] yid_scan_out_unused;
    logic [XID_BITS-1:0] xid_scan_chain [0:NUMS_PE_ROW];

    genvar r;

    assign xid_scan_chain[0] = XID_scan_in;

    // First level: each local row selects one PE column.
    generate
        for (r = 0; r < NUMS_PE_ROW; r = r + 1) begin : GEN_LOCAL_X_BUS
            GON_Bus #(
                .NUMS_MASTER      (NUMS_PE_COL),
                .ID_SIZE          (XID_BITS),
                .DATA_SIZE        (DATA_SIZE),
                .STATIC_ID_ENABLE (1'b1)
            ) u_x_bus (
                .clk          (clk),
                .rst          (rst),
                .tag          (tag_X),

                .master_valid (PE_valid[r*NUMS_PE_COL +: NUMS_PE_COL]),
                .master_data  (PE_data[r*(NUMS_PE_COL*DATA_SIZE) +: (NUMS_PE_COL*DATA_SIZE)]),
                .master_ready (PE_ready[r*NUMS_PE_COL +: NUMS_PE_COL]),

                .slave_valid  (row_valid[r]),
                .slave_ready  (row_ready[r]),
                .slave_data   (row_data[r*DATA_SIZE +: DATA_SIZE]),

                .set_id       (set_XID),
                .ID_scan_in   (xid_scan_chain[r]),
                .ID_scan_out  (xid_scan_chain[r+1])
            );
        end
    endgenerate

    // Second level: select the local row.
    GON_Bus #(
        .NUMS_MASTER      (NUMS_PE_ROW),
        .ID_SIZE          (YID_BITS),
        .DATA_SIZE        (DATA_SIZE),
        .STATIC_ID_ENABLE (1'b1)
    ) u_y_bus (
        .clk          (clk),
        .rst          (rst),
        .tag          (tag_Y),

        .master_valid (row_valid),
        .master_data  (row_data),
        .master_ready (row_ready),

        .slave_valid  (GON_valid),
        .slave_ready  (GON_ready),
        .slave_data   (GON_data),

        .set_id       (set_YID),
        .ID_scan_in   (YID_scan_in),
        .ID_scan_out  (yid_scan_out_unused)
    );

endmodule

`endif
