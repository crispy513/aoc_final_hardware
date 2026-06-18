//===========================================================================
// MODULE:        Singal PE in Eyeriss architecture
//
// FILE NAME:     PE.sv
// VERSION:       1.1
// DATE:          2026/4/26
// 
// CODE TYPE:     RTL model
//
// DESCRIPTION:   Do 1*3 convlution with data saved in inside spad by a MAC
//
// Revisions:     2026/04/26  Finish module with ring ifmap spad, clock 
//                            gating and MAC data gating
//
//                2026/05/26  The parameter settings have been modified to 
//                            conform to final project.
//===========================================================================
module PE #(
    parameter IFMAP_SIZE       = 8,    // Due to time constraints, these 
    parameter FILTER_SIZE      = 8,    // parameters were not used; we await 
    parameter PSUM_SIZE        = 32,   // optimization by someone who is 
    parameter IFMAP_SPAD_LEN   = 12,   // interested.
    parameter FILTER_SPAD_LEN  = 48,
    parameter OFMAP_SPAD_LEN   = 4,
    parameter IFMAP_INDEX_BIT  = 4,
    parameter FILTER_INDEX_BIT = 6,
    parameter OFMAP_INDEX_BIT  = 2,
    parameter OFMAP_COL_BIT    = 5
)(
    input               clk,           // Global clock, posedge trigger
    input               rst,           // Reset signal, active high
    input               PE_en,         // PE enable signal, active high
    input        [10:0] i_config,      // config signal, determine mode and
                                       // mapping parameter
    input        [31:0] ifmap,         // input ifmap pixels (32-bit here)
    input        [31:0] filter,        // input filter weights (32-bit here)
    input        [31:0] ipsum,         // input partial sum (32-bit here)
    input               ifmap_valid,   // ifmap valid signal for handshake
    input               filter_valid,  // filter valid signal for handshake
    input               ipsum_valid,   // partial sum valid signal for handshake
    input               opsum_ready,   // express output partial sum is getten
    output logic [31:0] opsum,         // partial sum output
    output logic        ifmap_ready,   // express ifmap pixel is getten
    output logic        filter_ready,  // express filter weight is getten
    output logic        ipsum_ready,   // express input partial sum is getten
    output logic        opsum_valid    // output partial sum valid signal
);

//===========================================================================
// Register and Parameter Defination
//===========================================================================
// Config register: Save mapping parameter
logic       mode;     // 0: CONV, 1: FC
logic [1:0] p_max;    // number of filters processed by a PE set, max p = 4
logic [1:0] q_max;    // number of channels processed by a PE set, max q = 4
logic [4:0] f_max;    // ofmap plane width, equal number of cal, max f = 16
localparam s_max = 2'd2;  // filter width, almost everyone is 3, we set 2 for
                          // easier logic

// Global counter: Counter for state transfer and spad mapping
logic [1:0] cnt_p;    // p counter, from 0 to p_max
logic [1:0] cnt_s;    // s counter, from 0 to filter width (3 at here) minus 1
logic [1:0] cnt_q;    // q counter, from 0 to q_max
logic [4:0] cnt_f;    // f counter, from 0 to f_max
logic [1:0] wr_ptr;   // head pointer for ifmap spad to be a ring FIFO

// PE inside spad: Save the data and use index to call for calculation
logic [31:0] filter_spad [0:3][0:2]; // p * s * q * 8-bit sapce
logic [31:0] ifmap_spad  [0:2];      // s * q * 8-bit space
logic [31:0] psum_spad   [0:3];      // p 32-bit space (1 opsum 32-bit)
//===========================================================================
// Control Path: State Defination
//===========================================================================
localparam IDLE             = 3'd0;  // IDLE
localparam LOAD_FILTER      = 3'd1;  // load filter weights
localparam LOAD_IFMAP_INIT  = 3'd2;  // load ifmap pixel first time, need to fill the spad
localparam LOAD_IFMAP_SHIFT = 3'd3;  // load new column ifmap pixel, after output opsum
localparam LOAD_IPSUM       = 3'd4;  // load ipsum to accumulate
localparam CALC             = 3'd5;  // MAC working, do 1 multiple and addition
localparam OUT_OPSUM        = 3'd6;  // output opsum and wait for next row ifmap or IDLE

logic [2:0] state, next_state;

