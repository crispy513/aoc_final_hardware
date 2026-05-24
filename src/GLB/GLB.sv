`ifndef GLB_USE_EXTERNAL_TS6N16
module TS6N16ADFPCLLLVTA128X64M4FWSHOD #(
    parameter N = 64,
    parameter W = 128,
    parameter M = 7
)(
    input  [M-1:0] AA,
    input  [N-1:0] D,
    input  [N-1:0] BWEB,
    input          WEB,
    input          CLKW,
    input  [M-1:0] AB,
    input          REB,
    input          CLKR,
    input          SLP,
    input          DSLP,
    input          SD,
    output         PUDELAY,
    input  [1:0]   RCT,
    input  [1:0]   WCT,
    input  [2:0]   KP,
    output logic [N-1:0] Q
);

    logic [N-1:0] mem [0:W-1];

    assign PUDELAY = 1'b0;

    always_ff @(posedge CLKW) begin
        if (!WEB) begin
            for (int i = 0; i < N; i++) begin
                if (!BWEB[i]) begin
                    mem[AA][i] <= D[i];
                end
            end
        end
    end

    always_ff @(posedge CLKR) begin
        if (!REB) begin
            Q <= mem[AB];
        end
    end

endmodule
`endif

module GLB_SRAM32 #(
    parameter int DEPTH  = 256,
    parameter int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
)(
    input  logic              clk,

    input  logic              wr_en,
    input  logic [ADDR_W-1:0] wr_addr,
    input  logic [31:0]       wr_data,

    input  logic              rd_en,
    input  logic [ADDR_W-1:0] rd_addr,
    output logic [31:0]       rd_data
);

    localparam int LOGICAL_WORDS_PER_BANK = 256;
    localparam int NUM_BANKS = (DEPTH + LOGICAL_WORDS_PER_BANK - 1) / LOGICAL_WORDS_PER_BANK;
    localparam int BANK_W = (NUM_BANKS <= 1) ? 1 : $clog2(NUM_BANKS);

    logic [BANK_W-1:0] wr_bank;
    logic [BANK_W-1:0] rd_bank;
    logic [BANK_W-1:0] rd_bank_q;
    logic              rd_half_q;
    logic              rd_hit_q;
    logic              wr_hit;
    logic              rd_hit;
    logic [6:0]        wr_row;
    logic [6:0]        rd_row;
    logic [63:0]       wr_data64;
    logic [63:0]       wr_bweb;
    wire  [NUM_BANKS*64-1:0] bank_q_flat;
    logic [63:0]       rd_q_mux;

    assign wr_bank  = (NUM_BANKS <= 1) ? '0 : (wr_addr >> 8);
    assign rd_bank  = (NUM_BANKS <= 1) ? '0 : (rd_addr >> 8);
    assign wr_row   = wr_addr >> 1;
    assign rd_row   = rd_addr >> 1;
    assign wr_data64 = wr_addr[0] ? {wr_data, 32'b0} : {32'b0, wr_data};
    assign wr_bweb   = wr_addr[0] ? 64'h0000_0000_ffff_ffff : 64'hffff_ffff_0000_0000;
    assign wr_hit    = wr_en && (wr_addr < DEPTH);
    assign rd_hit    = rd_en && (rd_addr < DEPTH);

    always_ff @(posedge clk) begin
        rd_bank_q <= rd_bank;
        rd_half_q <= rd_addr[0];
        rd_hit_q  <= rd_hit;
    end

    always_comb begin
        rd_q_mux = '0;
        for (int i = 0; i < NUM_BANKS; i++) begin
            if (rd_bank_q == i) begin
                rd_q_mux = bank_q_flat[i*64 +: 64];
            end
        end
    end

    assign rd_data = rd_hit_q ? (rd_half_q ? rd_q_mux[63:32] : rd_q_mux[31:0]) : 32'b0;

    generate
        for (genvar b = 0; b < NUM_BANKS; b++) begin : GEN_BANK
            localparam int BANK_BASE = b * 64;
            localparam logic [BANK_W-1:0] BANK_ID = b[BANK_W-1:0];
            wire pudelay_unused;
            wire [63:0] bank_q_local;

            assign bank_q_flat[BANK_BASE +: 64] = bank_q_local;

            TS6N16ADFPCLLLVTA128X64M4FWSHOD u_sram (
                .AA      (wr_row),
                .D       (wr_data64),
                .BWEB    (wr_bweb),
                .WEB     (!(wr_hit && (wr_bank == BANK_ID))),
                .CLKW    (clk),
                .AB      (rd_row),
                .REB     (!(rd_hit && (rd_bank == BANK_ID))),
                .CLKR    (clk),
                .SLP     (1'b0),
                .DSLP    (1'b0),
                .SD      (1'b0),
                .PUDELAY (pudelay_unused),
                .RCT     (2'b0),
                .WCT     (2'b0),
                .KP      (3'b0),
                .Q       (bank_q_local)
            );
        end
    endgenerate

endmodule

module GLB #(
    parameter int DATA_SIZE     = 32,
    parameter int IFMAP_DEPTH   = 4096,
    parameter int FILTER_DEPTH  = 2048,
    parameter int IPSUM_DEPTH   = 8192,
    parameter int OPSUM_DEPTH   = 8192,
    parameter int IFMAP_AW      = (IFMAP_DEPTH  <= 1) ? 1 : $clog2(IFMAP_DEPTH),
    parameter int FILTER_AW     = (FILTER_DEPTH <= 1) ? 1 : $clog2(FILTER_DEPTH),
    parameter int IPSUM_AW      = (IPSUM_DEPTH  <= 1) ? 1 : $clog2(IPSUM_DEPTH),
    parameter int OPSUM_AW      = (OPSUM_DEPTH  <= 1) ? 1 : $clog2(OPSUM_DEPTH),
    parameter int ADDR_W        = ((IFMAP_AW > FILTER_AW) ?
                                  ((IFMAP_AW > IPSUM_AW) ?
                                  ((IFMAP_AW > OPSUM_AW) ? IFMAP_AW : OPSUM_AW) :
                                  ((IPSUM_AW > OPSUM_AW) ? IPSUM_AW : OPSUM_AW)) :
                                  ((FILTER_AW > IPSUM_AW) ?
                                  ((FILTER_AW > OPSUM_AW) ? FILTER_AW : OPSUM_AW) :
                                  ((IPSUM_AW > OPSUM_AW) ? IPSUM_AW : OPSUM_AW)))
)(
    input  logic clk,
    input  logic rst,

    input  logic                 wr_en,
    input  logic [1:0]           wr_sel,
    input  logic [ADDR_W-1:0]    wr_addr,
    input  logic [DATA_SIZE-1:0] wr_data,

    input  logic                 rd_en,
    input  logic [1:0]           rd_sel,
    input  logic [ADDR_W-1:0]    rd_addr,
    output logic [DATA_SIZE-1:0] rd_data,

    input  logic                   start_ifmap,
    input  logic [IFMAP_AW-1:0]    ifmap_base,
    input  logic [IFMAP_AW:0]      ifmap_len,
    output logic                   ifmap_busy,
    output logic                   ifmap_done,

    input  logic                   start_filter,
    input  logic [FILTER_AW-1:0]   filter_base,
    input  logic [FILTER_AW:0]     filter_len,
    output logic                   filter_busy,
    output logic                   filter_done,

    input  logic                   start_ipsum,
    input  logic [IPSUM_AW-1:0]    ipsum_base,
    input  logic [IPSUM_AW:0]      ipsum_len,
    output logic                   ipsum_busy,
    output logic                   ipsum_done,

    input  logic                   start_capture_opsum,
    input  logic [OPSUM_AW-1:0]    opsum_base,
    input  logic [OPSUM_AW:0]      opsum_len,
    input  logic                   opsum_capture_stop,
    output logic [OPSUM_AW:0]      opsum_captured_count,
    output logic                   opsum_busy,
    output logic                   opsum_done,

    output logic                   GLB_ifmap_valid,
    input  logic                   GLB_ifmap_ready,
    output logic [DATA_SIZE-1:0]   GLB_ifmap_data_in,

    output logic                   GLB_filter_valid,
    input  logic                   GLB_filter_ready,
    output logic [DATA_SIZE-1:0]   GLB_filter_data_in,

    output logic                   GLB_ipsum_valid,
    input  logic                   GLB_ipsum_ready,
    output logic [DATA_SIZE-1:0]   GLB_ipsum_data_in,

    input  logic                   GLB_opsum_valid,
    output logic                   GLB_opsum_ready,
    input  logic [DATA_SIZE-1:0]   GLB_data_out
);

    typedef enum logic [1:0] {
        SEL_IFMAP  = 2'd0,
        SEL_FILTER = 2'd1,
        SEL_IPSUM  = 2'd2,
        SEL_OPSUM  = 2'd3
    } mem_sel_t;

    logic [IFMAP_AW-1:0]  ifmap_ptr_q,  ifmap_ptr_d;
    logic [FILTER_AW-1:0] filter_ptr_q, filter_ptr_d;
    logic [IPSUM_AW-1:0]  ipsum_ptr_q,  ipsum_ptr_d;

    logic [IFMAP_AW:0]    ifmap_left_q,  ifmap_left_d;
    logic [FILTER_AW:0]   filter_left_q, filter_left_d;
    logic [IPSUM_AW:0]    ipsum_left_q,  ipsum_left_d;

    logic [OPSUM_AW-1:0]  opsum_wr_ptr_q, opsum_wr_ptr_d;
    logic [OPSUM_AW:0]    opsum_left_q,   opsum_left_d;
    logic [OPSUM_AW:0]    opsum_count_q,  opsum_count_d;
    logic                 opsum_cap_en_q, opsum_cap_en_d;

    logic ifmap_valid_q,  ifmap_valid_d;
    logic filter_valid_q, filter_valid_d;
    logic ipsum_valid_q,  ipsum_valid_d;
    logic ifmap_pending_q,  ifmap_pending_d;
    logic filter_pending_q, filter_pending_d;
    logic ipsum_pending_q,  ipsum_pending_d;
    logic [31:0] ifmap_data_q,  ifmap_data_d;
    logic [31:0] filter_data_q, filter_data_d;
    logic [31:0] ipsum_data_q,  ipsum_data_d;

    logic ifmap_fire;
    logic filter_fire;
    logic ipsum_fire;
    logic opsum_fire;

    logic ifmap_stream_rd_en;
    logic filter_stream_rd_en;
    logic ipsum_stream_rd_en;

    logic ifmap_host_rd_en;
    logic filter_host_rd_en;
    logic ipsum_host_rd_en;
    logic opsum_host_rd_en;
    logic host_rd_pending_q;
    logic [1:0] host_rd_sel_q;

    logic [IFMAP_AW-1:0]  ifmap_rd_addr;
    logic [FILTER_AW-1:0] filter_rd_addr;
    logic [IPSUM_AW-1:0]  ipsum_rd_addr;
    logic [OPSUM_AW-1:0]  opsum_wr_addr;
    logic [OPSUM_AW-1:0]  opsum_rd_addr;

    logic ifmap_wr_en;
    logic filter_wr_en;
    logic ipsum_wr_en;
    logic opsum_wr_en;

    logic [31:0] ifmap_rdata;
    logic [31:0] filter_rdata;
    logic [31:0] ipsum_rdata;
    logic [31:0] opsum_rdata;
    logic [31:0] opsum_wr_data;

    initial begin
        if (DATA_SIZE != 32) begin
            $error("GLB_SRAM32 replacement requires DATA_SIZE == 32.");
        end
    end

    assign ifmap_busy  = (ifmap_left_q  != 0) || ifmap_valid_q  || ifmap_pending_q;
    assign filter_busy = (filter_left_q != 0) || filter_valid_q || filter_pending_q;
    assign ipsum_busy  = (ipsum_left_q  != 0) || ipsum_valid_q  || ipsum_pending_q;

    assign GLB_ifmap_valid   = ifmap_valid_q;
    assign GLB_filter_valid  = filter_valid_q;
    assign GLB_ipsum_valid   = ipsum_valid_q;
    assign GLB_ifmap_data_in = ifmap_data_q;
    assign GLB_filter_data_in = filter_data_q;
    assign GLB_ipsum_data_in = ipsum_data_q;

    assign ifmap_fire  = GLB_ifmap_valid  & GLB_ifmap_ready;
    assign filter_fire = GLB_filter_valid & GLB_filter_ready;
    assign ipsum_fire  = GLB_ipsum_valid  & GLB_ipsum_ready;

    assign ifmap_stream_rd_en  = (ifmap_left_q  != 0) && !ifmap_pending_q  && (!ifmap_valid_q  || ifmap_fire);
    assign filter_stream_rd_en = (filter_left_q != 0) && !filter_pending_q && (!filter_valid_q || filter_fire);
    assign ipsum_stream_rd_en  = (ipsum_left_q  != 0) && !ipsum_pending_q  && (!ipsum_valid_q  || ipsum_fire);

    assign ifmap_host_rd_en  = rd_en && (mem_sel_t'(rd_sel) == SEL_IFMAP)  && (rd_addr < IFMAP_DEPTH)  && !ifmap_busy;
    assign filter_host_rd_en = rd_en && (mem_sel_t'(rd_sel) == SEL_FILTER) && (rd_addr < FILTER_DEPTH) && !filter_busy;
    assign ipsum_host_rd_en  = rd_en && (mem_sel_t'(rd_sel) == SEL_IPSUM)  && (rd_addr < IPSUM_DEPTH)  && !ipsum_busy;
    assign opsum_host_rd_en  = rd_en && (mem_sel_t'(rd_sel) == SEL_OPSUM)  && (rd_addr < OPSUM_DEPTH);

    assign ifmap_rd_addr  = ifmap_stream_rd_en  ? ifmap_ptr_q  : rd_addr[IFMAP_AW-1:0];
    assign filter_rd_addr = filter_stream_rd_en ? filter_ptr_q : rd_addr[FILTER_AW-1:0];
    assign ipsum_rd_addr  = ipsum_stream_rd_en  ? ipsum_ptr_q  : rd_addr[IPSUM_AW-1:0];
    assign opsum_rd_addr  = rd_addr[OPSUM_AW-1:0];

    assign ifmap_wr_en  = wr_en && (mem_sel_t'(wr_sel) == SEL_IFMAP)  && (wr_addr < IFMAP_DEPTH);
    assign filter_wr_en = wr_en && (mem_sel_t'(wr_sel) == SEL_FILTER) && (wr_addr < FILTER_DEPTH);
    assign ipsum_wr_en  = wr_en && (mem_sel_t'(wr_sel) == SEL_IPSUM)  && (wr_addr < IPSUM_DEPTH);

    assign GLB_opsum_ready = opsum_cap_en_q && (opsum_left_q != 0);
    assign opsum_fire      = GLB_opsum_valid & GLB_opsum_ready;
    assign opsum_wr_en     = (opsum_fire && (opsum_wr_ptr_q < OPSUM_DEPTH)) ||
                             (wr_en && (mem_sel_t'(wr_sel) == SEL_OPSUM) &&
                              (wr_addr < OPSUM_DEPTH) && !opsum_fire);
    assign opsum_wr_addr   = (opsum_fire && (opsum_wr_ptr_q < OPSUM_DEPTH)) ?
                             opsum_wr_ptr_q : wr_addr[OPSUM_AW-1:0];
    assign opsum_wr_data   = (opsum_fire && (opsum_wr_ptr_q < OPSUM_DEPTH)) ?
                             GLB_data_out[31:0] : wr_data[31:0];

    GLB_SRAM32 #(
        .DEPTH  (IFMAP_DEPTH),
        .ADDR_W (IFMAP_AW)
    ) u_ifmap_mem (
        .clk     (clk),
        .wr_en   (ifmap_wr_en),
        .wr_addr (wr_addr[IFMAP_AW-1:0]),
        .wr_data (wr_data[31:0]),
        .rd_en   (ifmap_stream_rd_en || ifmap_host_rd_en),
        .rd_addr (ifmap_rd_addr),
        .rd_data (ifmap_rdata)
    );

    GLB_SRAM32 #(
        .DEPTH  (FILTER_DEPTH),
        .ADDR_W (FILTER_AW)
    ) u_filter_mem (
        .clk     (clk),
        .wr_en   (filter_wr_en),
        .wr_addr (wr_addr[FILTER_AW-1:0]),
        .wr_data (wr_data[31:0]),
        .rd_en   (filter_stream_rd_en || filter_host_rd_en),
        .rd_addr (filter_rd_addr),
        .rd_data (filter_rdata)
    );

    GLB_SRAM32 #(
        .DEPTH  (IPSUM_DEPTH),
        .ADDR_W (IPSUM_AW)
    ) u_ipsum_mem (
        .clk     (clk),
        .wr_en   (ipsum_wr_en),
        .wr_addr (wr_addr[IPSUM_AW-1:0]),
        .wr_data (wr_data[31:0]),
        .rd_en   (ipsum_stream_rd_en || ipsum_host_rd_en),
        .rd_addr (ipsum_rd_addr),
        .rd_data (ipsum_rdata)
    );

    GLB_SRAM32 #(
        .DEPTH  (OPSUM_DEPTH),
        .ADDR_W (OPSUM_AW)
    ) u_opsum_mem (
        .clk     (clk),
        .wr_en   (opsum_wr_en),
        .wr_addr (opsum_wr_addr),
        .wr_data (opsum_wr_data),
        .rd_en   (opsum_host_rd_en),
        .rd_addr (opsum_rd_addr),
        .rd_data (opsum_rdata)
    );

    always_comb begin
        ifmap_ptr_d   = ifmap_ptr_q;
        ifmap_left_d  = ifmap_left_q;
        ifmap_valid_d = ifmap_valid_q;
        ifmap_pending_d = 1'b0;
        ifmap_data_d  = ifmap_data_q;
        ifmap_done    = 1'b0;

        if (start_ifmap && !ifmap_busy) begin
            ifmap_ptr_d   = ifmap_base;
            ifmap_left_d  = ifmap_len;
            ifmap_valid_d = 1'b0;
            ifmap_pending_d = 1'b0;
        end
        else begin
            if (ifmap_fire) begin
                ifmap_valid_d = 1'b0;
                if (ifmap_left_q == 0 && !ifmap_pending_q) begin
                    ifmap_done = 1'b1;
                end
            end
            if (ifmap_pending_q) begin
                ifmap_data_d  = ifmap_rdata;
                ifmap_valid_d = 1'b1;
            end
            if (ifmap_stream_rd_en) begin
                ifmap_ptr_d   = ifmap_ptr_q + 1'b1;
                ifmap_left_d  = ifmap_left_q - 1'b1;
                ifmap_pending_d = 1'b1;
            end
        end
    end

    always_comb begin
        filter_ptr_d   = filter_ptr_q;
        filter_left_d  = filter_left_q;
        filter_valid_d = filter_valid_q;
        filter_pending_d = 1'b0;
        filter_data_d  = filter_data_q;
        filter_done    = 1'b0;

        if (start_filter && !filter_busy) begin
            filter_ptr_d   = filter_base;
            filter_left_d  = filter_len;
            filter_valid_d = 1'b0;
            filter_pending_d = 1'b0;
        end
        else begin
            if (filter_fire) begin
                filter_valid_d = 1'b0;
                if (filter_left_q == 0 && !filter_pending_q) begin
                    filter_done = 1'b1;
                end
            end
            if (filter_pending_q) begin
                filter_data_d  = filter_rdata;
                filter_valid_d = 1'b1;
            end
            if (filter_stream_rd_en) begin
                filter_ptr_d   = filter_ptr_q + 1'b1;
                filter_left_d  = filter_left_q - 1'b1;
                filter_pending_d = 1'b1;
            end
        end
    end

    always_comb begin
        ipsum_ptr_d   = ipsum_ptr_q;
        ipsum_left_d  = ipsum_left_q;
        ipsum_valid_d = ipsum_valid_q;
        ipsum_pending_d = 1'b0;
        ipsum_data_d  = ipsum_data_q;
        ipsum_done    = 1'b0;

        if (start_ipsum && !ipsum_busy) begin
            ipsum_ptr_d   = ipsum_base;
            ipsum_left_d  = ipsum_len;
            ipsum_valid_d = 1'b0;
            ipsum_pending_d = 1'b0;
        end
        else begin
            if (ipsum_fire) begin
                ipsum_valid_d = 1'b0;
                if (ipsum_left_q == 0 && !ipsum_pending_q) begin
                    ipsum_done = 1'b1;
                end
            end
            if (ipsum_pending_q) begin
                ipsum_data_d  = ipsum_rdata;
                ipsum_valid_d = 1'b1;
            end
            if (ipsum_stream_rd_en) begin
                ipsum_ptr_d   = ipsum_ptr_q + 1'b1;
                ipsum_left_d  = ipsum_left_q - 1'b1;
                ipsum_pending_d = 1'b1;
            end
        end
    end

    always_comb begin
        opsum_wr_ptr_d = opsum_wr_ptr_q;
        opsum_left_d   = opsum_left_q;
        opsum_count_d  = opsum_count_q;
        opsum_cap_en_d = opsum_cap_en_q;
        opsum_done     = 1'b0;

        if (start_capture_opsum && !opsum_cap_en_q) begin
            opsum_wr_ptr_d = opsum_base;
            opsum_left_d   = opsum_len;
            opsum_count_d  = '0;
            opsum_cap_en_d = (opsum_len != 0);
        end
        else begin
            if (opsum_fire) begin
                opsum_wr_ptr_d = opsum_wr_ptr_q + 1'b1;
                opsum_left_d   = opsum_left_q - 1'b1;
                opsum_count_d  = opsum_count_q + 1'b1;
            end

            if (opsum_cap_en_q && ((opsum_fire && (opsum_left_q == 1)) || opsum_capture_stop)) begin
                opsum_cap_en_d = 1'b0;
                opsum_done     = 1'b1;
            end
        end
    end

    always_comb begin
        rd_data = '0;
        if (host_rd_pending_q) begin
            unique case (mem_sel_t'(host_rd_sel_q))
                SEL_IFMAP:  rd_data = ifmap_rdata;
                SEL_FILTER: rd_data = filter_rdata;
                SEL_IPSUM:  rd_data = ipsum_rdata;
                SEL_OPSUM:  rd_data = opsum_rdata;
                default:    rd_data = '0;
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ifmap_ptr_q       <= '0;
            filter_ptr_q      <= '0;
            ipsum_ptr_q       <= '0;

            ifmap_left_q      <= '0;
            filter_left_q     <= '0;
            ipsum_left_q      <= '0;

            ifmap_valid_q     <= 1'b0;
            filter_valid_q    <= 1'b0;
            ipsum_valid_q     <= 1'b0;
            ifmap_pending_q   <= 1'b0;
            filter_pending_q  <= 1'b0;
            ipsum_pending_q   <= 1'b0;
            ifmap_data_q      <= '0;
            filter_data_q     <= '0;
            ipsum_data_q      <= '0;

            opsum_wr_ptr_q    <= '0;
            opsum_left_q      <= '0;
            opsum_count_q     <= '0;
            opsum_cap_en_q    <= 1'b0;

            host_rd_pending_q <= 1'b0;
            host_rd_sel_q     <= '0;
        end
        else begin
            ifmap_ptr_q       <= ifmap_ptr_d;
            filter_ptr_q      <= filter_ptr_d;
            ipsum_ptr_q       <= ipsum_ptr_d;

            ifmap_left_q      <= ifmap_left_d;
            filter_left_q     <= filter_left_d;
            ipsum_left_q      <= ipsum_left_d;

            ifmap_valid_q     <= ifmap_valid_d;
            filter_valid_q    <= filter_valid_d;
            ipsum_valid_q     <= ipsum_valid_d;
            ifmap_pending_q   <= ifmap_pending_d;
            filter_pending_q  <= filter_pending_d;
            ipsum_pending_q   <= ipsum_pending_d;
            ifmap_data_q      <= ifmap_data_d;
            filter_data_q     <= filter_data_d;
            ipsum_data_q      <= ipsum_data_d;

            opsum_wr_ptr_q    <= opsum_wr_ptr_d;
            opsum_left_q      <= opsum_left_d;
            opsum_count_q     <= opsum_count_d;
            opsum_cap_en_q    <= opsum_cap_en_d;

            host_rd_pending_q <= ifmap_host_rd_en || filter_host_rd_en ||
                                 ipsum_host_rd_en || opsum_host_rd_en;
            host_rd_sel_q     <= rd_sel;
        end
    end

    assign opsum_busy = opsum_cap_en_q;
    assign opsum_captured_count = opsum_count_q;

endmodule
