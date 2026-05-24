`timescale 1ns/1ps

`include "define.svh"
`include "src/top_with_controller.sv"

module tb_top_with_controller;
    localparam int CLK_PERIOD = 10;

    localparam logic [1:0] SEL_IFMAP  = 2'd0;
    localparam logic [1:0] SEL_FILTER = 2'd1;
    localparam logic [1:0] SEL_IPSUM  = 2'd2;
    localparam logic [1:0] SEL_OPSUM  = 2'd3;

    localparam int NUMS_PE_ROW = `NUMS_PE_ROW;
    localparam int NUMS_PE_COL = `NUMS_PE_COL;
    localparam int XID_BITS    = `XID_BITS;
    localparam int YID_BITS    = `YID_BITS;
    localparam int DATA_SIZE   = `DATA_BITS;
    localparam int CONFIG_SIZE = `CONFIG_SIZE;

    localparam int IFMAP_DEPTH  = 256;
    localparam int FILTER_DEPTH = 256;
    localparam int IPSUM_DEPTH  = 256;
    localparam int OPSUM_DEPTH  = 256;
    localparam int IFMAP_AW     = (IFMAP_DEPTH  <= 1) ? 1 : $clog2(IFMAP_DEPTH);
    localparam int FILTER_AW    = (FILTER_DEPTH <= 1) ? 1 : $clog2(FILTER_DEPTH);
    localparam int IPSUM_AW     = (IPSUM_DEPTH  <= 1) ? 1 : $clog2(IPSUM_DEPTH);
    localparam int OPSUM_AW     = (OPSUM_DEPTH  <= 1) ? 1 : $clog2(OPSUM_DEPTH);
    localparam int ADDR_W       = 8;

    localparam int SPARSE_BLOCK_SIZE = 8;
    localparam int SPARSE_COUNT_W    = $clog2(SPARSE_BLOCK_SIZE + 1);
    localparam int BMAP_ADDR_W       = 5;

    localparam logic [CONFIG_SIZE-1:0] PE_CONFIG_CONV_P1_F1_Q1 = 10'b0_00_00000_00;
    localparam int CONV_KERNEL_LEN = 3;
    localparam int MAX_P = 4;
    localparam int MAX_F = 32;
    localparam int MAX_Q = 4;
    localparam int IFMAP_DENSE_MAX = MAX_F + CONV_KERNEL_LEN - 1;
    localparam int FILTER_DENSE_MAX = MAX_P * CONV_KERNEL_LEN;
    localparam int IPSUM_DENSE_MAX = MAX_F * MAX_P;
    localparam int OPSUM_DENSE_MAX = MAX_F * MAX_P;
    localparam int IFMAP_BMAP_MAX = (IFMAP_DENSE_MAX + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;
    localparam int FILTER_BMAP_MAX = (FILTER_DENSE_MAX + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;
    localparam int IPSUM_BMAP_MAX = (IPSUM_DENSE_MAX + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;
    localparam int OPSUM_BMAP_MAX = (OPSUM_DENSE_MAX + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;

    logic clk;
    logic rst;

    logic                 wr_en;
    logic [1:0]           wr_sel;
    logic [ADDR_W-1:0]    wr_addr;
    logic [DATA_SIZE-1:0] wr_data;
    logic                 rd_en;
    logic [1:0]           rd_sel;
    logic [ADDR_W-1:0]    rd_addr;
    logic [DATA_SIZE-1:0] rd_data;

    logic                         bitmap_wr_en;
    logic [1:0]                   bitmap_wr_sel;
    logic [BMAP_ADDR_W-1:0]       bitmap_wr_addr;
    logic [SPARSE_BLOCK_SIZE-1:0] bitmap_wr_data;
    logic [SPARSE_COUNT_W-1:0]    bitmap_wr_nz_count;
    logic                         bitmap_rd_en;
    logic [1:0]                   bitmap_rd_sel;
    logic [BMAP_ADDR_W-1:0]       bitmap_rd_addr;
    logic [SPARSE_BLOCK_SIZE-1:0] bitmap_rd_data;
    logic [SPARSE_COUNT_W-1:0]    bitmap_rd_nz_count;

    logic                start_ifmap;
    logic [IFMAP_AW-1:0] ifmap_base;
    logic [IFMAP_AW:0]   ifmap_len;
    logic                ifmap_busy;
    logic                ifmap_done;

    logic                 start_filter;
    logic [FILTER_AW-1:0] filter_base;
    logic [FILTER_AW:0]   filter_len;
    logic                 filter_busy;
    logic                 filter_done;

    logic                start_ipsum;
    logic [IPSUM_AW-1:0] ipsum_base;
    logic [IPSUM_AW:0]   ipsum_len;
    logic                ipsum_busy;
    logic                ipsum_done;

    logic                         start_ifmap_bitmap;
    logic [BMAP_ADDR_W-1:0]       ifmap_bitmap_base;
    logic [BMAP_ADDR_W:0]         ifmap_bitmap_len;
    logic                         ifmap_bitmap_busy;
    logic                         ifmap_bitmap_done;
    logic                         start_filter_bitmap;
    logic [BMAP_ADDR_W-1:0]       filter_bitmap_base;
    logic [BMAP_ADDR_W:0]         filter_bitmap_len;
    logic                         filter_bitmap_busy;
    logic                         filter_bitmap_done;
    logic                         start_ipsum_bitmap;
    logic [BMAP_ADDR_W-1:0]       ipsum_bitmap_base;
    logic [BMAP_ADDR_W:0]         ipsum_bitmap_len;
    logic                         ipsum_bitmap_busy;
    logic                         ipsum_bitmap_done;

    logic                start_encode_opsum;
    logic [OPSUM_AW:0]   opsum_dense_len;
    logic                opsum_encode_busy;
    logic                opsum_encode_done;
    logic [OPSUM_AW:0]   opsum_encoded_dense_count;
    logic [OPSUM_AW:0]   opsum_encoded_cmp_count;
    logic [OPSUM_AW:0]   opsum_encoded_bitmap_count;
    logic                start_capture_opsum;
    logic [OPSUM_AW-1:0] opsum_base;
    logic [OPSUM_AW:0]   opsum_len;
    logic [OPSUM_AW:0]   opsum_captured_count;
    logic                opsum_busy;
    logic                opsum_done;
    logic                         start_capture_opsum_bitmap;
    logic [BMAP_ADDR_W-1:0]       opsum_bitmap_base;
    logic [BMAP_ADDR_W:0]         opsum_bitmap_len;
    logic                         opsum_bitmap_busy;
    logic                         opsum_bitmap_done;

    logic set_XID;
    logic [XID_BITS-1:0] ifmap_XID_scan_in;
    logic [XID_BITS-1:0] filter_XID_scan_in;
    logic [XID_BITS-1:0] ipsum_XID_scan_in;
    logic [XID_BITS-1:0] opsum_XID_scan_in;
    logic set_YID;
    logic [YID_BITS-1:0] ifmap_YID_scan_in;
    logic [YID_BITS-1:0] filter_YID_scan_in;
    logic [YID_BITS-1:0] ipsum_YID_scan_in;
    logic [YID_BITS-1:0] opsum_YID_scan_in;
    logic set_LN;
    logic [NUMS_PE_ROW-2:0] LN_config_in;
    logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] PE_en;
    logic [CONFIG_SIZE-1:0] PE_config;
    logic [XID_BITS-1:0] ifmap_tag_X;
    logic [YID_BITS-1:0] ifmap_tag_Y;
    logic [XID_BITS-1:0] filter_tag_X;
    logic [YID_BITS-1:0] filter_tag_Y;
    logic [XID_BITS-1:0] ipsum_tag_X;
    logic [YID_BITS-1:0] ipsum_tag_Y;
    logic [XID_BITS-1:0] opsum_tag_X;
    logic [YID_BITS-1:0] opsum_tag_Y;

    logic sw_start;
    logic controller_busy;
    logic controller_done;
    logic controller_error;
    logic [2:0] p_i;
    logic [5:0] f_i;
    logic [2:0] q_i;
    logic conv_mode_i;
    logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] active_pe_mask_i;
    logic [XID_BITS-1:0] ifmap_tag_X_i;
    logic [YID_BITS-1:0] ifmap_tag_Y_i;
    logic [XID_BITS-1:0] filter_tag_X_i;
    logic [YID_BITS-1:0] filter_tag_Y_i;
    logic [XID_BITS-1:0] ipsum_tag_X_i;
    logic [YID_BITS-1:0] ipsum_tag_Y_i;
    logic [XID_BITS-1:0] opsum_tag_X_i;
    logic [YID_BITS-1:0] opsum_tag_Y_i;
    logic [IFMAP_AW-1:0] ifmap_base_i;
    logic [IFMAP_AW:0] ifmap_len_i;
    logic [FILTER_AW-1:0] filter_base_i;
    logic [FILTER_AW:0] filter_len_i;
    logic [IPSUM_AW-1:0] ipsum_base_i;
    logic [IPSUM_AW:0] ipsum_len_i;
    logic [BMAP_ADDR_W-1:0] ifmap_bitmap_base_i;
    logic [BMAP_ADDR_W:0] ifmap_bitmap_len_i;
    logic [BMAP_ADDR_W-1:0] filter_bitmap_base_i;
    logic [BMAP_ADDR_W:0] filter_bitmap_len_i;
    logic [BMAP_ADDR_W-1:0] ipsum_bitmap_base_i;
    logic [BMAP_ADDR_W:0] ipsum_bitmap_len_i;
    logic [OPSUM_AW:0] opsum_dense_len_i;
    logic [OPSUM_AW-1:0] opsum_base_i;
    logic [BMAP_ADDR_W-1:0] opsum_bitmap_base_i;

    logic                 GLB_ifmap_valid_dbg;
    logic                 GLB_ifmap_ready_dbg;
    logic [DATA_SIZE-1:0] GLB_ifmap_data_dbg;
    logic                 PE_ifmap_valid_dbg;
    logic                 PE_ifmap_ready_dbg;
    logic [DATA_SIZE-1:0] PE_ifmap_data_dbg;
    logic                 GLB_filter_valid_dbg;
    logic                 GLB_filter_ready_dbg;
    logic [DATA_SIZE-1:0] GLB_filter_data_dbg;
    logic                 PE_filter_valid_dbg;
    logic                 PE_filter_ready_dbg;
    logic [DATA_SIZE-1:0] PE_filter_data_dbg;
    logic                 GLB_ipsum_valid_dbg;
    logic                 GLB_ipsum_ready_dbg;
    logic [DATA_SIZE-1:0] GLB_ipsum_data_dbg;
    logic                 PE_ipsum_valid_dbg;
    logic                 PE_ipsum_ready_dbg;
    logic [DATA_SIZE-1:0] PE_ipsum_data_dbg;
    logic                 PE_opsum_valid_dbg;
    logic                 PE_opsum_ready_dbg;
    logic [DATA_SIZE-1:0] PE_opsum_data_dbg;
    logic                 GLB_opsum_valid_dbg;
    logic                 GLB_opsum_ready_dbg;
    logic [DATA_SIZE-1:0] GLB_opsum_data_dbg;

    logic [DATA_SIZE-1:0] dense_ifmap  [0:IFMAP_DENSE_MAX-1];
    logic [DATA_SIZE-1:0] dense_filter [0:FILTER_DENSE_MAX-1];
    logic [DATA_SIZE-1:0] dense_ipsum  [0:IPSUM_DENSE_MAX-1];
    logic [DATA_SIZE-1:0] golden_opsum_mem [0:OPSUM_DENSE_MAX-1];

    logic [SPARSE_BLOCK_SIZE-1:0] ifmap_bitmap_expected  [0:IFMAP_BMAP_MAX-1];
    logic [SPARSE_BLOCK_SIZE-1:0] filter_bitmap_expected [0:FILTER_BMAP_MAX-1];
    logic [SPARSE_BLOCK_SIZE-1:0] ipsum_bitmap_expected  [0:IPSUM_BMAP_MAX-1];
    logic [SPARSE_BLOCK_SIZE-1:0] opsum_bitmap_expected  [0:OPSUM_BMAP_MAX-1];

    logic [SPARSE_COUNT_W-1:0] ifmap_nz_expected  [0:IFMAP_BMAP_MAX-1];
    logic [SPARSE_COUNT_W-1:0] filter_nz_expected [0:FILTER_BMAP_MAX-1];
    logic [SPARSE_COUNT_W-1:0] ipsum_nz_expected  [0:IPSUM_BMAP_MAX-1];
    logic [SPARSE_COUNT_W-1:0] opsum_nz_expected  [0:OPSUM_BMAP_MAX-1];

    logic [IFMAP_AW:0]  ifmap_cmp_len_expected;
    logic [FILTER_AW:0] filter_cmp_len_expected;
    logic [IPSUM_AW:0]  ipsum_cmp_len_expected;
    logic [OPSUM_AW:0]  opsum_cmp_len_expected;
    int p_from_file;
    int f_from_file;
    int q_from_file;
    int ifmap_dense_len;
    int filter_dense_len;
    int ipsum_dense_len;
    int golden_dense_len;
    int ifmap_bmap_len_expected;
    int filter_bmap_len_expected;
    int ipsum_bmap_len_expected;
    int opsum_bmap_len_expected;
    string input_file_path;
    string golden_file_path;

    top_with_controller #(
        .NUMS_PE_ROW       (NUMS_PE_ROW),
        .NUMS_PE_COL       (NUMS_PE_COL),
        .XID_BITS          (XID_BITS),
        .YID_BITS          (YID_BITS),
        .DATA_SIZE         (DATA_SIZE),
        .CONFIG_SIZE       (CONFIG_SIZE),
        .IFMAP_DEPTH       (IFMAP_DEPTH),
        .FILTER_DEPTH      (FILTER_DEPTH),
        .IPSUM_DEPTH       (IPSUM_DEPTH),
        .OPSUM_DEPTH       (OPSUM_DEPTH),
        .SPARSE_BLOCK_SIZE (SPARSE_BLOCK_SIZE)
    ) dut (.*);

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    function automatic logic [CONFIG_SIZE-1:0] make_conv_config(
        input int p,
        input int f,
        input int q
    );
        logic [1:0] p_m1;
        logic [4:0] f_m1;
        logic [1:0] q_m1;
    begin
        p_m1 = p - 1;
        f_m1 = f - 1;
        q_m1 = q - 1;
        make_conv_config = {1'b0, p_m1, f_m1, q_m1};
    end
    endfunction

    task automatic clear_vectors;
        integer i;
    begin
        for (i = 0; i < IFMAP_DENSE_MAX; i = i + 1) begin
            dense_ifmap[i] = '0;
        end
        for (i = 0; i < FILTER_DENSE_MAX; i = i + 1) begin
            dense_filter[i] = '0;
        end
        for (i = 0; i < IPSUM_DENSE_MAX; i = i + 1) begin
            dense_ipsum[i] = '0;
        end
        for (i = 0; i < OPSUM_DENSE_MAX; i = i + 1) begin
            golden_opsum_mem[i] = '0;
        end
    end
    endtask

    task automatic read_input_file;
        integer fd;
        integer code;
        integer i;
    begin
        clear_vectors();
        fd = $fopen(input_file_path, "r");
        if (fd == 0) begin
            $error("Cannot open %s", input_file_path);
            $fatal(1);
        end

        code = $fscanf(fd, "%d %d %d\n", p_from_file, f_from_file, q_from_file);
        if ((code != 3) ||
            (p_from_file < 1) || (p_from_file > MAX_P) ||
            (f_from_file < 1) || (f_from_file > MAX_F) ||
            (q_from_file < 1) || (q_from_file > MAX_Q)) begin
            $error("Invalid config in %s: p=%0d f=%0d q=%0d",
                   input_file_path, p_from_file, f_from_file, q_from_file);
            $fatal(1);
        end

        code = $fscanf(fd, "%d\n", ifmap_dense_len);
        if ((code != 1) || (ifmap_dense_len > IFMAP_DENSE_MAX)) begin
            $error("Invalid ifmap length: %0d", ifmap_dense_len);
            $fatal(1);
        end
        for (i = 0; i < ifmap_dense_len; i = i + 1) begin
            code = $fscanf(fd, "%h\n", dense_ifmap[i]);
            if (code != 1) begin
                $error("Failed to read ifmap[%0d]", i);
                $fatal(1);
            end
        end

        code = $fscanf(fd, "%d\n", filter_dense_len);
        if ((code != 1) || (filter_dense_len > FILTER_DENSE_MAX)) begin
            $error("Invalid filter length: %0d", filter_dense_len);
            $fatal(1);
        end
        for (i = 0; i < filter_dense_len; i = i + 1) begin
            code = $fscanf(fd, "%h\n", dense_filter[i]);
            if (code != 1) begin
                $error("Failed to read filter[%0d]", i);
                $fatal(1);
            end
        end

        code = $fscanf(fd, "%d\n", ipsum_dense_len);
        if ((code != 1) || (ipsum_dense_len > IPSUM_DENSE_MAX)) begin
            $error("Invalid ipsum length: %0d", ipsum_dense_len);
            $fatal(1);
        end
        for (i = 0; i < ipsum_dense_len; i = i + 1) begin
            code = $fscanf(fd, "%h\n", dense_ipsum[i]);
            if (code != 1) begin
                $error("Failed to read ipsum[%0d]", i);
                $fatal(1);
            end
        end

        $fclose(fd);

        if ((ifmap_dense_len != (f_from_file + CONV_KERNEL_LEN - 1)) ||
            (filter_dense_len != (p_from_file * CONV_KERNEL_LEN)) ||
            (ipsum_dense_len != (f_from_file * p_from_file))) begin
            $error("Input lengths do not match config. ifmap=%0d filter=%0d ipsum=%0d p=%0d f=%0d q=%0d",
                   ifmap_dense_len, filter_dense_len, ipsum_dense_len,
                   p_from_file, f_from_file, q_from_file);
            $fatal(1);
        end
    end
    endtask

    task automatic read_golden_file;
        integer fd;
        integer code;
        integer i;
    begin
        fd = $fopen(golden_file_path, "r");
        if (fd == 0) begin
            $error("Cannot open %s", golden_file_path);
            $fatal(1);
        end

        code = $fscanf(fd, "%d\n", golden_dense_len);
        if ((code != 1) || (golden_dense_len > OPSUM_DENSE_MAX)) begin
            $error("Invalid golden length: %0d", golden_dense_len);
            $fatal(1);
        end
        for (i = 0; i < golden_dense_len; i = i + 1) begin
            code = $fscanf(fd, "%h\n", golden_opsum_mem[i]);
            if (code != 1) begin
                $error("Failed to read golden[%0d]", i);
                $fatal(1);
            end
        end
        $fclose(fd);

        if (golden_dense_len != (f_from_file * p_from_file)) begin
            $error("Golden length %0d does not match f*p=%0d",
                   golden_dense_len, f_from_file * p_from_file);
            $fatal(1);
        end
    end
    endtask

    task automatic set_defaults;
    begin
        wr_en = 1'b0;
        wr_sel = '0;
        wr_addr = '0;
        wr_data = '0;
        rd_en = 1'b0;
        rd_sel = '0;
        rd_addr = '0;
        bitmap_wr_en = 1'b0;
        bitmap_wr_sel = '0;
        bitmap_wr_addr = '0;
        bitmap_wr_data = '0;
        bitmap_wr_nz_count = '0;
        bitmap_rd_en = 1'b0;
        bitmap_rd_sel = '0;
        bitmap_rd_addr = '0;
        start_ifmap = 1'b0;
        ifmap_base = '0;
        ifmap_len = '0;
        start_filter = 1'b0;
        filter_base = '0;
        filter_len = '0;
        start_ipsum = 1'b0;
        ipsum_base = '0;
        ipsum_len = '0;
        start_ifmap_bitmap = 1'b0;
        ifmap_bitmap_base = '0;
        ifmap_bitmap_len = '0;
        start_filter_bitmap = 1'b0;
        filter_bitmap_base = '0;
        filter_bitmap_len = '0;
        start_ipsum_bitmap = 1'b0;
        ipsum_bitmap_base = '0;
        ipsum_bitmap_len = '0;
        start_encode_opsum = 1'b0;
        opsum_dense_len = '0;
        start_capture_opsum = 1'b0;
        opsum_base = '0;
        opsum_len = '0;
        start_capture_opsum_bitmap = 1'b0;
        opsum_bitmap_base = '0;
        opsum_bitmap_len = '0;
        set_XID = 1'b0;
        ifmap_XID_scan_in = '0;
        filter_XID_scan_in = '0;
        ipsum_XID_scan_in = '0;
        opsum_XID_scan_in = '0;
        set_YID = 1'b0;
        ifmap_YID_scan_in = '0;
        filter_YID_scan_in = '0;
        ipsum_YID_scan_in = '0;
        opsum_YID_scan_in = '0;
        set_LN = 1'b0;
        LN_config_in = '0;
        PE_en = '0;
        PE_config = PE_CONFIG_CONV_P1_F1_Q1;
        ifmap_tag_X = '0;
        ifmap_tag_Y = '0;
        filter_tag_X = '0;
        filter_tag_Y = '0;
        ipsum_tag_X = '0;
        ipsum_tag_Y = '0;
        opsum_tag_X = '0;
        opsum_tag_Y = '0;
        sw_start = 1'b0;
        p_i = '0;
        f_i = '0;
        q_i = '0;
        conv_mode_i = 1'b0;
        active_pe_mask_i = '0;
        ifmap_tag_X_i = '0;
        ifmap_tag_Y_i = '0;
        filter_tag_X_i = '0;
        filter_tag_Y_i = '0;
        ipsum_tag_X_i = '0;
        ipsum_tag_Y_i = '0;
        opsum_tag_X_i = '0;
        opsum_tag_Y_i = '0;
        ifmap_base_i = '0;
        ifmap_len_i = '0;
        filter_base_i = '0;
        filter_len_i = '0;
        ipsum_base_i = '0;
        ipsum_len_i = '0;
        ifmap_bitmap_base_i = '0;
        ifmap_bitmap_len_i = '0;
        filter_bitmap_base_i = '0;
        filter_bitmap_len_i = '0;
        ipsum_bitmap_base_i = '0;
        ipsum_bitmap_len_i = '0;
        opsum_dense_len_i = '0;
        opsum_base_i = '0;
        opsum_bitmap_base_i = '0;
    end
    endtask

    task automatic glb_write(
        input logic [1:0] sel,
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_SIZE-1:0] data
    );
    begin
        @(negedge clk);
        wr_en = 1'b1;
        wr_sel = sel;
        wr_addr = addr;
        wr_data = data;
        @(negedge clk);
        wr_en = 1'b0;
        wr_sel = '0;
        wr_addr = '0;
        wr_data = '0;
    end
    endtask

    task automatic bitmap_write(
        input logic [1:0] sel,
        input logic [BMAP_ADDR_W-1:0] addr,
        input logic [SPARSE_BLOCK_SIZE-1:0] bitmap,
        input logic [SPARSE_COUNT_W-1:0] nz_count
    );
    begin
        @(negedge clk);
        bitmap_wr_en = 1'b1;
        bitmap_wr_sel = sel;
        bitmap_wr_addr = addr;
        bitmap_wr_data = bitmap;
        bitmap_wr_nz_count = nz_count;
        @(negedge clk);
        bitmap_wr_en = 1'b0;
        bitmap_wr_sel = '0;
        bitmap_wr_addr = '0;
        bitmap_wr_data = '0;
        bitmap_wr_nz_count = '0;
    end
    endtask

    task automatic load_ifmap_vector;
        integer i;
        integer block;
        integer local_idx;
        integer cmp_addr;
        integer nz_count;
        logic [SPARSE_BLOCK_SIZE-1:0] bitmap;
    begin
        cmp_addr = 0;
        ifmap_bmap_len_expected = (ifmap_dense_len + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;
        for (block = 0; block < ifmap_bmap_len_expected; block = block + 1) begin
            nz_count = 0;
            bitmap = '0;
            for (local_idx = 0; local_idx < SPARSE_BLOCK_SIZE; local_idx = local_idx + 1) begin
                i = block * SPARSE_BLOCK_SIZE + local_idx;
                if ((i < ifmap_dense_len) && (dense_ifmap[i] != '0)) begin
                    glb_write(SEL_IFMAP, cmp_addr[ADDR_W-1:0], dense_ifmap[i]);
                    bitmap[local_idx] = 1'b1;
                    cmp_addr = cmp_addr + 1;
                    nz_count = nz_count + 1;
                end
            end
            ifmap_bitmap_expected[block] = bitmap;
            ifmap_nz_expected[block] = nz_count[SPARSE_COUNT_W-1:0];
            bitmap_write(SEL_IFMAP, block[BMAP_ADDR_W-1:0],
                         ifmap_bitmap_expected[block], ifmap_nz_expected[block]);
        end
        ifmap_cmp_len_expected = cmp_addr[IFMAP_AW:0];
    end
    endtask

    task automatic load_filter_vector;
        integer i;
        integer block;
        integer local_idx;
        integer cmp_addr;
        integer nz_count;
        logic [SPARSE_BLOCK_SIZE-1:0] bitmap;
    begin
        cmp_addr = 0;
        filter_bmap_len_expected = (filter_dense_len + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;
        for (block = 0; block < filter_bmap_len_expected; block = block + 1) begin
            nz_count = 0;
            bitmap = '0;
            for (local_idx = 0; local_idx < SPARSE_BLOCK_SIZE; local_idx = local_idx + 1) begin
                i = block * SPARSE_BLOCK_SIZE + local_idx;
                if ((i < filter_dense_len) && (dense_filter[i] != '0)) begin
                    glb_write(SEL_FILTER, cmp_addr[ADDR_W-1:0], dense_filter[i]);
                    bitmap[local_idx] = 1'b1;
                    cmp_addr = cmp_addr + 1;
                    nz_count = nz_count + 1;
                end
            end
            filter_bitmap_expected[block] = bitmap;
            filter_nz_expected[block] = nz_count[SPARSE_COUNT_W-1:0];
            bitmap_write(SEL_FILTER, block[BMAP_ADDR_W-1:0],
                         filter_bitmap_expected[block], filter_nz_expected[block]);
        end
        filter_cmp_len_expected = cmp_addr[FILTER_AW:0];
    end
    endtask

    task automatic load_ipsum_vector;
        integer i;
        integer block;
        integer local_idx;
        integer cmp_addr;
        integer nz_count;
        logic [SPARSE_BLOCK_SIZE-1:0] bitmap;
    begin
        cmp_addr = 0;
        ipsum_bmap_len_expected = (ipsum_dense_len + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;
        for (block = 0; block < ipsum_bmap_len_expected; block = block + 1) begin
            nz_count = 0;
            bitmap = '0;
            for (local_idx = 0; local_idx < SPARSE_BLOCK_SIZE; local_idx = local_idx + 1) begin
                i = block * SPARSE_BLOCK_SIZE + local_idx;
                if ((i < ipsum_dense_len) && (dense_ipsum[i] != '0)) begin
                    glb_write(SEL_IPSUM, cmp_addr[ADDR_W-1:0], dense_ipsum[i]);
                    bitmap[local_idx] = 1'b1;
                    cmp_addr = cmp_addr + 1;
                    nz_count = nz_count + 1;
                end
            end
            ipsum_bitmap_expected[block] = bitmap;
            ipsum_nz_expected[block] = nz_count[SPARSE_COUNT_W-1:0];
            bitmap_write(SEL_IPSUM, block[BMAP_ADDR_W-1:0],
                         ipsum_bitmap_expected[block], ipsum_nz_expected[block]);
        end
        ipsum_cmp_len_expected = cmp_addr[IPSUM_AW:0];
    end
    endtask

    task automatic build_opsum_expectations;
        integer i;
        integer block;
        integer local_idx;
        integer cmp_count;
        integer nz_count;
        logic [SPARSE_BLOCK_SIZE-1:0] bitmap;
    begin
        cmp_count = 0;
        opsum_bmap_len_expected = (golden_dense_len + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE;
        for (block = 0; block < opsum_bmap_len_expected; block = block + 1) begin
            nz_count = 0;
            bitmap = '0;
            for (local_idx = 0; local_idx < SPARSE_BLOCK_SIZE; local_idx = local_idx + 1) begin
                i = block * SPARSE_BLOCK_SIZE + local_idx;
                if ((i < golden_dense_len) && (golden_opsum_mem[i] != '0)) begin
                    bitmap[local_idx] = 1'b1;
                    cmp_count = cmp_count + 1;
                    nz_count = nz_count + 1;
                end
            end
            opsum_bitmap_expected[block] = bitmap;
            opsum_nz_expected[block] = nz_count[SPARSE_COUNT_W-1:0];
        end
        opsum_cmp_len_expected = cmp_count[OPSUM_AW:0];
    end
    endtask

    task automatic expect_glb_read(
        input logic [1:0] sel,
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_SIZE-1:0] expected
    );
    begin
        @(negedge clk);
        rd_en = 1'b1;
        rd_sel = sel;
        rd_addr = addr;
        @(posedge clk);
        #1;
        $display("[GLB_COMPARE] sel=%0d addr=%0d expected=0x%08h actual=0x%08h %s",
                 sel, addr, expected, rd_data, (rd_data === expected) ? "PASS" : "FAIL");
        if (rd_data !== expected) begin
            $error("GLB read mismatch sel=%0d addr=%0d expected=0x%08h actual=0x%08h",
                   sel, addr, expected, rd_data);
            $fatal(1);
        end
        @(negedge clk);
        rd_en = 1'b0;
        rd_sel = '0;
        rd_addr = '0;
    end
    endtask

    task automatic expect_bitmap_read(
        input logic [1:0] sel,
        input logic [BMAP_ADDR_W-1:0] addr,
        input logic [SPARSE_BLOCK_SIZE-1:0] expected_bitmap,
        input logic [SPARSE_COUNT_W-1:0] expected_nz_count
    );
    begin
        @(negedge clk);
        bitmap_rd_en = 1'b1;
        bitmap_rd_sel = sel;
        bitmap_rd_addr = addr;
        #1;
        $display("[BMAP_COMPARE] sel=%0d addr=%0d expected_bitmap=0x%02h actual_bitmap=0x%02h expected_nz=%0d actual_nz=%0d %s",
                 sel, addr, expected_bitmap, bitmap_rd_data,
                 expected_nz_count, bitmap_rd_nz_count,
                 ((bitmap_rd_data === expected_bitmap) && (bitmap_rd_nz_count === expected_nz_count)) ? "PASS" : "FAIL");
        if ((bitmap_rd_data !== expected_bitmap) ||
            (bitmap_rd_nz_count !== expected_nz_count)) begin
            $error("Bitmap read mismatch sel=%0d addr=%0d expected={0x%02h,%0d} actual={0x%02h,%0d}",
                   sel, addr, expected_bitmap, expected_nz_count, bitmap_rd_data, bitmap_rd_nz_count);
            $fatal(1);
        end
        @(negedge clk);
        bitmap_rd_en = 1'b0;
        bitmap_rd_sel = '0;
        bitmap_rd_addr = '0;
    end
    endtask

    task automatic start_full_pipeline;
    begin
        @(negedge clk);
        p_i = p_from_file[2:0];
        f_i = f_from_file[5:0];
        q_i = q_from_file[2:0];
        conv_mode_i = 1'b0;
        active_pe_mask_i = '0;
        active_pe_mask_i[0] = 1'b1;

        ifmap_tag_X_i = '0;
        ifmap_tag_Y_i = '0;
        filter_tag_X_i = '0;
        filter_tag_Y_i = '0;
        ipsum_tag_X_i = '0;
        ipsum_tag_Y_i = '0;
        opsum_tag_X_i = '0;
        opsum_tag_Y_i = '0;

        ifmap_base_i = '0;
        ifmap_len_i = ifmap_cmp_len_expected;
        filter_base_i = '0;
        filter_len_i = filter_cmp_len_expected;
        ipsum_base_i = '0;
        ipsum_len_i = ipsum_cmp_len_expected;

        ifmap_bitmap_base_i = '0;
        ifmap_bitmap_len_i = ifmap_bmap_len_expected[BMAP_ADDR_W:0];
        filter_bitmap_base_i = '0;
        filter_bitmap_len_i = filter_bmap_len_expected[BMAP_ADDR_W:0];
        ipsum_bitmap_base_i = '0;
        ipsum_bitmap_len_i = ipsum_bmap_len_expected[BMAP_ADDR_W:0];

        opsum_dense_len_i = golden_dense_len[OPSUM_AW:0];
        opsum_base_i = '0;
        opsum_bitmap_base_i = '0;

        sw_start = 1'b1;
    end
    endtask

    task automatic wait_for_pipeline_done;
        int cycles;
    begin
        cycles = 0;
        while (!controller_done) begin
            @(posedge clk);
            cycles++;
            if (controller_error) begin
                $error("Controller reported invalid configuration");
                $fatal(1);
            end
            if (cycles > 5000) begin
                $error("Timeout waiting for controller completion");
                $fatal(1);
            end
        end
        @(negedge clk);
        sw_start = 1'b0;
    end
    endtask

    task automatic check_opsum_against_golden;
        integer i;
        integer block;
        integer cmp_addr;
    begin
        $display("");
        $display("==== OPSUM compressed data compare ====");
        cmp_addr = 0;
        for (i = 0; i < golden_dense_len; i = i + 1) begin
            if (golden_opsum_mem[i] != '0) begin
                $display("dense_index=%0d -> compressed_addr=%0d", i, cmp_addr);
                expect_glb_read(SEL_OPSUM, cmp_addr[ADDR_W-1:0], golden_opsum_mem[i]);
                cmp_addr = cmp_addr + 1;
            end
            else begin
                $display("[DENSE_COMPARE] index=%0d expected=0x%08h actual=0x00000000 PASS (zero encoded by bitmap)",
                         i, golden_opsum_mem[i]);
            end
        end

        $display("");
        $display("==== OPSUM bitmap compare ====");
        for (block = 0; block < opsum_bmap_len_expected; block = block + 1) begin
            expect_bitmap_read(SEL_OPSUM, block[BMAP_ADDR_W-1:0],
                               opsum_bitmap_expected[block], opsum_nz_expected[block]);
        end
    end
    endtask

    initial begin
`ifdef FSDB
        $fsdbDumpfile("simulation/tb_top_with_controller.fsdb");
        $fsdbDumpvars(0, tb_top_with_controller);
