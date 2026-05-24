`ifndef TOP_WITH_GLB_AOC_SV
`define TOP_WITH_GLB_AOC_SV

`include "src/GLB/GLB.sv"
`include "src/Sparse/BitmapBuffer.sv"
`include "src/Sparse/SparseDecoder.sv"
`include "src/Sparse/SparseEncoder.sv"
`include "src/PE_array/PE_array.sv"

module top_with_glb #(
    parameter int NUMS_PE_ROW = `NUMS_PE_ROW,
    parameter int NUMS_PE_COL = `NUMS_PE_COL,
    parameter int XID_BITS    = `XID_BITS,
    parameter int YID_BITS    = `YID_BITS,
    parameter int DATA_SIZE   = `DATA_BITS,
    parameter int CONFIG_SIZE = `CONFIG_SIZE,

    parameter int PE_ROW_PER_CLUSTER = 2,
    parameter int PE_COL_PER_CLUSTER = 2,

    parameter int IFMAP_DEPTH  = 4096,
    parameter int FILTER_DEPTH = 4096,
    parameter int IPSUM_DEPTH  = 4096,
    parameter int OPSUM_DEPTH  = 4096,

    parameter int IFMAP_AW  = (IFMAP_DEPTH  <= 1) ? 1 : $clog2(IFMAP_DEPTH),
    parameter int FILTER_AW = (FILTER_DEPTH <= 1) ? 1 : $clog2(FILTER_DEPTH),
    parameter int IPSUM_AW  = (IPSUM_DEPTH  <= 1) ? 1 : $clog2(IPSUM_DEPTH),
    parameter int OPSUM_AW  = (OPSUM_DEPTH  <= 1) ? 1 : $clog2(OPSUM_DEPTH),
    parameter int ADDR_W    = ((IFMAP_AW > FILTER_AW) ?
                              ((IFMAP_AW > IPSUM_AW) ?
                              ((IFMAP_AW > OPSUM_AW) ? IFMAP_AW : OPSUM_AW) :
                              ((IPSUM_AW > OPSUM_AW) ? IPSUM_AW : OPSUM_AW)) :
                              ((FILTER_AW > IPSUM_AW) ?
                              ((FILTER_AW > OPSUM_AW) ? FILTER_AW : OPSUM_AW) :
                              ((IPSUM_AW > OPSUM_AW) ? IPSUM_AW : OPSUM_AW))),

    // Sparse bitmap settings.
    parameter int SPARSE_BLOCK_SIZE = 8,
    parameter int SPARSE_COUNT_W    = (SPARSE_BLOCK_SIZE <= 1) ? 1 : $clog2(SPARSE_BLOCK_SIZE + 1),

    // Bitmap depths count bitmap entries, not data words.
    parameter int IFMAP_BMAP_DEPTH  = (IFMAP_DEPTH  + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,
    parameter int FILTER_BMAP_DEPTH = (FILTER_DEPTH + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,
    parameter int IPSUM_BMAP_DEPTH  = (IPSUM_DEPTH  + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,
    parameter int OPSUM_BMAP_DEPTH  = (OPSUM_DEPTH  + SPARSE_BLOCK_SIZE - 1) / SPARSE_BLOCK_SIZE,

    parameter int IFMAP_BMAP_AW  = (IFMAP_BMAP_DEPTH  <= 1) ? 1 : $clog2(IFMAP_BMAP_DEPTH),
    parameter int FILTER_BMAP_AW = (FILTER_BMAP_DEPTH <= 1) ? 1 : $clog2(FILTER_BMAP_DEPTH),
    parameter int IPSUM_BMAP_AW  = (IPSUM_BMAP_DEPTH  <= 1) ? 1 : $clog2(IPSUM_BMAP_DEPTH),
    parameter int OPSUM_BMAP_AW  = (OPSUM_BMAP_DEPTH  <= 1) ? 1 : $clog2(OPSUM_BMAP_DEPTH),
    parameter int BMAP_ADDR_W    = ((IFMAP_BMAP_AW > FILTER_BMAP_AW) ?
                                  ((IFMAP_BMAP_AW > IPSUM_BMAP_AW) ?
                                  ((IFMAP_BMAP_AW > OPSUM_BMAP_AW) ? IFMAP_BMAP_AW : OPSUM_BMAP_AW) :
                                  ((IPSUM_BMAP_AW > OPSUM_BMAP_AW) ? IPSUM_BMAP_AW : OPSUM_BMAP_AW)) :
                                  ((FILTER_BMAP_AW > IPSUM_BMAP_AW) ?
                                  ((FILTER_BMAP_AW > OPSUM_BMAP_AW) ? FILTER_BMAP_AW : OPSUM_BMAP_AW) :
                                  ((IPSUM_BMAP_AW > OPSUM_BMAP_AW) ? IPSUM_BMAP_AW : OPSUM_BMAP_AW)))
)(
    input  logic clk,
    input  logic rst,

    // ------------------------------------------------------------------
    // GLB host data access. Data stored here is compressed data.
    // wr_sel / rd_sel: 0 ifmap, 1 filter, 2 ipsum, 3 opsum.
    // ------------------------------------------------------------------
    input  logic                 wr_en,
    input  logic [1:0]           wr_sel,
    input  logic [ADDR_W-1:0]    wr_addr,
    input  logic [DATA_SIZE-1:0] wr_data,

    input  logic                 rd_en,
    input  logic [1:0]           rd_sel,
    input  logic [ADDR_W-1:0]    rd_addr,
    output logic [DATA_SIZE-1:0] rd_data,

    // ------------------------------------------------------------------
    // BitmapBuffer host access. Bitmap data is stored separately.
    // bitmap_*_sel: 0 ifmap, 1 filter, 2 ipsum, 3 opsum.
    // ------------------------------------------------------------------
    input  logic                       bitmap_wr_en,
    input  logic [1:0]                 bitmap_wr_sel,
    input  logic [BMAP_ADDR_W-1:0]     bitmap_wr_addr,
    input  logic [SPARSE_BLOCK_SIZE-1:0] bitmap_wr_data,
    input  logic [SPARSE_COUNT_W-1:0]  bitmap_wr_nz_count,

    input  logic                       bitmap_rd_en,
    input  logic [1:0]                 bitmap_rd_sel,
    input  logic [BMAP_ADDR_W-1:0]     bitmap_rd_addr,
    output logic [SPARSE_BLOCK_SIZE-1:0] bitmap_rd_data,
    output logic [SPARSE_COUNT_W-1:0]  bitmap_rd_nz_count,

    // ------------------------------------------------------------------
    // Compressed input streams from GLB to SparseDecoder.
    // *_len is number of compressed non-zero words in GLB.
    // ------------------------------------------------------------------
    input  logic                start_ifmap,
    input  logic [IFMAP_AW-1:0] ifmap_base,
    input  logic [IFMAP_AW:0]   ifmap_len,
    output logic                ifmap_busy,
    output logic                ifmap_done,

    input  logic                 start_filter,
    input  logic [FILTER_AW-1:0] filter_base,
    input  logic [FILTER_AW:0]   filter_len,
    output logic                 filter_busy,
    output logic                 filter_done,

    input  logic                start_ipsum,
    input  logic [IPSUM_AW-1:0] ipsum_base,
    input  logic [IPSUM_AW:0]   ipsum_len,
    output logic                ipsum_busy,
    output logic                ipsum_done,

    // ------------------------------------------------------------------
    // Bitmap streams from BitmapBuffer to SparseDecoder.
    // *_bitmap_len is number of bitmap entries / blocks.
    // Start this at the same time as the matching compressed GLB stream.
    // ------------------------------------------------------------------
    input  logic                       start_ifmap_bitmap,
    input  logic [IFMAP_BMAP_AW-1:0]   ifmap_bitmap_base,
    input  logic [IFMAP_BMAP_AW:0]     ifmap_bitmap_len,
    output logic                       ifmap_bitmap_busy,
    output logic                       ifmap_bitmap_done,

    input  logic                       start_filter_bitmap,
    input  logic [FILTER_BMAP_AW-1:0]  filter_bitmap_base,
    input  logic [FILTER_BMAP_AW:0]    filter_bitmap_len,
    output logic                       filter_bitmap_busy,
    output logic                       filter_bitmap_done,

    input  logic                       start_ipsum_bitmap,
    input  logic [IPSUM_BMAP_AW-1:0]   ipsum_bitmap_base,
    input  logic [IPSUM_BMAP_AW:0]     ipsum_bitmap_len,
    output logic                       ipsum_bitmap_busy,
    output logic                       ipsum_bitmap_done,

    // ------------------------------------------------------------------
    // Opsum compression path: PE_array dense opsum -> Encoder -> GLB + bitmap.
    // start_encode_opsum consumes opsum_dense_len dense output words.
    // start_capture_opsum stores the encoder compressed words into GLB opsum_mem.
    // start_capture_opsum_bitmap stores encoder bitmap metadata into BitmapBuffer.
    // These three start pulses should normally be asserted together.
    // ------------------------------------------------------------------
    input  logic                start_encode_opsum,
    input  logic [OPSUM_AW:0]   opsum_dense_len,
    output logic                opsum_encode_busy,
    output logic                opsum_encode_done,
    output logic [OPSUM_AW:0]   opsum_encoded_dense_count,
    output logic [OPSUM_AW:0]   opsum_encoded_cmp_count,
    output logic [OPSUM_AW:0]   opsum_encoded_bitmap_count,

    input  logic                start_capture_opsum,
    input  logic [OPSUM_AW-1:0] opsum_base,
    input  logic [OPSUM_AW:0]   opsum_len,
    output logic [OPSUM_AW:0]   opsum_captured_count,
    output logic                opsum_busy,
    output logic                opsum_done,

    input  logic                       start_capture_opsum_bitmap,
    input  logic [OPSUM_BMAP_AW-1:0]   opsum_bitmap_base,
    input  logic [OPSUM_BMAP_AW:0]     opsum_bitmap_len,
    output logic                       opsum_bitmap_busy,
    output logic                       opsum_bitmap_done,

    // ------------------------------------------------------------------
    // PE_array configuration.
    // ------------------------------------------------------------------
    input  logic set_XID,
    input  logic [XID_BITS-1:0] ifmap_XID_scan_in,
    input  logic [XID_BITS-1:0] filter_XID_scan_in,
    input  logic [XID_BITS-1:0] ipsum_XID_scan_in,
    input  logic [XID_BITS-1:0] opsum_XID_scan_in,

    input  logic set_YID,
    input  logic [YID_BITS-1:0] ifmap_YID_scan_in,
    input  logic [YID_BITS-1:0] filter_YID_scan_in,
    input  logic [YID_BITS-1:0] ipsum_YID_scan_in,
    input  logic [YID_BITS-1:0] opsum_YID_scan_in,

    input  logic                   set_LN,
    input  logic [NUMS_PE_ROW-2:0] LN_config_in,

    input  logic [NUMS_PE_ROW*NUMS_PE_COL-1:0] PE_en,
    input  logic [CONFIG_SIZE-1:0]              PE_config,

    input  logic [XID_BITS-1:0] ifmap_tag_X,
    input  logic [YID_BITS-1:0] ifmap_tag_Y,
    input  logic [XID_BITS-1:0] filter_tag_X,
    input  logic [YID_BITS-1:0] filter_tag_Y,
    input  logic [XID_BITS-1:0] ipsum_tag_X,
    input  logic [YID_BITS-1:0] ipsum_tag_Y,
    input  logic [XID_BITS-1:0] opsum_tag_X,
    input  logic [YID_BITS-1:0] opsum_tag_Y,

    // Debug: compressed GLB side and dense PE side.
    output logic                 GLB_ifmap_valid_dbg,
    output logic                 GLB_ifmap_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_ifmap_data_dbg,
    output logic                 PE_ifmap_valid_dbg,
    output logic                 PE_ifmap_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_ifmap_data_dbg,

    output logic                 GLB_filter_valid_dbg,
    output logic                 GLB_filter_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_filter_data_dbg,
    output logic                 PE_filter_valid_dbg,
    output logic                 PE_filter_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_filter_data_dbg,

    output logic                 GLB_ipsum_valid_dbg,
    output logic                 GLB_ipsum_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_ipsum_data_dbg,
    output logic                 PE_ipsum_valid_dbg,
    output logic                 PE_ipsum_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_ipsum_data_dbg,

    output logic                 PE_opsum_valid_dbg,
    output logic                 PE_opsum_ready_dbg,
    output logic [DATA_SIZE-1:0] PE_opsum_data_dbg,
    output logic                 GLB_opsum_valid_dbg,
    output logic                 GLB_opsum_ready_dbg,
    output logic [DATA_SIZE-1:0] GLB_opsum_data_dbg
);

    localparam logic [1:0] SEL_IFMAP  = 2'd0;
    localparam logic [1:0] SEL_FILTER = 2'd1;
    localparam logic [1:0] SEL_IPSUM  = 2'd2;
    localparam logic [1:0] SEL_OPSUM  = 2'd3;

    logic GLB_ifmap_valid;
    logic GLB_ifmap_ready;
    logic [DATA_SIZE-1:0] GLB_ifmap_data_in;

    logic GLB_filter_valid;
    logic GLB_filter_ready;
    logic [DATA_SIZE-1:0] GLB_filter_data_in;

    logic GLB_ipsum_valid;
    logic GLB_ipsum_ready;
    logic [DATA_SIZE-1:0] GLB_ipsum_data_in;

    logic PE_ifmap_valid;
    logic PE_ifmap_ready;
    logic [DATA_SIZE-1:0] PE_ifmap_data;

    logic PE_filter_valid;
    logic PE_filter_ready;
    logic [DATA_SIZE-1:0] PE_filter_data;

    logic PE_ipsum_valid;
    logic PE_ipsum_ready;
    logic [DATA_SIZE-1:0] PE_ipsum_data;

    logic PE_opsum_valid;
    logic PE_opsum_ready;
    logic [DATA_SIZE-1:0] PE_opsum_data;

    logic enc_opsum_valid;
    logic enc_opsum_ready;
    logic [DATA_SIZE-1:0] enc_opsum_data;

    logic enc_bitmap_valid;
    logic enc_bitmap_ready;
    logic [SPARSE_BLOCK_SIZE-1:0] enc_bitmap;
    logic [SPARSE_COUNT_W-1:0] enc_nz_count;

    logic ifmap_bmap_valid, ifmap_bmap_ready;
    logic [SPARSE_BLOCK_SIZE-1:0] ifmap_bmap_data;
    logic [SPARSE_COUNT_W-1:0] ifmap_bmap_nz;

    logic filter_bmap_valid, filter_bmap_ready;
    logic [SPARSE_BLOCK_SIZE-1:0] filter_bmap_data;
    logic [SPARSE_COUNT_W-1:0] filter_bmap_nz;

    logic ipsum_bmap_valid, ipsum_bmap_ready;
    logic [SPARSE_BLOCK_SIZE-1:0] ipsum_bmap_data;
    logic [SPARSE_COUNT_W-1:0] ipsum_bmap_nz;

    logic [SPARSE_BLOCK_SIZE-1:0] ifmap_bmap_rd_data, filter_bmap_rd_data, ipsum_bmap_rd_data, opsum_bmap_rd_data;
    logic [SPARSE_COUNT_W-1:0] ifmap_bmap_rd_nz, filter_bmap_rd_nz, ipsum_bmap_rd_nz, opsum_bmap_rd_nz;

    // ------------------------------------------------------------------
    // GLB stores compressed data.
    // ------------------------------------------------------------------
    GLB #(
        .DATA_SIZE    (DATA_SIZE),
        .IFMAP_DEPTH  (IFMAP_DEPTH),
        .FILTER_DEPTH (FILTER_DEPTH),
        .IPSUM_DEPTH  (IPSUM_DEPTH),
        .OPSUM_DEPTH  (OPSUM_DEPTH)
    ) u_glb (
        .clk                 (clk),
        .rst                 (rst),
        .wr_en               (wr_en),
        .wr_sel              (wr_sel),
        .wr_addr             (wr_addr),
        .wr_data             (wr_data),
        .rd_en               (rd_en),
        .rd_sel              (rd_sel),
        .rd_addr             (rd_addr),
        .rd_data             (rd_data),

        .start_ifmap         (start_ifmap),
        .ifmap_base          (ifmap_base),
        .ifmap_len           (ifmap_len),
        .ifmap_busy          (ifmap_busy),
        .ifmap_done          (ifmap_done),

        .start_filter        (start_filter),
        .filter_base         (filter_base),
        .filter_len          (filter_len),
        .filter_busy         (filter_busy),
        .filter_done         (filter_done),

        .start_ipsum         (start_ipsum),
        .ipsum_base          (ipsum_base),
        .ipsum_len           (ipsum_len),
        .ipsum_busy          (ipsum_busy),
        .ipsum_done          (ipsum_done),

        .start_capture_opsum (start_capture_opsum),
        .opsum_base          (opsum_base),
        .opsum_len           (opsum_len),
        .opsum_capture_stop  (opsum_encode_done),
        .opsum_captured_count(opsum_captured_count),
        .opsum_busy          (opsum_busy),
        .opsum_done          (opsum_done),

        .GLB_ifmap_valid     (GLB_ifmap_valid),
        .GLB_ifmap_ready     (GLB_ifmap_ready),
        .GLB_ifmap_data_in   (GLB_ifmap_data_in),
        .GLB_filter_valid    (GLB_filter_valid),
        .GLB_filter_ready    (GLB_filter_ready),
        .GLB_filter_data_in  (GLB_filter_data_in),
        .GLB_ipsum_valid     (GLB_ipsum_valid),
        .GLB_ipsum_ready     (GLB_ipsum_ready),
        .GLB_ipsum_data_in   (GLB_ipsum_data_in),
        .GLB_opsum_valid     (enc_opsum_valid),
        .GLB_opsum_ready     (enc_opsum_ready),
        .GLB_data_out        (enc_opsum_data)
    );

    // ------------------------------------------------------------------
    // Bitmap buffers.
    // ------------------------------------------------------------------
    BitmapBuffer #(
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE),
        .DEPTH      (IFMAP_BMAP_DEPTH)
    ) u_ifmap_bitmap (
        .clk                 (clk),
        .rst                 (rst),
        .host_wr_en          (bitmap_wr_en && (bitmap_wr_sel == SEL_IFMAP)),
        .host_wr_addr        (bitmap_wr_addr[IFMAP_BMAP_AW-1:0]),
        .host_bitmap_wdata   (bitmap_wr_data),
        .host_nz_count_wdata (bitmap_wr_nz_count),
        .host_rd_en          (bitmap_rd_en && (bitmap_rd_sel == SEL_IFMAP)),
        .host_rd_addr        (bitmap_rd_addr[IFMAP_BMAP_AW-1:0]),
        .host_bitmap_rdata   (ifmap_bmap_rd_data),
        .host_nz_count_rdata (ifmap_bmap_rd_nz),
        .start_capture       (1'b0),
        .capture_base        ('0),
        .capture_len         ('0),
        .capture_busy        (),
        .capture_done        (),
        .enc_bitmap_i        ('0),
        .enc_nz_count_i      ('0),
        .enc_valid_i         (1'b0),
        .enc_ready_o         (),
        .start_stream        (start_ifmap_bitmap),
        .stream_base         (ifmap_bitmap_base),
        .stream_len          (ifmap_bitmap_len),
        .stream_busy         (ifmap_bitmap_busy),
        .stream_done         (ifmap_bitmap_done),
        .dec_bitmap_o        (ifmap_bmap_data),
        .dec_nz_count_o      (ifmap_bmap_nz),
        .dec_valid_o         (ifmap_bmap_valid),
        .dec_ready_i         (ifmap_bmap_ready)
    );

    BitmapBuffer #(
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE),
        .DEPTH      (FILTER_BMAP_DEPTH)
    ) u_filter_bitmap (
        .clk                 (clk),
        .rst                 (rst),
        .host_wr_en          (bitmap_wr_en && (bitmap_wr_sel == SEL_FILTER)),
        .host_wr_addr        (bitmap_wr_addr[FILTER_BMAP_AW-1:0]),
        .host_bitmap_wdata   (bitmap_wr_data),
        .host_nz_count_wdata (bitmap_wr_nz_count),
        .host_rd_en          (bitmap_rd_en && (bitmap_rd_sel == SEL_FILTER)),
        .host_rd_addr        (bitmap_rd_addr[FILTER_BMAP_AW-1:0]),
        .host_bitmap_rdata   (filter_bmap_rd_data),
        .host_nz_count_rdata (filter_bmap_rd_nz),
        .start_capture       (1'b0),
        .capture_base        ('0),
        .capture_len         ('0),
        .capture_busy        (),
        .capture_done        (),
        .enc_bitmap_i        ('0),
        .enc_nz_count_i      ('0),
        .enc_valid_i         (1'b0),
        .enc_ready_o         (),
        .start_stream        (start_filter_bitmap),
        .stream_base         (filter_bitmap_base),
        .stream_len          (filter_bitmap_len),
        .stream_busy         (filter_bitmap_busy),
        .stream_done         (filter_bitmap_done),
        .dec_bitmap_o        (filter_bmap_data),
        .dec_nz_count_o      (filter_bmap_nz),
        .dec_valid_o         (filter_bmap_valid),
        .dec_ready_i         (filter_bmap_ready)
    );

    BitmapBuffer #(
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE),
        .DEPTH      (IPSUM_BMAP_DEPTH)
    ) u_ipsum_bitmap (
        .clk                 (clk),
        .rst                 (rst),
        .host_wr_en          (bitmap_wr_en && (bitmap_wr_sel == SEL_IPSUM)),
        .host_wr_addr        (bitmap_wr_addr[IPSUM_BMAP_AW-1:0]),
        .host_bitmap_wdata   (bitmap_wr_data),
        .host_nz_count_wdata (bitmap_wr_nz_count),
        .host_rd_en          (bitmap_rd_en && (bitmap_rd_sel == SEL_IPSUM)),
        .host_rd_addr        (bitmap_rd_addr[IPSUM_BMAP_AW-1:0]),
        .host_bitmap_rdata   (ipsum_bmap_rd_data),
        .host_nz_count_rdata (ipsum_bmap_rd_nz),
        .start_capture       (1'b0),
        .capture_base        ('0),
        .capture_len         ('0),
        .capture_busy        (),
        .capture_done        (),
        .enc_bitmap_i        ('0),
        .enc_nz_count_i      ('0),
        .enc_valid_i         (1'b0),
        .enc_ready_o         (),
        .start_stream        (start_ipsum_bitmap),
        .stream_base         (ipsum_bitmap_base),
        .stream_len          (ipsum_bitmap_len),
        .stream_busy         (ipsum_bitmap_busy),
        .stream_done         (ipsum_bitmap_done),
        .dec_bitmap_o        (ipsum_bmap_data),
        .dec_nz_count_o      (ipsum_bmap_nz),
        .dec_valid_o         (ipsum_bmap_valid),
        .dec_ready_i         (ipsum_bmap_ready)
    );

    BitmapBuffer #(
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE),
        .DEPTH      (OPSUM_BMAP_DEPTH)
    ) u_opsum_bitmap (
        .clk                 (clk),
        .rst                 (rst),
        .host_wr_en          (bitmap_wr_en && (bitmap_wr_sel == SEL_OPSUM)),
        .host_wr_addr        (bitmap_wr_addr[OPSUM_BMAP_AW-1:0]),
        .host_bitmap_wdata   (bitmap_wr_data),
        .host_nz_count_wdata (bitmap_wr_nz_count),
        .host_rd_en          (bitmap_rd_en && (bitmap_rd_sel == SEL_OPSUM)),
        .host_rd_addr        (bitmap_rd_addr[OPSUM_BMAP_AW-1:0]),
        .host_bitmap_rdata   (opsum_bmap_rd_data),
        .host_nz_count_rdata (opsum_bmap_rd_nz),
        .start_capture       (start_capture_opsum_bitmap),
        .capture_base        (opsum_bitmap_base),
        .capture_len         (opsum_bitmap_len),
        .capture_busy        (opsum_bitmap_busy),
        .capture_done        (opsum_bitmap_done),
        .enc_bitmap_i        (enc_bitmap),
        .enc_nz_count_i      (enc_nz_count),
        .enc_valid_i         (enc_bitmap_valid),
        .enc_ready_o         (enc_bitmap_ready),
        .start_stream        (1'b0),
        .stream_base         ('0),
        .stream_len          ('0),
        .stream_busy         (),
        .stream_done         (),
        .dec_bitmap_o        (),
        .dec_nz_count_o      (),
        .dec_valid_o         (),
        .dec_ready_i         (1'b0)
    );

    always_comb begin
        bitmap_rd_data     = '0;
        bitmap_rd_nz_count = '0;
        unique case (bitmap_rd_sel)
            SEL_IFMAP: begin
                bitmap_rd_data     = ifmap_bmap_rd_data;
                bitmap_rd_nz_count = ifmap_bmap_rd_nz;
            end
            SEL_FILTER: begin
                bitmap_rd_data     = filter_bmap_rd_data;
                bitmap_rd_nz_count = filter_bmap_rd_nz;
            end
            SEL_IPSUM: begin
                bitmap_rd_data     = ipsum_bmap_rd_data;
                bitmap_rd_nz_count = ipsum_bmap_rd_nz;
            end
            SEL_OPSUM: begin
                bitmap_rd_data     = opsum_bmap_rd_data;
                bitmap_rd_nz_count = opsum_bmap_rd_nz;
            end
            default: begin
                bitmap_rd_data     = '0;
                bitmap_rd_nz_count = '0;
            end
        endcase
    end

    // ------------------------------------------------------------------
    // Decoders: GLB compressed stream + bitmap stream -> PE dense stream.
    // ------------------------------------------------------------------
    SparseDecoder #(
        .DATA_SIZE  (DATA_SIZE),
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE)
    ) u_ifmap_decoder (
        .clk            (clk),
        .rst            (rst),
        .bitmap_i       (ifmap_bmap_data),
        .nz_count_i     (ifmap_bmap_nz),
        .bitmap_valid_i (ifmap_bmap_valid),
        .bitmap_ready_o (ifmap_bmap_ready),
        .cmp_data_i     (GLB_ifmap_data_in),
        .cmp_valid_i    (GLB_ifmap_valid),
        .cmp_ready_o    (GLB_ifmap_ready),
        .dense_data_o   (PE_ifmap_data),
        .dense_valid_o  (PE_ifmap_valid),
        .dense_ready_i  (PE_ifmap_ready)
    );

    SparseDecoder #(
        .DATA_SIZE  (DATA_SIZE),
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE)
    ) u_filter_decoder (
        .clk            (clk),
        .rst            (rst),
        .bitmap_i       (filter_bmap_data),
        .nz_count_i     (filter_bmap_nz),
        .bitmap_valid_i (filter_bmap_valid),
        .bitmap_ready_o (filter_bmap_ready),
        .cmp_data_i     (GLB_filter_data_in),
        .cmp_valid_i    (GLB_filter_valid),
        .cmp_ready_o    (GLB_filter_ready),
        .dense_data_o   (PE_filter_data),
        .dense_valid_o  (PE_filter_valid),
        .dense_ready_i  (PE_filter_ready)
    );

    SparseDecoder #(
        .DATA_SIZE  (DATA_SIZE),
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE)
    ) u_ipsum_decoder (
        .clk            (clk),
        .rst            (rst),
        .bitmap_i       (ipsum_bmap_data),
        .nz_count_i     (ipsum_bmap_nz),
        .bitmap_valid_i (ipsum_bmap_valid),
        .bitmap_ready_o (ipsum_bmap_ready),
        .cmp_data_i     (GLB_ipsum_data_in),
        .cmp_valid_i    (GLB_ipsum_valid),
        .cmp_ready_o    (GLB_ipsum_ready),
        .dense_data_o   (PE_ipsum_data),
        .dense_valid_o  (PE_ipsum_valid),
        .dense_ready_i  (PE_ipsum_ready)
    );

    // ------------------------------------------------------------------
    // PE array sees dense data. It does not need to understand bitmap format.
    // ------------------------------------------------------------------
    PE_array #(
        .NUMS_PE_ROW        (NUMS_PE_ROW),
        .NUMS_PE_COL        (NUMS_PE_COL),
        .XID_BITS           (XID_BITS),
        .YID_BITS           (YID_BITS),
        .DATA_SIZE          (DATA_SIZE),
        .CONFIG_SIZE        (CONFIG_SIZE),
        .PE_ROW_PER_CLUSTER (PE_ROW_PER_CLUSTER),
        .PE_COL_PER_CLUSTER (PE_COL_PER_CLUSTER)
    ) u_pe_array (
        .clk                (clk),
        .rst                (rst),
        .set_XID            (set_XID),
        .ifmap_XID_scan_in  (ifmap_XID_scan_in),
        .filter_XID_scan_in (filter_XID_scan_in),
        .ipsum_XID_scan_in  (ipsum_XID_scan_in),
        .opsum_XID_scan_in  (opsum_XID_scan_in),
        .set_YID            (set_YID),
        .ifmap_YID_scan_in  (ifmap_YID_scan_in),
        .filter_YID_scan_in (filter_YID_scan_in),
        .ipsum_YID_scan_in  (ipsum_YID_scan_in),
        .opsum_YID_scan_in  (opsum_YID_scan_in),
        .set_LN             (set_LN),
        .LN_config_in       (LN_config_in),
        .PE_en              (PE_en),
        .PE_config          (PE_config),
        .ifmap_tag_X        (ifmap_tag_X),
        .ifmap_tag_Y        (ifmap_tag_Y),
        .filter_tag_X       (filter_tag_X),
        .filter_tag_Y       (filter_tag_Y),
        .ipsum_tag_X        (ipsum_tag_X),
        .ipsum_tag_Y        (ipsum_tag_Y),
        .opsum_tag_X        (opsum_tag_X),
        .opsum_tag_Y        (opsum_tag_Y),
        .GLB_ifmap_valid    (PE_ifmap_valid),
        .GLB_ifmap_ready    (PE_ifmap_ready),
        .GLB_ifmap_data_in  (PE_ifmap_data),
        .GLB_filter_valid   (PE_filter_valid),
        .GLB_filter_ready   (PE_filter_ready),
        .GLB_filter_data_in (PE_filter_data),
        .GLB_ipsum_valid    (PE_ipsum_valid),
        .GLB_ipsum_ready    (PE_ipsum_ready),
        .GLB_ipsum_data_in  (PE_ipsum_data),
        .GLB_opsum_valid    (PE_opsum_valid),
        .GLB_opsum_ready    (PE_opsum_ready),
        .GLB_data_out       (PE_opsum_data)
    );

    // ------------------------------------------------------------------
    // Encoder: PE dense opsum -> compressed GLB data + opsum bitmap buffer.
    // ------------------------------------------------------------------
    SparseEncoder #(
        .DATA_SIZE  (DATA_SIZE),
        .BLOCK_SIZE (SPARSE_BLOCK_SIZE),
        .LEN_W      (OPSUM_AW + 1)
    ) u_opsum_encoder (
        .clk             (clk),
        .rst             (rst),
        .start_i         (start_encode_opsum),
        .dense_len_i     (opsum_dense_len),
        .busy_o          (opsum_encode_busy),
        .done_o          (opsum_encode_done),
        .dense_count_o   (opsum_encoded_dense_count),
        .cmp_count_o     (opsum_encoded_cmp_count),
        .bitmap_count_o  (opsum_encoded_bitmap_count),
        .dense_data_i    (PE_opsum_data),
        .dense_valid_i   (PE_opsum_valid),
        .dense_ready_o   (PE_opsum_ready),
        .bitmap_o        (enc_bitmap),
        .nz_count_o      (enc_nz_count),
        .bitmap_valid_o  (enc_bitmap_valid),
        .bitmap_ready_i  (enc_bitmap_ready),
        .cmp_data_o      (enc_opsum_data),
        .cmp_valid_o     (enc_opsum_valid),
        .cmp_ready_i     (enc_opsum_ready)
    );

    // ------------------------------------------------------------------
    // Debug output assignment.
    // ------------------------------------------------------------------
    assign GLB_ifmap_valid_dbg  = GLB_ifmap_valid;
    assign GLB_ifmap_ready_dbg  = GLB_ifmap_ready;
    assign GLB_ifmap_data_dbg   = GLB_ifmap_data_in;
    assign PE_ifmap_valid_dbg   = PE_ifmap_valid;
    assign PE_ifmap_ready_dbg   = PE_ifmap_ready;
    assign PE_ifmap_data_dbg    = PE_ifmap_data;

    assign GLB_filter_valid_dbg = GLB_filter_valid;
    assign GLB_filter_ready_dbg = GLB_filter_ready;
    assign GLB_filter_data_dbg  = GLB_filter_data_in;
    assign PE_filter_valid_dbg  = PE_filter_valid;
    assign PE_filter_ready_dbg  = PE_filter_ready;
    assign PE_filter_data_dbg   = PE_filter_data;

    assign GLB_ipsum_valid_dbg  = GLB_ipsum_valid;
    assign GLB_ipsum_ready_dbg  = GLB_ipsum_ready;
    assign GLB_ipsum_data_dbg   = GLB_ipsum_data_in;
    assign PE_ipsum_valid_dbg   = PE_ipsum_valid;
    assign PE_ipsum_ready_dbg   = PE_ipsum_ready;
    assign PE_ipsum_data_dbg    = PE_ipsum_data;

    assign PE_opsum_valid_dbg   = PE_opsum_valid;
    assign PE_opsum_ready_dbg   = PE_opsum_ready;
    assign PE_opsum_data_dbg    = PE_opsum_data;
    assign GLB_opsum_valid_dbg  = enc_opsum_valid;
    assign GLB_opsum_ready_dbg  = enc_opsum_ready;
    assign GLB_opsum_data_dbg   = enc_opsum_data;

endmodule

`endif // TOP_WITH_GLB_AOC_SV
