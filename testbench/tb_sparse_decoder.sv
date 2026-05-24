`timescale 1ns/1ps

`include "src/Sparse/SparseDecoder.sv"

module tb_sparse_decoder;
    localparam int DATA_SIZE  = 32;
    localparam int BLOCK_SIZE = 4;
    localparam int COUNT_W    = $clog2(BLOCK_SIZE + 1);

    logic clk;
    logic rst;

    logic [BLOCK_SIZE-1:0] bitmap_i;
    logic [COUNT_W-1:0]    nz_count_i;
    logic                  bitmap_valid_i;
    logic                  bitmap_ready_o;
    logic [DATA_SIZE-1:0]  cmp_data_i;
    logic                  cmp_valid_i;
    logic                  cmp_ready_o;
    logic [DATA_SIZE-1:0]  dense_data_o;
    logic                  dense_valid_o;
    logic                  dense_ready_i;

    logic [BLOCK_SIZE-1:0] bitmap_vec [0:1];
    logic [COUNT_W-1:0] nz_vec [0:1];
    logic [DATA_SIZE-1:0] cmp_vec [0:2];
    logic [DATA_SIZE-1:0] expected_dense [0:7];

    SparseDecoder #(
        .DATA_SIZE  (DATA_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .bitmap_i       (bitmap_i),
        .nz_count_i     (nz_count_i),
        .bitmap_valid_i (bitmap_valid_i),
        .bitmap_ready_o (bitmap_ready_o),
        .cmp_data_i     (cmp_data_i),
        .cmp_valid_i    (cmp_valid_i),
        .cmp_ready_o    (cmp_ready_o),
        .dense_data_o   (dense_data_o),
        .dense_valid_o  (dense_valid_o),
        .dense_ready_i  (dense_ready_i)
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
        integer bitmap_idx;
        integer cmp_idx;
        integer dense_idx;
        integer cycles;

`ifdef FSDB
        $fsdbDumpfile("simulation/tb_sparse_decoder.fsdb");
        $fsdbDumpvars(0, tb_sparse_decoder);
`elsif WV_NORMAL
        $dumpfile("testbench/tb_sparse_decoder.vcd");
        $dumpvars(0, tb_sparse_decoder);
`endif

        bitmap_vec[0] = 4'b1010;
        bitmap_vec[1] = 4'b0001;
        nz_vec[0] = 3'd2;
        nz_vec[1] = 3'd1;
        cmp_vec[0] = 32'd5;
        cmp_vec[1] = 32'hffff_fffd;
        cmp_vec[2] = 32'd9;
        expected_dense[0] = 32'd0;
        expected_dense[1] = 32'd5;
        expected_dense[2] = 32'd0;
        expected_dense[3] = 32'hffff_fffd;
        expected_dense[4] = 32'd9;
        expected_dense[5] = 32'd0;
        expected_dense[6] = 32'd0;
        expected_dense[7] = 32'd0;

        rst = 1'b1;
        bitmap_i = '0;
        nz_count_i = '0;
        bitmap_valid_i = 1'b0;
        cmp_data_i = '0;
        cmp_valid_i = 1'b0;
        dense_ready_i = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        bitmap_idx = 0;
        cmp_idx = 0;
        dense_idx = 0;
        cycles = 0;

        fork
            begin : DRIVE_BITMAP
                while (bitmap_idx < 2) begin
                    @(negedge clk);
                    if (bitmap_ready_o) begin
                        bitmap_i = bitmap_vec[bitmap_idx];
                        nz_count_i = nz_vec[bitmap_idx];
                        bitmap_valid_i = 1'b1;
                        bitmap_idx = bitmap_idx + 1;
                    end
                    else begin
                        bitmap_valid_i = 1'b0;
                    end
                end
                @(negedge clk);
                bitmap_valid_i = 1'b0;
                bitmap_i = '0;
                nz_count_i = '0;
            end

            begin : DRIVE_CMP
                while (cmp_idx < 3) begin
                    @(negedge clk);
                    if (cmp_ready_o) begin
                        cmp_data_i = cmp_vec[cmp_idx];
                        cmp_valid_i = 1'b1;
                        cmp_idx = cmp_idx + 1;
                    end
                    else begin
                        cmp_valid_i = 1'b0;
                    end
                end
                @(negedge clk);
                cmp_valid_i = 1'b0;
                cmp_data_i = '0;
            end

            begin : CHECK_DENSE
                while (dense_idx < 8) begin
                    @(posedge clk);
                    if (dense_valid_o && dense_ready_i) begin
                        $display("[DEC_DENSE_COMPARE] index=%0d expected=0x%08h actual=0x%08h %s",
                                 dense_idx, expected_dense[dense_idx], dense_data_o,
                                 (dense_data_o === expected_dense[dense_idx]) ? "PASS" : "FAIL");
                        if (dense_data_o !== expected_dense[dense_idx]) fail("Decoder dense output mismatch");
                        dense_idx = dense_idx + 1;
                    end
                    cycles = cycles + 1;
                    if (cycles > 100) fail("Decoder timeout");
                end
            end
        join

        $display("PASS: SparseDecoder standalone test");
        repeat (3) @(posedge clk);
        $finish;
    end
endmodule
