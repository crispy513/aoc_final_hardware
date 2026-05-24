`ifndef BITMAP_BUFFER_SV
`define BITMAP_BUFFER_SV

// -----------------------------------------------------------------------------
// BitmapBuffer
// -----------------------------------------------------------------------------
// Store bitmap metadata for sparse compressed data.
// Each entry corresponds to one block:
//   bitmap_mem[entry]   : which positions in the block are non-zero
//   nz_count_mem[entry] : number of non-zero words in this block
// -----------------------------------------------------------------------------
module BitmapBuffer #(
    parameter int BLOCK_SIZE = 8,
    parameter int DEPTH      = 1024,
    parameter int ADDR_W     = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int COUNT_W    = (BLOCK_SIZE <= 1) ? 1 : $clog2(BLOCK_SIZE + 1)
)(
    input  logic clk, // 時脈訊號，host/capture/stream 狀態皆在正緣更新
    input  logic rst, // 非同步 reset，高電位時清空 capture/stream 指標與 busy 狀態

    // Host / AXI-MMIO random access interface.
    input  logic                    host_wr_en,          // Host 隨機寫入使能，拉高時把 bitmap/nz_count 寫進指定 entry
    input  logic [ADDR_W-1:0]       host_wr_addr,        // Host 寫入的 bitmap buffer 位址
    input  logic [BLOCK_SIZE-1:0]   host_bitmap_wdata,   // Host 寫入的 bitmap，bit=1 代表該 block 位置非零
    input  logic [COUNT_W-1:0]      host_nz_count_wdata, // Host 寫入的非零資料數量

    input  logic                    host_rd_en,          // Host 隨機讀取使能，拉高時讀出指定 entry
    input  logic [ADDR_W-1:0]       host_rd_addr,        // Host 讀取的 bitmap buffer 位址
    output logic [BLOCK_SIZE-1:0]   host_bitmap_rdata,   // Host 讀出的 bitmap
    output logic [COUNT_W-1:0]      host_nz_count_rdata, // Host 讀出的非零資料數量

    // Sequential capture interface from SparseEncoder.
    // capture_len means number of bitmap entries.
    input  logic                    start_capture, // 開始從 SparseEncoder 連續寫入 bitmap metadata 的脈衝
    input  logic [ADDR_W-1:0]       capture_base,  // capture 寫入起始位址
    input  logic [ADDR_W:0]         capture_len,   // capture 要寫入的 bitmap entry 數量
    output logic                    capture_busy,  // capture 進行中，代表正在等待/接收 Encoder metadata
    output logic                    capture_done,  // capture 完成脈衝，最後一筆 entry 寫入後拉高一拍

    input  logic [BLOCK_SIZE-1:0]   enc_bitmap_i,   // SparseEncoder 輸入的 bitmap metadata
    input  logic [COUNT_W-1:0]      enc_nz_count_i, // SparseEncoder 輸入的該 block 非零數量
    input  logic                    enc_valid_i,    // Encoder 表示 enc_bitmap_i / enc_nz_count_i 有效
    output logic                    enc_ready_o,    // BitmapBuffer 可接收 Encoder metadata；valid 與 ready 同時為 1 時完成寫入

    // Sequential stream interface to SparseDecoder.
    // stream_len means number of bitmap entries.
    input  logic                    start_stream, // 開始連續送 bitmap metadata 給 SparseDecoder 的脈衝
    input  logic [ADDR_W-1:0]       stream_base,  // stream 讀取起始位址
    input  logic [ADDR_W:0]         stream_len,   // stream 要送出的 bitmap entry 數量
    output logic                    stream_busy,  // stream 進行中，代表還有 metadata 尚未送完
    output logic                    stream_done,  // stream 完成脈衝，最後一筆 entry 被 Decoder 接收後拉高一拍

    output logic [BLOCK_SIZE-1:0]   dec_bitmap_o,   // 輸出給 SparseDecoder 的 bitmap metadata
    output logic [COUNT_W-1:0]      dec_nz_count_o, // 輸出給 SparseDecoder 的該 block 非零數量
    output logic                    dec_valid_o,    // BitmapBuffer 表示 dec_bitmap_o / dec_nz_count_o 有效
    input  logic                    dec_ready_i     // Decoder 可接收 metadata；valid 與 ready 同時為 1 時完成輸出
);

    initial begin
        if (BLOCK_SIZE <= 0) begin
            $error("BitmapBuffer: BLOCK_SIZE must be greater than 0");
        end
        if (DEPTH <= 0) begin
            $error("BitmapBuffer: DEPTH must be greater than 0");
        end
    end

    logic [BLOCK_SIZE-1:0] bitmap_mem   [0:DEPTH-1];
    logic [COUNT_W-1:0]    nz_count_mem [0:DEPTH-1];

    logic [ADDR_W-1:0] cap_ptr_q, cap_ptr_d;
    logic [ADDR_W:0]   cap_left_q, cap_left_d;
    logic              cap_en_q, cap_en_d;

    logic [ADDR_W-1:0] str_ptr_q, str_ptr_d;
    logic [ADDR_W:0]   str_left_q, str_left_d;

    logic enc_fire;
    logic dec_fire;

    always_comb begin
        host_bitmap_rdata   = '0;
        host_nz_count_rdata = '0;
        if (host_rd_en) begin
            host_bitmap_rdata   = bitmap_mem[host_rd_addr];
            host_nz_count_rdata = nz_count_mem[host_rd_addr];
        end
    end

    always_comb begin
        cap_ptr_d      = cap_ptr_q;
        cap_left_d     = cap_left_q;
        cap_en_d       = cap_en_q;
        capture_done   = 1'b0;

        if (start_capture && !cap_en_q) begin
            cap_ptr_d  = capture_base;
            cap_left_d = capture_len;
            cap_en_d   = (capture_len != '0);
        end
        else if (enc_fire) begin
            cap_ptr_d  = cap_ptr_q + 1'b1;
            cap_left_d = cap_left_q - 1'b1;
            if (cap_left_q == {{ADDR_W{1'b0}}, 1'b1}) begin
                cap_en_d     = 1'b0;
                capture_done = 1'b1;
            end
        end
    end

    assign capture_busy = cap_en_q;
    assign enc_ready_o  = cap_en_q && (cap_left_q != '0);
    assign enc_fire     = enc_valid_i & enc_ready_o;

    always_comb begin
        str_ptr_d    = str_ptr_q;
        str_left_d   = str_left_q;
        stream_done  = 1'b0;

        if (start_stream && !stream_busy) begin
            str_ptr_d  = stream_base;
            str_left_d = stream_len;
        end
        else if (dec_fire) begin
            str_ptr_d  = str_ptr_q + 1'b1;
            str_left_d = str_left_q - 1'b1;
            if (str_left_q == {{ADDR_W{1'b0}}, 1'b1}) begin
                stream_done = 1'b1;
            end
        end
    end

    assign stream_busy    = (str_left_q != '0);
    assign dec_valid_o    = (str_left_q != '0);
    assign dec_bitmap_o   = bitmap_mem[str_ptr_q];
    assign dec_nz_count_o = nz_count_mem[str_ptr_q];
    assign dec_fire       = dec_valid_o & dec_ready_i;

    always_ff @(posedge clk) begin
        if (enc_fire) begin
            bitmap_mem[cap_ptr_q]   <= enc_bitmap_i;
            nz_count_mem[cap_ptr_q] <= enc_nz_count_i;
        end
        else if (host_wr_en) begin
            bitmap_mem[host_wr_addr]   <= host_bitmap_wdata;
            nz_count_mem[host_wr_addr] <= host_nz_count_wdata;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cap_ptr_q   <= '0;
            cap_left_q  <= '0;
            cap_en_q    <= 1'b0;
            str_ptr_q   <= '0;
            str_left_q  <= '0;
        end
        else begin
            cap_ptr_q   <= cap_ptr_d;
            cap_left_q  <= cap_left_d;
            cap_en_q    <= cap_en_d;
            str_ptr_q   <= str_ptr_d;
            str_left_q  <= str_left_d;
        end
    end

endmodule

`endif // BITMAP_BUFFER_SV
