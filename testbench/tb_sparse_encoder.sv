`timescale 1ns/1ps

`include "src/Sparse/SparseEncoder.sv"

module tb_sparse_encoder;
    localparam int DATA_SIZE  = 32;
    localparam int BLOCK_SIZE = 4;
    localparam int LEN_W      = 8;
    localparam int COUNT_W    = $clog2(BLOCK_SIZE + 1);

    logic clk;
    logic rst;

    logic                  start_i;
    logic [LEN_W-1:0]      dense_len_i;
    logic                  busy_o;
    logic                  done_o;
    logic [LEN_W-1:0]      dense_count_o;
    logic [LEN_W-1:0]      cmp_count_o;
    logic [LEN_W-1:0]      bitmap_count_o;
    logic [DATA_SIZE-1:0]  dense_data_i;
    logic                  dense_valid_i;
    logic                  dense_ready_o;
    logic [BLOCK_SIZE-1:0] bitmap_o;
    logic [COUNT_W-1:0]    nz_count_o;
    logic                  bitmap_valid_o;
    logic                  bitmap_ready_i;
    logic [DATA_SIZE-1:0]  cmp_data_o;
    logic                  cmp_valid_o;
    logic                  cmp_ready_i;

    logic [DATA_SIZE-1:0] dense_vec [0:5];
    logic [BLOCK_SIZE-1:0] expected_bitmap [0:1];
    logic [COUNT_W-1:0] expected_nz [0:1];
    logic [DATA_SIZE-1:0] expected_cmp [0:2];

    SparseEncoder #(
        .DATA_SIZE  (DATA_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE),
        .LEN_W      (LEN_W)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .start_i        (start_i),
        .dense_len_i    (dense_len_i),
        .busy_o         (busy_o),
        .done_o         (done_o),
        .dense_count_o  (dense_count_o),
        .cmp_count_o    (cmp_count_o),
        .bitmap_count_o (bitmap_count_o),
        .dense_data_i   (dense_data_i),
        .dense_valid_i  (dense_valid_i),
        .dense_ready_o  (dense_ready_o),
        .bitmap_o       (bitmap_o),
        .nz_count_o     (nz_count_o),
        .bitmap_valid_o (bitmap_valid_o),
        .bitmap_ready_i (bitmap_ready_i),
        .cmp_data_o     (cmp_data_o),
        .cmp_valid_o    (cmp_valid_o),
        .cmp_ready_i    (cmp_ready_i)
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
        integer send_idx;
        integer bitmap_idx;
        integer cmp_idx;
        integer cycles;
        bit saw_done;

`ifdef FSDB
        $fsdbDumpfile("simulation/tb_sparse_encoder.fsdb");
        $fsdbDumpvars(0, tb_sparse_encoder);
`elsif WV_NORMAL
        $dumpfile("testbench/tb_sparse_encoder.vcd");
        $dumpvars(0, tb_sparse_encoder);
`endif

        dense_vec[0] = 32'd0;
        dense_vec[1] = 32'd5;
        dense_vec[2] = 32'd0;
        dense_vec[3] = 32'hffff_fffd;
        dense_vec[4] = 32'd9;
        dense_vec[5] = 32'd0;

        expected_bitmap[0] = 4'b1010;
        expected_bitmap[1] = 4'b0001;
        expected_nz[0] = 3'd2;
        expected_nz[1] = 3'd1;
        expected_cmp[0] = 32'd5;
        expected_cmp[1] = 32'hffff_fffd;
        expected_cmp[2] = 32'd9;

        rst = 1'b1;
        start_i = 1'b0;
        dense_len_i = '0;
        dense_data_i = '0;
        dense_valid_i = 1'b0;
        bitmap_ready_i = 1'b1;
        cmp_ready_i = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        @(negedge clk);
        dense_len_i = 6;
        start_i = 1'b1;
        @(negedge clk);
        start_i = 1'b0;

        send_idx = 0;
        bitmap_idx = 0;
        cmp_idx = 0;
        cycles = 0;
        saw_done = 1'b0;

        fork
            begin : DRIVE_DENSE
                while (send_idx < 6) begin
                    @(negedge clk);
                    if (dense_ready_o) begin
                        dense_data_i = dense_vec[send_idx];
                        dense_valid_i = 1'b1;
                        send_idx = send_idx + 1;
                    end
                    else begin
                        dense_valid_i = 1'b0;
                    end
                end
                @(negedge clk);
                dense_valid_i = 1'b0;
                dense_data_i = '0;
            end

            begin : CHECK_OUTPUT
                while (!saw_done) begin
                    @(posedge clk);
                    if (bitmap_valid_o && bitmap_ready_i) begin
                        if (bitmap_idx >= 2) fail("Encoder produced too many bitmap entries");
                        $display("[ENC_BMAP_COMPARE] index=%0d expected_bitmap=0x%01h actual_bitmap=0x%01h expected_nz=%0d actual_nz=%0d %s",
                                 bitmap_idx, expected_bitmap[bitmap_idx], bitmap_o,
                                 expected_nz[bitmap_idx], nz_count_o,
                                 ((bitmap_o === expected_bitmap[bitmap_idx]) && (nz_count_o === expected_nz[bitmap_idx])) ? "PASS" : "FAIL");
                        if (bitmap_o !== expected_bitmap[bitmap_idx]) fail("Encoder bitmap mismatch");
                        if (nz_count_o !== expected_nz[bitmap_idx]) fail("Encoder nz_count mismatch");
                        bitmap_idx = bitmap_idx + 1;
                    end
                    if (cmp_valid_o && cmp_ready_i) begin
                        if (cmp_idx >= 3) fail("Encoder produced too many compressed words");
                        $display("[ENC_CMP_COMPARE] index=%0d expected=0x%08h actual=0x%08h %s",
                                 cmp_idx, expected_cmp[cmp_idx], cmp_data_o,
                                 (cmp_data_o === expected_cmp[cmp_idx]) ? "PASS" : "FAIL");
                        if (cmp_data_o !== expected_cmp[cmp_idx]) fail("Encoder compressed data mismatch");
                        cmp_idx = cmp_idx + 1;
                    end
                    if (done_o) saw_done = 1'b1;
                    cycles = cycles + 1;
                    if (cycles > 100) fail("Encoder timeout");
                end
            end
        join

        if (bitmap_idx != 2) fail("Encoder bitmap count mismatch");
        if (cmp_idx != 3) fail("Encoder compressed count mismatch");
        if (dense_count_o !== 6) fail("Encoder dense_count_o mismatch");
        if (bitmap_count_o !== 2) fail("Encoder bitmap_count_o mismatch");
        if (cmp_count_o !== 3) fail("Encoder cmp_count_o mismatch");
        $display("[ENC_COUNT_COMPARE] dense expected=6 actual=%0d PASS", dense_count_o);
        $display("[ENC_COUNT_COMPARE] bitmap expected=2 actual=%0d PASS", bitmap_count_o);
        $display("[ENC_COUNT_COMPARE] compressed expected=3 actual=%0d PASS", cmp_count_o);

        $display("PASS: SparseEncoder standalone test");
        repeat (3) @(posedge clk);
        $finish;
    end
endmodule