//===========================================================================
// Datapath: Net Defination
//===========================================================================
// MAC's input/output signal
logic        [7:0]  ifmap_raw;  // Ifmap row be choosen to go to MAC
logic signed [7:0]  op_ifmap;   // Ifmap pixel after zero-point process
logic signed [7:0]  op_filter;  // Filter be chossen to go to MAC
logic signed [31:0] op_opsum;   // Opsum be chossen to go to MAC accumulate

// MAC's output (1 multiplier and 1 adder)
logic signed [15:0] mul_out;   // Multiplier output
logic signed [31:0] add_out;   // Adder output

//===========================================================================
// Control Path: Combinational block of control signal
//===========================================================================
// Ready signal output for each state situation, active high
assign filter_ready = (state == LOAD_FILTER);       // Ready to load weight
assign ifmap_ready  = (state == LOAD_IFMAP_INIT) 
                   || (state == LOAD_IFMAP_SHIFT);  // Ready to load ifmap
assign ipsum_ready  = (state == LOAD_IPSUM);        // Ready to load ipsum
assign opsum_valid  = (state == OUT_OPSUM);         // opsum is valid

// HandShake success condition: valid and ready is high at same cycle
wire hs_filter = filter_valid & filter_ready;  // filter load success
wire hs_ifmap  = ifmap_valid  & ifmap_ready;   // ifmap load success
wire hs_ipsum  = ipsum_valid  & ipsum_ready;   // ipsum load success
wire hs_opsum  = opsum_valid  & opsum_ready;   // opsum transmit success

// Enable signal for spad to load data, Clock Gating
// filer spad enable, filter state and make sure handshake
wire filter_en      = (state == LOAD_FILTER) && hs_filter;
// ifmap spad when first load data, init ifmap state and make sure handshake
wire ifmap_init_en  = (state == LOAD_IFMAP_INIT) && hs_ifmap;
// ifmap spad when load new row, shift ifmap state and make sure handshake
wire ifmap_shift_en = (state == LOAD_IFMAP_SHIFT) && hs_ifmap;
// input partial sum spad, input psum state and make sure handshake
wire ipsum_en       = (state == LOAD_IPSUM) && hs_ipsum;
// partial sum spad after accumulate, cal state and make sure handshake
wire psum_calc_en   = (state == CALC);

// Ring FIFO pointer: combine wr_ptr and cnt_s to be a real ifmap read index
wire [2:0] idx_sum  = {1'b0, wr_ptr} + {1'b0, cnt_s};
wire [2:0] over_idx = idx_sum - 3'd3;
wire [1:0] read_idx = (idx_sum >= 3'd3) ? over_idx[1:0] : idx_sum[1:0];

// Data Gating for MAC, reduce dynamic power by glitch
// only in cal state release data, else always zero
wire signed [7:0] op_ifmap_isolated  = (state == CALC) ? op_ifmap  : 8'd0;
wire signed [7:0] op_filter_isolated = (state == CALC) ? op_filter : 8'd0;


//===========================================================================
// Control Path: Next state logic
//===========================================================================
always_comb begin
    case (state)
        IDLE:  // wait for enable signal and go to complete calculation loop
            if (PE_en) next_state = LOAD_FILTER;
            else next_state = IDLE;
            
        LOAD_FILTER: 
            // handshake the basic rule for load data and state transfer
            // We load p * (s = 3) 32-bit (assume q = 4) weights into spad
            if ((hs_filter) && (cnt_p == p_max) && (cnt_s == s_max)) 
                next_state = LOAD_IFMAP_INIT;
            else next_state = LOAD_FILTER;
                
        LOAD_IFMAP_INIT: 
            // handshake the basic rule for load data and state transfer
            // We load (s = 3) 32-bit (assume q = 4) pixels into spad
            if ((hs_ifmap) && (cnt_s == s_max)) 
                next_state = LOAD_IPSUM;
            else next_state = LOAD_IFMAP_INIT;
                
        LOAD_IFMAP_SHIFT: 
            // handshake the basic rule for load data and state transfer
            // We only load one new row 32-bit pixels into spad
            // match the slide window type dataflow
            if (hs_ifmap) 
                next_state = LOAD_IPSUM;
            else next_state = LOAD_IFMAP_SHIFT;
                
        LOAD_IPSUM: 
            // handshake the basic rule for load data and state transfer
            // We load p 32-bit (assume q = 4) initial partial sum into spad
            if ((hs_ipsum) && (cnt_p == p_max)) 
                next_state = CALC;
            else next_state = LOAD_IPSUM;
                
        CALC: 
            // handshake the basic rule for load data and state transfer
            // We calculate q * (s = 3) * p times make sure all pixel has
            // multiple with corresponding weight and accumulate
            if ((cnt_q == q_max) && (cnt_s == s_max) && (cnt_p == p_max)) 
                next_state = OUT_OPSUM;
            else next_state = CALC;
                
        OUT_OPSUM: 
            // handshake the basic rule for load data and state transfer
            // We output p opsum at this state, then loop to LOAD_IFMAP_SHIFT
            // iff this ofmap row hasn't completed. After f loop, back to IDLE
            if ((hs_opsum) && (cnt_p == p_max)) 
                next_state = (cnt_f == f_max) ? IDLE : LOAD_IFMAP_SHIFT;
            else next_state = OUT_OPSUM;
                
        default:  // default need go back to IDLE
            next_state = IDLE;
    endcase
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) state <= IDLE;    // reset state, active high
    else state <= next_state;  // FSM going to next state determine by state
