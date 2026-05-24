`ifndef SPARSE_ENCODER_SV
`define SPARSE_ENCODER_SV

// -----------------------------------------------------------------------------
// SparseEncoder
// -----------------------------------------------------------------------------
// Length-controlled dense-to-bitmap sparse encoder.
//
// Controller starts one encode job with start_i and dense_len_i.
// The encoder consumes dense_len_i dense words and pads the last bitmap block
// with zeros when dense_len_i is not a multiple of BLOCK_SIZE.
//
// For every BLOCK_SIZE dense positions, it outputs:
//   1. one bitmap entry: bitmap[i] = 1 if original dense word i is non-zero
//   2. nz_count non-zero data words on cmp_data_o
// -----------------------------------------------------------------------------
module SparseEncoder #(
    parameter int DATA_SIZE  = 32,
    parameter int BLOCK_SIZE = 8,
    parameter int LEN_W      = 16,
    parameter int COUNT_W    = (BLOCK_SIZE <= 1) ? 1 : $clog2(BLOCK_SIZE + 1)
)(
    input  logic clk, // 時脈訊號，所有 sequential logic 在正緣更新
    input  logic rst, // 非同步 reset，高電位時清空 FSM、計數器與暫存資料

    // Encode command.
    input  logic                 start_i,        // 開始壓縮脈衝，拉高一拍後 Encoder 開始處理一筆工作
    input  logic [LEN_W-1:0]     dense_len_i,    // 本次要壓縮的 dense 資料總筆數
    output logic                 busy_o,         // Encoder 忙碌中，代表目前不在 idle state
    output logic                 done_o,         // 壓縮完成脈衝，完成當下拉高一拍
    output logic [LEN_W-1:0]     dense_count_o,  // 已吃進 Encoder 的 dense word 數量
    output logic [LEN_W-1:0]     cmp_count_o,    // 已輸出的 compressed non-zero word 數量
    output logic [LEN_W-1:0]     bitmap_count_o, // 已輸出的 bitmap block 數量

    // Dense input stream, one original word per handshake.
    input  logic [DATA_SIZE-1:0] dense_data_i,  // 原始 dense 資料輸入，一次一個 word
    input  logic                 dense_valid_i, // 上游表示 dense_data_i 有效
    output logic                 dense_ready_o, // Encoder 可接收 dense_data_i；valid 與 ready 同時為 1 時完成接收

    // Bitmap output stream, one bitmap per block.
    output logic [BLOCK_SIZE-1:0] bitmap_o,       // 每個 block 的非零位置圖，bit=1 代表該位置資料非零
    output logic [COUNT_W-1:0]    nz_count_o,     // 該 bitmap block 內非零資料的數量
    output logic                  bitmap_valid_o, // Encoder 表示 bitmap_o / nz_count_o 有效
    input  logic                  bitmap_ready_i, // 下游可接收 bitmap；valid 與 ready 同時為 1 時完成輸出

    // Compressed output stream, only non-zero words are sent.
    output logic [DATA_SIZE-1:0] cmp_data_o,  // 壓縮後的非零資料輸出，只送 dense 中非 0 的 word
    output logic                 cmp_valid_o, // Encoder 表示 cmp_data_o 有效
    input  logic                 cmp_ready_i  // 下游可接收 compressed data；valid 與 ready 同時為 1 時完成輸出
);

    initial begin
        if (BLOCK_SIZE <= 0) begin
            $error("SparseEncoder: BLOCK_SIZE must be greater than 0");
        end
        if (LEN_W <= 0) begin
            $error("SparseEncoder: LEN_W must be greater than 0");
        end
    end

    localparam int IDX_W = (BLOCK_SIZE <= 1) ? 1 : $clog2(BLOCK_SIZE);

    typedef enum logic [1:0] {
        S_IDLE        = 2'd0,
        S_COLLECT     = 2'd1,
        S_SEND_BITMAP = 2'd2,
        S_SEND_DATA   = 2'd3
    } state_t;

    state_t state_q;

    logic [LEN_W-1:0] remaining_q;
    logic [LEN_W-1:0] dense_count_q;
    logic [LEN_W-1:0] cmp_count_q;
    logic [LEN_W-1:0] bitmap_count_q;

    logic [IDX_W-1:0] collect_idx_q;
    logic [COUNT_W-1:0] nz_count_q;
    logic [COUNT_W-1:0] send_idx_q;
    logic [BLOCK_SIZE-1:0] bitmap_q;
    logic [DATA_SIZE-1:0] nz_buf_q [0:BLOCK_SIZE-1];

    logic dense_fire;
    logic bitmap_fire;
    logic cmp_fire;
    logic last_word_of_job;
    logic last_word_of_block;
    logic finish_block;
    logic finish_job_after_bitmap;
    logic finish_job_after_data;
    logic done_q;

    assign busy_o          = (state_q != S_IDLE);
    assign done_o          = done_q;
    assign dense_count_o   = dense_count_q;
    assign cmp_count_o     = cmp_count_q;
    assign bitmap_count_o  = bitmap_count_q;

    assign dense_ready_o   = (state_q == S_COLLECT) && (remaining_q != '0);
    assign dense_fire      = dense_valid_i & dense_ready_o;

    assign bitmap_valid_o  = (state_q == S_SEND_BITMAP);
    assign bitmap_o        = bitmap_q;
    assign nz_count_o      = nz_count_q;
    assign bitmap_fire     = bitmap_valid_o & bitmap_ready_i;

    assign cmp_valid_o     = (state_q == S_SEND_DATA) && (send_idx_q < nz_count_q);
    assign cmp_data_o      = (send_idx_q < nz_count_q) ? nz_buf_q[send_idx_q] : '0;
    assign cmp_fire        = cmp_valid_o & cmp_ready_i;

    assign last_word_of_job   = (remaining_q == {{(LEN_W-1){1'b0}}, 1'b1});
    assign last_word_of_block = (collect_idx_q == (BLOCK_SIZE-1));
    assign finish_block       = dense_fire && (last_word_of_block || last_word_of_job);

    assign finish_job_after_bitmap = (remaining_q == '0) && (nz_count_q == '0);
    assign finish_job_after_data   = (remaining_q == '0) && (send_idx_q == (nz_count_q - 1'b1));

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q        <= S_IDLE;
            remaining_q    <= '0;
            dense_count_q  <= '0;
            cmp_count_q    <= '0;
            bitmap_count_q <= '0;
            collect_idx_q  <= '0;
            nz_count_q     <= '0;
            send_idx_q     <= '0;
            bitmap_q       <= '0;
            done_q         <= 1'b0;
        end
        else begin
            done_q <= 1'b0;

            unique case (state_q)
                S_IDLE: begin
                    collect_idx_q <= '0;
                    nz_count_q    <= '0;
                    send_idx_q    <= '0;
                    bitmap_q      <= '0;

                    if (start_i) begin
                        remaining_q    <= dense_len_i;
                        dense_count_q  <= '0;
                        cmp_count_q    <= '0;
                        bitmap_count_q <= '0;

                        if (dense_len_i == '0) begin
                            done_q  <= 1'b1;
                            state_q <= S_IDLE;
                        end
                        else begin
                            state_q <= S_COLLECT;
                        end
                    end
                end

                S_COLLECT: begin
                    if (dense_fire) begin
                        bitmap_q[collect_idx_q] <= (dense_data_i != '0);
                        remaining_q             <= remaining_q - 1'b1;
                        dense_count_q           <= dense_count_q + 1'b1;

                        if (dense_data_i != '0) begin
                            nz_buf_q[nz_count_q] <= dense_data_i;
                            nz_count_q           <= nz_count_q + 1'b1;
                        end

                        if (finish_block) begin
                            collect_idx_q <= '0;
                            state_q       <= S_SEND_BITMAP;
                        end
                        else begin
                            collect_idx_q <= collect_idx_q + 1'b1;
                        end
                    end
                end

                S_SEND_BITMAP: begin
                    if (bitmap_fire) begin
                        bitmap_count_q <= bitmap_count_q + 1'b1;
                        send_idx_q     <= '0;

                        if (finish_job_after_bitmap) begin
                            bitmap_q   <= '0;
                            nz_count_q <= '0;
                            state_q    <= S_IDLE;
                            done_q     <= 1'b1;
                        end
                        else if (nz_count_q == '0) begin
                            bitmap_q   <= '0;
                            nz_count_q <= '0;
                            state_q    <= S_COLLECT;
                        end
                        else begin
                            state_q <= S_SEND_DATA;
                        end
                    end
                end

                S_SEND_DATA: begin
                    if (cmp_fire) begin
                        cmp_count_q <= cmp_count_q + 1'b1;

                        if (send_idx_q == (nz_count_q - 1'b1)) begin
                            send_idx_q <= '0;
                            bitmap_q   <= '0;
                            nz_count_q <= '0;

                            if (finish_job_after_data) begin
                                state_q <= S_IDLE;
                                done_q  <= 1'b1;
                            end
                            else begin
                                state_q <= S_COLLECT;
                            end
                        end
                        else begin
                            send_idx_q <= send_idx_q + 1'b1;
                        end
                    end
                end

                default: begin
                    state_q        <= S_IDLE;
                    remaining_q    <= '0;
                    dense_count_q  <= '0;
                    cmp_count_q    <= '0;
                    bitmap_count_q <= '0;
                    collect_idx_q  <= '0;
                    nz_count_q     <= '0;
                    send_idx_q     <= '0;
                    bitmap_q       <= '0;
                end
            endcase
        end
    end

endmodule

`endif // SPARSE_ENCODER_SV
