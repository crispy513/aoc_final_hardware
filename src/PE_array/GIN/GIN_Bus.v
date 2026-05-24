`ifndef GIN_BUS_V
`define GIN_BUS_V

`include "define.svh"
`include "src/PE_array/GIN/GIN_MulticastController.v"

module GIN_Bus #(
    parameter int NUMS_SLAVE       = `NUMS_PE_COL,
    parameter int ID_SIZE          = `XID_BITS,
    parameter int DATA_SIZE        = `DATA_BITS,
    // 1: use physical index as ID, no scan configuration needed.
    // 0: use the original scan-chain ID registers.
    parameter bit STATIC_ID_ENABLE = 1'b0
)(
    input  logic                         clk,
    input  logic                         rst,

    // Master side
    input  logic [ID_SIZE-1:0]           tag,
    input  logic                         master_valid,
    input  logic [DATA_SIZE-1:0]         master_data,
    output logic                         master_ready,

    // Slave side
    input  logic [NUMS_SLAVE-1:0]        slave_ready,
    output logic [NUMS_SLAVE-1:0]        slave_valid,
    output logic [DATA_SIZE-1:0]         slave_data,

    // ID scan-chain config
    input  logic                         set_id,
    input  logic [ID_SIZE-1:0]           ID_scan_in,
    output logic [ID_SIZE-1:0]           ID_scan_out
);

    logic [NUMS_SLAVE-1:0] mc_ready;

    genvar i;

    assign slave_data   = master_data;

    // Broadcast can consume one word only when every selected destination is ready.
    // Non-selected destinations return ready=1, so they do not block.
    assign master_ready = &mc_ready;

    generate
        if (STATIC_ID_ENABLE) begin : GEN_STATIC_ID
            assign ID_scan_out = ID_scan_in;

            for (i = 0; i < NUMS_SLAVE; i = i + 1) begin : GEN_STATIC_MC
                localparam logic [ID_SIZE-1:0] THIS_ID = i;
                logic hit;

                assign hit            = (tag == THIS_ID);
                assign slave_valid[i] = master_valid & hit;
                assign mc_ready[i]    = (~master_valid) | (~hit) | slave_ready[i];
            end
        end
        else begin : GEN_SCAN_ID
            logic [ID_SIZE-1:0] id_chain [0:NUMS_SLAVE];

            assign id_chain[0] = ID_scan_in;
            assign ID_scan_out = id_chain[NUMS_SLAVE];

            for (i = 0; i < NUMS_SLAVE; i = i + 1) begin : GEN_MC
                GIN_MulticastController #(
                    .ID_SIZE(ID_SIZE)
                ) u_mc (
                    .clk       (clk),
                    .rst       (rst),
                    .set_id    (set_id),
                    .id_in     (id_chain[i]),
                    .id        (id_chain[i+1]),
                    .tag       (tag),
                    .valid_in  (master_valid),
                    .valid_out (slave_valid[i]),
                    .ready_in  (slave_ready[i]),
                    .ready_out (mc_ready[i])
                );
            end
        end
    endgenerate

endmodule

`endif
