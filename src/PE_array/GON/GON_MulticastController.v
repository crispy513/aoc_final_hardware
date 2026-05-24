`ifndef GON_MULTICAST_CONTROLLER_V
`define GON_MULTICAST_CONTROLLER_V

`include "define.svh"

module GON_MulticastController #(
    parameter int ID_SIZE = `XID_BITS
)(
    input  logic               clk,
    input  logic               rst,

    // ID scan-chain config
    input  logic               set_id,
    input  logic [ID_SIZE-1:0] id_in,
    output logic [ID_SIZE-1:0] id,

    // source-selection tag
    input  logic [ID_SIZE-1:0] tag,

    // source ready/valid
    input  logic               valid_in,
    output logic               valid_out,
    input  logic               ready_in,
    output logic               ready_out,
    output logic               hit_out
);

    localparam logic [ID_SIZE-1:0] DEFAULT_ID = {ID_SIZE{1'b1}};

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            id <= DEFAULT_ID;
        end
        else if (set_id) begin
            id <= id_in;
        end
    end

    assign hit_out   = (tag == id);
    assign valid_out = valid_in & hit_out;

    // For a gather network, non-selected sources must NOT be consumed.
    assign ready_out = ready_in & hit_out;

endmodule

`endif
