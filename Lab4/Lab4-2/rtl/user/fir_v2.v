`timescale 1ns / 1ps

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(   
    //---------- AXI-lite slave Interface ----------
    // Address write channel
    output  wire                     awready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    // Write channel
    output  wire                     wready,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    // Address read channel
    output  wire                     arready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    // Read channel
    output  reg                      rvalid,
    output  reg  [(pDATA_WIDTH-1):0] rdata,
    input   wire                     rready,

    //---------- AXI-stream Interface ----------
    // Slave
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  reg                      ss_tready, 
    // Master
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // //---------- BRAM for tap RAM ----------
    // output  wire [3:0]               tap_WE,
    // output  wire                     tap_EN,
    // output  wire [(pDATA_WIDTH-1):0] tap_Di,
    // output  wire [(pADDR_WIDTH-1):0] tap_A,
    // input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // //---------- BRAM for data RAM ----------
    // output  wire [3:0]               data_WE,
    // output  wire                     data_EN,
    // output  wire [(pDATA_WIDTH-1):0] data_Di,
    // output  wire [(pADDR_WIDTH-1):0] data_A,
    // input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
//=====================================================================
//   REG AND WIRE DECLARATION
//=====================================================================
// FSM
reg [2:0] cur_state, next_state;
reg [3:0] cnt;
// AXIlite
reg [(pADDR_WIDTH-1):0] addr_r, addr_w;
reg task_r, task_w;
reg rcnt;
// AXIstream
reg [3:0] ss_idx;
wire x_ready, y_ready;

// Configuration
reg ap_start, ap_done, ap_idle;
reg [(pDATA_WIDTH-1):0] len;  // data length
// BRAM
wire tap_ram_write, data_ram_write, tap_ram_read;
reg [11:0] tap_ram_addr, data_ram_addr;
// wire [(pDATA_WIDTH-1):0] tap_ram_out, data_ram_out;
reg [(pDATA_WIDTH-1):0] data_ram_in;
wire tap_axi_acess;
// FIR engine
wire [(pDATA_WIDTH-1):0] x_i, h_i, product_i;
reg [(pDATA_WIDTH-1):0] acc, y_buffer;
reg y_done;
reg [(pDATA_WIDTH-1):0] icnt;

//---------- BRAM for tap RAM ----------
wire                     tap_WE;
wire                     tap_EN;
wire [(pDATA_WIDTH-1):0] tap_Di;
wire [(pADDR_WIDTH-1):0] tap_A;
wire [(pDATA_WIDTH-1):0] tap_Do;
//---------- BRAM for data RAM ----------
wire                     data_WE;
wire                     data_EN;
wire [(pDATA_WIDTH-1):0] data_Di;
wire [(pADDR_WIDTH-1):0] data_A;
wire [(pDATA_WIDTH-1):0] data_Do;

//=====================================================================
//   PARAMETER AND INTEGER
//=====================================================================
localparam S_IDLE = 'd0;
localparam S_INIT = 'd1;    // reset data ram
localparam S_LOAD = 'd2;    // read xi from axi stream
localparam S_RUN = 'd3;     // accumulate x*h product
localparam S_WAIT = 'd4;    // wait axi stream read y
localparam S_FINISH = 'd5;

//=====================================================================
//   FSM
//=====================================================================
// Current State
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        cur_state <= S_IDLE;
    else
        cur_state <= next_state;
end
// Next State
always @(*) begin
    case (cur_state)
        S_IDLE: begin
            if (ap_start)
                next_state = S_INIT;
            else
                next_state = S_IDLE;
        end
        S_INIT: begin
            if (cnt == 'd10)
                next_state = (ss_tvalid) ? S_RUN : S_LOAD; // read first x and go to RUN state
            else
                next_state = S_INIT;
        end
        S_RUN: begin

        end
        S_LOAD: begin

        end
        S_WAIT: begin

        end
        S_FINISH: begin

        end
        default: next_state = cur_state;
    endcase
end
// count
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        cnt <= 'd0;
    else begin
        case (cur_state)
            S_INIT,
            S_RUN: begin
                if (cnt < 'd10)
                    cnt <= cnt + 1'b1;
                else
                    cnt <= 'd0;
            end
            default: cnt <= 'd0;
        endcase
    end
end



endmodule