end

//===========================================================================
// Control Path: Config screenshot
//===========================================================================
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin  // reset config, active high
        mode  <= 1'b0;
        p_max <= 2'b0;
        f_max <= 5'b0;
        q_max <= 2'b0;
    end else if (PE_en) begin
        mode  <= i_config[9];    // 0: CONV, 1: FC
        p_max <= i_config[8:7];  // number of filters process, max p = 4
        f_max <= i_config[6:2];  // number of channels process, max q = 4
        q_max <= i_config[1:0];  // number of calculate times, max f = 16
    end
end

//===========================================================================
// Control Path: Counter and Pointer counting logic
//===========================================================================
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin  // reset counter, active high
        cnt_p <= 2'd0; cnt_s <= 2'd0; 
        cnt_q <= 2'd0; cnt_f <= 5'd0; wr_ptr <= 2'd0;
    end 
    
    else begin
        case (state)
            IDLE: begin  // IDLE need to be no action
                cnt_p <= 2'd0; cnt_s <= 2'd0; 
                cnt_q <= 2'd0; cnt_f <= 5'd0; 
                wr_ptr <= 2'd0;  // make sure oldest data at index 0
            end
            
            LOAD_FILTER: begin
                if (hs_filter) begin  // only work after handshake
                    // 2 loop counting. Inside count s. Outside count p.
                    // 1 weight is 8-bit and we assume q = 4, so we get 32-bit
                    // This part is independent with cnt_q, cnt_f
                    cnt_s <= (cnt_s == s_max) ? 2'd0 : cnt_s + 2'd1;
                    if (cnt_s == s_max) 
                        cnt_p <= (cnt_p == p_max) ? 2'd0 : cnt_p + 2'd1;
                end 
            end
            
            LOAD_IFMAP_INIT: begin
                if (hs_ifmap) begin   // only work after handshake
                    // 1 loop counting. Only count for 3 32-bit ifmap pixels
                    // This part is independent with cnt_q, cnt_p, cnt_f
                    cnt_s <= (cnt_s == s_max) ? 2'd0 : cnt_s + 2'd1;
                    wr_ptr <= 2'd0;  // make sure oldest data at index 0
                end
            end

            LOAD_IFMAP_SHIFT: begin   // only work after handshake
                if (hs_ifmap)
                    // just 1 cycle state, no need of counter
                    // But need to pointer + 1, make it point to oldest data
                    wr_ptr <= (wr_ptr == 2'd2) ? 2'd0 : wr_ptr + 2'd1;
            end

            LOAD_IPSUM: begin
                if (hs_ipsum) begin   // only work after handshake
                    // 1 loop counting. Only count for p_max 32-bit ipsums
                    // This part is independent with cnt_q, cnt_s, cnt_f
                    cnt_p <= (cnt_p == p_max) ? 2'd0 : cnt_p + 2'd1;
                end
            end

            CALC: begin  // Calculation loop have no comminication with outside,
                         // so there is no need of handshake
                // 3 loop counting. Inside count q. Middle count s. Outside
                // count p. q mean staggered arrangement of filter weights come 
                // from different channel. s mean the same row. p mean different
                // filter weights.
                // This part is independent with cnt_f
                cnt_q <= (cnt_q == q_max) ? 2'd0 : cnt_q + 2'd1;
                if (cnt_q == q_max) begin
                    cnt_s <= (cnt_s == s_max) ? 2'd0 : cnt_s + 2'd1;
                    if (cnt_s == s_max) cnt_p <= (cnt_p == p_max) ? 
                                                  2'd0 : cnt_p + 2'd1;
                end
            end

            OUT_OPSUM: begin
                if (hs_opsum) begin   // only work after handshake
                    // 2 loop counting. Inside count p. Outside count f.
                    // 1 calculation loop would output p opsum
                    // f loop is need for a ofmap
                    // This part is independent with cnt_q, cnt_s
                    cnt_p <= (cnt_p == p_max) ? 2'd0 : cnt_p + 2'd1;
                    if (cnt_p == p_max) cnt_f <= cnt_f + 5'd1;
                end
            end
            
            default: ; // default keep counter themselves
        endcase
    end
end

//===========================================================================
// Datapath: MUX and Zero-point Process
//===========================================================================
always_comb begin  // According to cnt_q choose the specific cahnnel
                   // use cnt_p to choose specific filter
                   // use cnt_s to choose specific 8-bit one weight
    case (cnt_q)
        2'd0: begin  // cnt_q is 0, index from 0 ~ 0 + 7
            ifmap_raw = ifmap_spad[read_idx][7:0];
            op_filter = filter_spad[cnt_p][cnt_s][7:0];
        end
        2'd1: begin  // cnt_q is 1, index from 8 * 1 ~ 8 * 1 + 7
            ifmap_raw = ifmap_spad[read_idx][15:8];
            op_filter = filter_spad[cnt_p][cnt_s][15:8];
        end
        2'd2: begin  // cnt_q is 2, index from 8 * 2 ~ 8 * 2 + 7
            ifmap_raw = ifmap_spad[read_idx][23:16];
            op_filter = filter_spad[cnt_p][cnt_s][23:16];
        end
        2'd3: begin  // cnt_q is 3, index from 8 * 3 ~ 8 * 3 + 7
            ifmap_raw = ifmap_spad[read_idx][31:24];
            op_filter = filter_spad[cnt_p][cnt_s][31:24];
        end
    endcase
    
    // Inverse MSE for 8-bit signed number is equal to minus 128
    op_ifmap = {~ifmap_raw[7], ifmap_raw[6:0]};
    op_opsum = psum_spad[cnt_p];
end

//===========================================================================
// Datapath: Core Shared MAC
//===========================================================================
// Share one 8-bit signed number Multiplier
assign mul_out = op_ifmap_isolated * op_filter_isolated;

// Accumulate 16-bit Multiplier output with now partial sum
assign add_out = $signed(op_opsum) + $signed({{16{mul_out[15]}}, mul_out});

//===========================================================================
// Datapath: Scratchpad load data and Accumulate
//===========================================================================
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        // Reset register, active high
        // Not necessary but reset to protect unknow signal pollute
        for (int i=0; i<3; i++) ifmap_spad[i] <= 32'd0;
        for (int i=0; i<4; i++) psum_spad[i] <= 32'd0;
        for (int p=0; p<4; p++)
            for (int s=0; s<3; s++)
                filter_spad[p][s] <= 32'd0;
    end 
    
    else begin
        // Filter write with clock gating
        // one cycle load q * 8-bit weights by order
        if (filter_en) filter_spad[cnt_p][cnt_s] <= filter;

        // Ifmap write with clock gating
        // Initial state, write q * 8-bit pixels by order
        if (ifmap_init_en)  ifmap_spad[cnt_s]  <= ifmap;
        // Shift state, write q * 8-bit pixels replace oldest data
        if (ifmap_shift_en) ifmap_spad[wr_ptr] <= ifmap;

        // Partial sum write with clock gating
        // Initial state, write p 32-bit pratial sum by order
        if (ipsum_en) psum_spad[cnt_p] <= ipsum;
        // Cal state, write p 32-bit MAC answer back to spad
        else if (psum_calc_en) psum_spad[cnt_p] <= add_out;
    end
end

//===========================================================================
// Datapath: Opsum output path
//===========================================================================
// Directly send the partial sum currently pointed to by cnt_p to the output
assign opsum = psum_spad[cnt_p];

endmodule