`elsif WV_NORMAL
        $dumpfile("testbench/tb_top_with_controller.vcd");
        $dumpvars(0, tb_top_with_controller);
`endif

        rst = 1'b1;
        set_defaults();
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        if (!$value$plusargs("INPUT_FILE=%s", input_file_path)) begin
            input_file_path = "testbench/input.txt";
        end
        if (!$value$plusargs("GOLDEN_FILE=%s", golden_file_path)) begin
            golden_file_path = "testbench/golden.txt";
        end

        $display("Using input file : %s", input_file_path);
        $display("Using golden file: %s", golden_file_path);

        read_input_file();
        read_golden_file();
        build_opsum_expectations();
        PE_config = make_conv_config(p_from_file, f_from_file, q_from_file);

        load_filter_vector();
        load_ifmap_vector();
        load_ipsum_vector();

        $display("Loaded input.txt: p=%0d f=%0d q=%0d ifmap=%0d filter=%0d ipsum=%0d golden=%0d",
                 p_from_file, f_from_file, q_from_file,
                 ifmap_dense_len, filter_dense_len, ipsum_dense_len, golden_dense_len);

        expect_glb_read(SEL_FILTER, 0, dense_filter[0]);
        expect_bitmap_read(SEL_FILTER, 0, filter_bitmap_expected[0], filter_nz_expected[0]);
        expect_bitmap_read(SEL_IFMAP, 0, ifmap_bitmap_expected[0], ifmap_nz_expected[0]);
        expect_bitmap_read(SEL_IPSUM, 0, ipsum_bitmap_expected[0], ipsum_nz_expected[0]);

        start_full_pipeline();
        wait_for_pipeline_done();

        if (opsum_encoded_dense_count !== golden_dense_len) begin
            $error("Dense opsum count mismatch expected=%0d actual=%0d",
                   golden_dense_len, opsum_encoded_dense_count);
            $fatal(1);
        end
        else begin
            $display("[COUNT_COMPARE] dense_count expected=%0d actual=%0d PASS",
                     golden_dense_len, opsum_encoded_dense_count);
        end
        if (opsum_encoded_cmp_count !== opsum_cmp_len_expected) begin
            $error("Compressed opsum count mismatch expected=%0d actual=%0d",
                   opsum_cmp_len_expected, opsum_encoded_cmp_count);
            $fatal(1);
        end
        else begin
            $display("[COUNT_COMPARE] compressed_count expected=%0d actual=%0d PASS",
                     opsum_cmp_len_expected, opsum_encoded_cmp_count);
        end
        if (opsum_captured_count !== opsum_cmp_len_expected) begin
            $error("Captured opsum count mismatch expected=%0d actual=%0d",
                   opsum_cmp_len_expected, opsum_captured_count);
            $fatal(1);
        end
        else begin
            $display("[COUNT_COMPARE] captured_count expected=%0d actual=%0d PASS",
                     opsum_cmp_len_expected, opsum_captured_count);
        end

        check_opsum_against_golden();

        $display("PASS: DUT opsum stream matches golden.txt");
        repeat (5) @(posedge clk);
        $finish;
    end
endmodule
