`ifndef GON_BUS_V
`define GON_BUS_V

`include "define.svh"
`include "src/PE_array/GON/GON_MulticastController.v"

// GON_Bus is a tagged gather bus.
// It collects one selected source from NUMS_MASTER masters and forwards it to one slave.
// Difference from GIN_Bus:
//   - GIN: non-hit destinations return ready=1 because they are not consuming data.
//   - GON: non-hit sources must return ready=0 because their valid data must not be consumed.
module GON_Bus #(
    parameter int NUMS_MASTER     = `NUMS_PE_COL,
    parameter int ID_SIZE         = `XID_BITS,
    parameter int DATA_SIZE       = `DATA_BITS,
    // 1: use physical index as ID, no scan configuration needed.
    // 0: use original scan-chain ID registers.
    parameter bit STATIC_ID_ENABLE = 1'b0
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic [ID_SIZE-1:0]           tag,

    // Master/source side: PE or PE_cluster outputs
    input  logic [NUMS_MASTER-1:0]       master_valid,
    input  logic [NUMS_MASTER*DATA_SIZE-1:0] master_data,
    output logic [NUMS_MASTER-1:0]       master_ready,

    // Slave/downstream side: upper GON level or GLB
    output logic                         slave_valid,
    input  logic                         slave_ready,
    output logic [DATA_SIZE-1:0]         slave_data,

    // ID scan-chain config
    input  logic                         set_id,
    input  logic [ID_SIZE-1:0]           ID_scan_in,
    output logic [ID_SIZE-1:0]           ID_scan_out
);

    logic [NUMS_MASTER-1:0] source_hit;
    logic [NUMS_MASTER-1:0] candidate_valid;
    logic [NUMS_MASTER-1:0] selected;

    integer k;
    genvar i;

    // Fixed-priority arbitration among matched sources.
    // Usually only one source has the requested ID, but the arbiter prevents
    // multiple drivers if scan-chain IDs were accidentally duplicated.
    always_comb begin
        slave_valid  = 1'b0;
        slave_data   = '0;
        selected     = '0;
        master_ready = '0;

        for (k = 0; k < NUMS_MASTER; k = k + 1) begin
            if ((slave_valid == 1'b0) && candidate_valid[k]) begin
                slave_valid = 1'b1;
                slave_data  = master_data[k*DATA_SIZE +: DATA_SIZE];
                selected[k] = 1'b1;
            end
        end

        for (k = 0; k < NUMS_MASTER; k = k + 1) begin
            // Only the selected source is consumed when downstream is ready.
            master_ready[k] = selected[k] & slave_ready;
        end
    end

    generate
        if (STATIC_ID_ENABLE) begin : GEN_STATIC_ID
            assign ID_scan_out = ID_scan_in;

            for (i = 0; i < NUMS_MASTER; i = i + 1) begin : GEN_STATIC_HIT
                localparam logic [ID_SIZE-1:0] THIS_ID = i;
                assign source_hit[i]      = (tag == THIS_ID);
                assign candidate_valid[i] = master_valid[i] & source_hit[i];
            end
        end
        else begin : GEN_SCAN_ID
            logic [ID_SIZE-1:0] id_chain [0:NUMS_MASTER];

            assign id_chain[0] = ID_scan_in;
            assign ID_scan_out = id_chain[NUMS_MASTER];

            for (i = 0; i < NUMS_MASTER; i = i + 1) begin : GEN_MC
                GON_MulticastController #(
                    .ID_SIZE(ID_SIZE)
                ) u_mc (
                    .clk       (clk),
                    .rst       (rst),
                    .set_id    (set_id),
                    .id_in     (id_chain[i]),
                    .id        (id_chain[i+1]),
                    .tag       (tag),
                    .valid_in  (master_valid[i]),
                    .valid_out (candidate_valid[i]),
                    .ready_in  (master_ready[i]),
                    .ready_out (),
                    .hit_out   (source_hit[i])
                );
            end
        end
    endgenerate

endmodule

`endif
