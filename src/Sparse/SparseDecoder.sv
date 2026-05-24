`ifndef SPARSE_DECODER_SV
`define SPARSE_DECODER_SV

// -----------------------------------------------------------------------------
// SparseDecoder
// -----------------------------------------------------------------------------
// Convert bitmap sparse format back to a dense stream.
// For each bitmap entry, the decoder outputs BLOCK_SIZE dense words.
// If bitmap[i] == 0, output zero.
// If bitmap[i] == 1, consume one compressed data word and output it.
// -----------------------------------------------------------------------------
module SparseDecoder #(
    parameter int DATA_SIZE  = 32,
    parameter int BLOCK_SIZE = 8,
    parameter int COUNT_W    = (BLOCK_SIZE <= 1) ? 1 : $clog2(BLOCK_SIZE + 1)
)(
    input  logic clk, // 時脈訊號，所有 sequential logic 在正緣更新
    input  logic rst, // 非同步 reset，高電位時回到等待 bitmap 的初始狀態

    // Bitmap input stream from BitmapBuffer.
    input  logic [BLOCK_SIZE-1:0] bitmap_i,       // 每個 block 的非零位置圖，bit=1 代表該位置要讀一筆 compressed data
    input  logic [COUNT_W-1:0]    nz_count_i,     // 該 block 的非零資料數量，目前主要作為檢查/除錯資訊
    input  logic                  bitmap_valid_i, // 上游表示 bitmap_i / nz_count_i 有效
    output logic                  bitmap_ready_o, // Decoder 可接收 bitmap；valid 與 ready 同時為 1 時完成接收

    // Compressed non-zero data input stream from GLB/DMA.
    input  logic [DATA_SIZE-1:0] cmp_data_i,  // 壓縮後的非零資料輸入，只在目前 bitmap bit=1 時會被消耗
    input  logic                 cmp_valid_i, // 上游表示 cmp_data_i 有效
    output logic                 cmp_ready_o, // Decoder 需要一筆 compressed data 時拉高；valid 與 ready 同時為 1 時完成接收

    // Dense output stream to PE_array / NoC.
    output logic [DATA_SIZE-1:0] dense_data_o,  // 解壓縮後的 dense 資料輸出；bitmap bit=0 時輸出 0，bit=1 時輸出 cmp_data_i
    output logic                 dense_valid_o, // Decoder 表示 dense_data_o 有效
    input  logic                 dense_ready_i  // 下游可接收 dense data；valid 與 ready 同時為 1 時完成輸出
);

    initial begin
        if (BLOCK_SIZE <= 0) begin
            $error("SparseDecoder: BLOCK_SIZE must be greater than 0");
        end
    end

    localparam int IDX_W = (BLOCK_SIZE <= 1) ? 1 : $clog2(BLOCK_SIZE);

    typedef enum logic [0:0] {
        S_WAIT_BITMAP = 1'b0,
        S_OUTPUT      = 1'b1
    } state_t;

    state_t state_q;

    logic [BLOCK_SIZE-1:0] bitmap_q;
    logic [IDX_W-1:0]      out_idx_q;
    logic                  current_is_nonzero;
    logic                  bitmap_fire;
    logic                  dense_fire;

    assign bitmap_ready_o = (state_q == S_WAIT_BITMAP);
    assign bitmap_fire    = bitmap_valid_i & bitmap_ready_o;

    assign current_is_nonzero = bitmap_q[out_idx_q];

    assign dense_valid_o = (state_q == S_OUTPUT) ?
                           (current_is_nonzero ? cmp_valid_i : 1'b1) :
                           1'b0;

    assign dense_data_o  = (state_q == S_OUTPUT) ?
                           (current_is_nonzero ? cmp_data_i : '0) :
                           '0;

    assign cmp_ready_o   = (state_q == S_OUTPUT) && current_is_nonzero && dense_ready_i;
    assign dense_fire    = dense_valid_o & dense_ready_i;

    // nz_count_i is kept for checking/debug. Decoding is determined by bitmap_i.
    logic unused_nz_count;
    assign unused_nz_count = ^nz_count_i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q   <= S_WAIT_BITMAP;
            bitmap_q  <= '0;
            out_idx_q <= '0;
        end
        else begin
            unique case (state_q)
                S_WAIT_BITMAP: begin
                    if (bitmap_fire) begin
                        bitmap_q  <= bitmap_i;
                        out_idx_q <= '0;
                        state_q   <= S_OUTPUT;
                    end
                end

                S_OUTPUT: begin
                    if (dense_fire) begin
                        if (out_idx_q == (BLOCK_SIZE-1)) begin
                            out_idx_q <= '0;
                            bitmap_q  <= '0;
                            state_q   <= S_WAIT_BITMAP;
                        end
                        else begin
                            out_idx_q <= out_idx_q + 1'b1;
                        end
                    end
                end

                default: begin
                    state_q   <= S_WAIT_BITMAP;
                    bitmap_q  <= '0;
                    out_idx_q <= '0;
                end
            endcase
        end
    end

endmodule

`endif // SPARSE_DECODER_SV
