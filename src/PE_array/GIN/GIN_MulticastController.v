`ifndef GIN_MULTICAST_CONTROLLER_V
`define GIN_MULTICAST_CONTROLLER_V

`include "define.svh"

module GIN_MulticastController #(
    parameter int ID_SIZE = `XID_BITS
)(
    input  logic                 clk,
    input  logic                 rst,

    // ID scan-chain config
    input  logic                 set_id,
    input  logic [ID_SIZE-1:0]   id_in,
    output logic [ID_SIZE-1:0]   id,

    // multicast tag
    input  logic [ID_SIZE-1:0]   tag,

    // ready/valid
    input  logic                 valid_in,
    output logic                 valid_out,
    input  logic                 ready_in,
    output logic                 ready_out
);

    localparam logic [ID_SIZE-1:0] DEFAULT_ID = {ID_SIZE{1'b1}};

    logic hit;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            id <= DEFAULT_ID;
        end
        else if (set_id) begin
            id <= id_in;
        end
    end

    assign hit       = (tag == id);
    assign valid_out = valid_in & hit;

    // If this node is not selected, it must not block the broadcast bus.
    // If selected, back-pressure follows the destination PE/cluster ready.
    assign ready_out = (~valid_in) | (~hit) | ready_in;

endmodule

`endif
