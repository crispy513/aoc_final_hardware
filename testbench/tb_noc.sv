`timescale 1ns/1ps

`include "define.svh"
`include "src/PE_array/GIN/GIN_Bus.v"
`include "src/PE_array/GON/GON_Bus.v"

module tb_noc;
    localparam int DATA_SIZE = 32;
    localparam int NUMS_NODE = 4;
    localparam int ID_SIZE   = 2;

    logic clk;
    logic rst;

    logic [ID_SIZE-1:0] gin_tag;
    logic gin_master_valid;
    logic [DATA_SIZE-1:0] gin_master_data;
    logic gin_master_ready;
    logic [NUMS_NODE-1:0] gin_slave_ready;
    logic [NUMS_NODE-1:0] gin_slave_valid;
    logic [DATA_SIZE-1:0] gin_slave_data;

    logic [ID_SIZE-1:0] gon_tag;
    logic [NUMS_NODE-1:0] gon_master_valid;
    logic [NUMS_NODE*DATA_SIZE-1:0] gon_master_data;
    logic [NUMS_NODE-1:0] gon_master_ready;
    logic gon_slave_valid;
    logic gon_slave_ready;
    logic [DATA_SIZE-1:0] gon_slave_data;

    GIN_Bus #(
        .NUMS_SLAVE       (NUMS_NODE),
        .ID_SIZE          (ID_SIZE),
        .DATA_SIZE        (DATA_SIZE),
        .STATIC_ID_ENABLE (1'b1)
    ) u_gin_bus (
        .clk          (clk),
        .rst          (rst),
        .tag          (gin_tag),
        .master_valid (gin_master_valid),
        .master_data  (gin_master_data),
        .master_ready (gin_master_ready),
        .slave_ready  (gin_slave_ready),
        .slave_valid  (gin_slave_valid),
        .slave_data   (gin_slave_data),
        .set_id       (1'b0),
        .ID_scan_in   ({ID_SIZE{1'b0}}),
        .ID_scan_out  ()
    );

    GON_Bus #(
        .NUMS_MASTER      (NUMS_NODE),
        .ID_SIZE          (ID_SIZE),
        .DATA_SIZE        (DATA_SIZE),
        .STATIC_ID_ENABLE (1'b1)
    ) u_gon_bus (
        .clk          (clk),
        .rst          (rst),
        .tag          (gon_tag),
        .master_valid (gon_master_valid),
        .master_data  (gon_master_data),
        .master_ready (gon_master_ready),
        .slave_valid  (gon_slave_valid),
        .slave_ready  (gon_slave_ready),
        .slave_data   (gon_slave_data),
        .set_id       (1'b0),
        .ID_scan_in   ({ID_SIZE{1'b0}}),
        .ID_scan_out  ()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic fail(input string msg);
    begin
        $error("%s", msg);
        $fatal(1);
    end
    endtask

    initial begin
`ifdef FSDB
        $fsdbDumpfile("simulation/tb_noc.fsdb");
        $fsdbDumpvars(0, tb_noc);
`elsif WV_NORMAL
        $dumpfile("testbench/tb_noc.vcd");
        $dumpvars(0, tb_noc);
`endif

        rst = 1'b1;
        gin_tag = '0;
        gin_master_valid = 1'b0;
        gin_master_data = '0;
        gin_slave_ready = '1;
        gon_tag = '0;
        gon_master_valid = '0;
        gon_master_data = '0;
        gon_slave_ready = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        #1;

        gin_tag = 2'd2;
        gin_master_valid = 1'b1;
        gin_master_data = 32'h1234_abcd;
        gin_slave_ready = 4'b1111;
        #1;
        $display("[NOC_GIN_COMPARE] tag=%0d expected_valid=0b0100 actual_valid=0b%04b expected_data=0x1234abcd actual_data=0x%08h expected_ready=1 actual_ready=%0b",
                 gin_tag, gin_slave_valid, gin_slave_data, gin_master_ready);
        if (gin_slave_valid !== 4'b0100) fail("GIN tag routing mismatch");
        if (gin_master_ready !== 1'b1) fail("GIN ready should be high when selected sink is ready");
        if (gin_slave_data !== 32'h1234_abcd) fail("GIN data mismatch");

        gin_slave_ready = 4'b1011;
        #1;
        $display("[NOC_GIN_STALL_COMPARE] tag=%0d expected_ready=0 actual_ready=%0b",
                 gin_tag, gin_master_ready);
        if (gin_master_ready !== 1'b0) fail("GIN ready should be low when selected sink is not ready");

        gon_tag = 2'd1;
        gon_master_valid = 4'b1111;
        gon_master_data[0*DATA_SIZE +: DATA_SIZE] = 32'h0000_00a0;
        gon_master_data[1*DATA_SIZE +: DATA_SIZE] = 32'h0000_00b1;
        gon_master_data[2*DATA_SIZE +: DATA_SIZE] = 32'h0000_00c2;
        gon_master_data[3*DATA_SIZE +: DATA_SIZE] = 32'h0000_00d3;
        gon_slave_ready = 1'b1;
        #1;
        $display("[NOC_GON_COMPARE] tag=%0d expected_valid=1 actual_valid=%0b expected_data=0x000000b1 actual_data=0x%08h expected_ready=0b0010 actual_ready=0b%04b",
                 gon_tag, gon_slave_valid, gon_slave_data, gon_master_ready);
        if (gon_slave_valid !== 1'b1) fail("GON selected source should be valid");
        if (gon_slave_data !== 32'h0000_00b1) fail("GON selected data mismatch");
        if (gon_master_ready !== 4'b0010) fail("GON ready should only consume selected source");

        gon_slave_ready = 1'b0;
        #1;
        $display("[NOC_GON_STALL_COMPARE] tag=%0d expected_valid=1 actual_valid=%0b expected_ready=0b0000 actual_ready=0b%04b",
                 gon_tag, gon_slave_valid, gon_master_ready);
        if (gon_slave_valid !== 1'b1) fail("GON valid should remain high when downstream stalls");
        if (gon_master_ready !== 4'b0000) fail("GON should not consume data when downstream is not ready");

        $display("PASS: NoC GIN/GON standalone test");
        repeat (3) @(posedge clk);
        $finish;
    end
endmodule
