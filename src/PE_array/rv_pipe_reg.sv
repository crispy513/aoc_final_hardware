`ifndef RV_PIPE_REG_SV
`define RV_PIPE_REG_SV

// One-entry ready/valid pipeline register.
// It breaks the long GLB/cluster-GIN -> PE_cluster/local-GIN ready path.
module rv_pipe_reg #(
    parameter int DATA_SIZE = 32
)(
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 valid_i,
    output logic                 ready_o,
    input  logic [DATA_SIZE-1:0] data_i,

    output logic                 valid_o,
    input  logic                 ready_i,
    output logic [DATA_SIZE-1:0] data_o
);

    logic                 valid_q;
    logic [DATA_SIZE-1:0] data_q;

    assign ready_o = ready_i | ~valid_q;
    assign valid_o = valid_q;
    assign data_o  = data_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_q <= 1'b0;
            data_q  <= '0;
        end
        else if (ready_o) begin
            valid_q <= valid_i;
            data_q  <= data_i;
        end
    end

endmodule

`endif
