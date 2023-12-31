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
    
    //---------- BRAM for tap RAM ----------
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    //---------- BRAM for data RAM ----------
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

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
            if (cnt == 'd10) begin
                if (y_done)
                    next_state = S_WAIT;
                else if (icnt == len - 'd1)
                    next_state = S_FINISH;
                else if (ss_tvalid)
                    next_state = S_RUN;
                else
                    next_state = S_LOAD;
            end
            else
                next_state = S_RUN;
        end
        S_LOAD: begin
            if (ss_tvalid)
                next_state = S_RUN;
            else
                next_state = S_LOAD;
        end
        S_WAIT: begin
            if (~y_done) begin
                if (sm_tready)
                    next_state = (icnt == len) ? S_FINISH : S_RUN;
                else
                    next_state = S_LOAD;
            end
            else
                next_state = S_WAIT;
        end
        S_FINISH: begin
            if (sm_tready)
                next_state = S_IDLE;
            else
                next_state = S_FINISH; 
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

//=====================================================================
//   DATA PATH & CONTROL
//=====================================================================
//---------- AXI-lite slave Interface ----------
// Address map
// 0x00 -[0]: ap_start
//      -[1]: ap_done
//      -[2]: ap_idle
// 0x10~14: data_length
// 0x20~ff: tap parameter
//----------------------------------------------
// Read: read mmio / tap RAM
// Address read channel
assign arready = ~task_r;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        addr_r <= 'd0;
    else begin
        if (arvalid & arready)
            addr_r <= araddr;
    end
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        task_r <= 1'b0;
    else begin
        case (task_r)
            1'b0: begin
                if (arvalid)
                    task_r <= 1'b1;
            end
            1'b1: begin
                if (rready & rvalid)
                    task_r <= 1'b0;
            end
        endcase
    end
end
// Read channel     * What happen if host acess tap_RAM in run state?
// assign rvalid = task_r;
always @(*) begin
    if (task_r) begin
        case (addr_r)
            'h00: begin
                rvalid = 1'b1;
                rdata = {5'b0, ap_idle, ap_done, ap_start};
            end
            'h10: begin
                rvalid = 1'b1;
                rdata = len;
            end
            default: begin
                // read tap bram
                rvalid = (rcnt) ? 1'b1 : 1'b0;
                rdata = (rcnt) ? tap_Do : 'd0;
            end
        endcase
    end
    else begin
        rdata = 'd0;
        rvalid = 1'b0;
    end
end
assign tap_ram_read = task_r & (addr_r >= 'h20 && addr_r <= 'hff);
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        rcnt <= 'd0;
    else begin
        if (tap_ram_read) begin
            rcnt <= 'd1;
        end
        else
            rcnt <= 'd0;
    end
end

// Write: write configation to mmio / tap RAM
// Address write channel
assign awready = ~task_w;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        addr_w <= 'd0;
    else begin
        if (awvalid)
            addr_w <= awaddr;
    end
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        task_w <= 1'b0;
    else begin
        case (task_w)
            1'b0: begin
                if (awvalid)
                    task_w <= 1'b1;
            end
            1'b1: begin
                if (wvalid)
                    task_w <= 1'b0;
            end
        endcase
    end
end
// Write channel
assign wready = task_w;

//---------- Block level protocol ----------
// ap_start: axilite slave write
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        ap_start <= 1'b0;
    else begin
        // set by host
        if (task_w & wvalid) begin
            ap_start <= ((addr_w == 'h00) & ap_idle) ? wdata[0] : ap_start;
        end
        // reset by engine
        else if (ap_start)
            ap_start <= 1'b0;
    end
end
// ap_done
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        ap_done <= 1'b0;
    else begin
        if ((cur_state == S_FINISH) & sm_tready)
            ap_done <= 1'b1;
    end
end
// ap_idle
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        ap_idle <= 1'b1;
    else begin
        if (ap_start)
            ap_idle <= 1'b0;
        else if (icnt == len & ~y_done)
            ap_idle <= 1'b1;
    end
end

//---------- Port level protocol ----------
// len: axilite slave write
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        len <= 'd0;
    else begin
        if (task_w & wvalid) begin
            len <= (addr_w == 'h10) ? wdata : len;
        end
    end
end
// tape: axilite slave write to bram
assign tap_ram_write = ((task_w & wvalid) && ((addr_w >= 'h20) && (addr_w <= 'hff))) ? 1'b1 : 1'b0;

//---------- AXI-stream Interface ----------
// Slave: input x to data_RAM
// assign ss_tready = (cur_state == S_LOAD);
always @(*) begin
    case (cur_state)
        S_INIT,
        S_RUN: ss_tready = (cnt == 'd10);
        S_LOAD: ss_tready = 1'b1;
        default: ss_tready = 1'b0;
    endcase
end
// Master: output y to tap_RAM
assign sm_tvalid = y_done;
assign sm_tdata = y_buffer;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
        y_buffer <= 'd0;
        y_done <= 1'b0;
    end
    else begin
        case (cur_state)
            S_RUN: begin
                if ((cnt == 'd10) & ~y_done) begin
                    y_buffer <= acc + product_i;
                    y_done <= 1'b1;
                end
                else
                    y_done <= sm_tready ? 1'b0 : y_done;
            end
            S_FINISH,
            S_LOAD: y_done <= sm_tready ? 1'b0 : y_done;
            S_WAIT: begin
                if (sm_tready) begin
                    y_buffer <= acc + product_i; // notice!!!
                end
            end
        endcase
    end
end

//---------- BRAM for tap RAM ----------
/*
bram11 tap_RAM (
    .CLK(axis_clk),
    .WE ({4{tap_ram_write}}),
    .EN (1'b1),
    .Di (wdata),
    .Do (tap_ram_out),
    .A  (tap_ram_addr)
);
*/
assign tap_WE = {4{tap_ram_write}};
assign tap_EN = 1'b1;
assign tap_Di = wdata;
assign tap_A = tap_ram_addr;

assign tap_axi_acess = tap_ram_read || tap_ram_write;
always @(*) begin
    if (tap_axi_acess) begin
        if (task_w)
            tap_ram_addr = addr_w - 'h20;
        else
            tap_ram_addr = addr_r - 'h20;
    end
    else begin
        // FIR engine
        case (cur_state)
            S_INIT, 
            S_LOAD: tap_ram_addr = 'd0;
            S_RUN: begin
                case (next_state)
                    S_RUN: tap_ram_addr = (cnt == 'd10) ? 'd0 : {cnt + 'd1, 2'b00};
                    S_WAIT: tap_ram_addr = {30'd9, 2'b00};
                    default: tap_ram_addr = 'd0;
                endcase
            end
            S_WAIT: tap_ram_addr = (sm_tready) ? 'd0 :{30'd9, 2'b00};
            default: tap_ram_addr = 'd0;
        endcase
    end
end

//---------- BRAM for data RAM ----------
/*
bram11 data_RAM (
    .CLK(axis_clk),
    .WE ({4{data_ram_write}}),
    .EN (1'b1),
    .Di (data_ram_in),
    .Do (data_ram_out),
    .A  (data_ram_addr)
);
*/
assign data_WE = {4{data_ram_write | (cur_state == S_INIT)}};
assign data_EN = 1'b1;
assign data_Di = data_ram_in;
assign data_A = data_ram_addr;

// Di
always @(*) begin
    case (cur_state)
        S_INIT: data_ram_in = (cnt == 'd10) ? ss_tdata : 'd0;
        default: data_ram_in = ss_tdata;
    endcase
end
assign data_ram_write = ss_tvalid & ss_tready;
// address
always @(*) begin
    case (cur_state)
        S_INIT: data_ram_addr = {cnt, 2'b00};       // write bram
        S_RUN: begin                                // cnt=0~9: read cnt=10: write
            if (cnt == 'd10)
                data_ram_addr = (ss_idx + 'd10 > 10) ?  {ss_idx - 'd1, 2'b00}: {ss_idx + 'd10, 2'b00};
            else
                data_ram_addr = (ss_idx + cnt + 'd1 > 10) ? {ss_idx + cnt - 'd10, 2'b00} : {ss_idx + cnt + 'd1, 2'b00};
        end
        default: data_ram_addr = {ss_idx, 2'b00};   // S_LOAD, S_WAIT: write bram
    endcase
end
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        ss_idx <= 'd10;
    else begin
        if (cur_state == S_RUN && cnt == 'd10)
            ss_idx <= (ss_idx > 0) ? ss_idx - 1'b1 : 'd10;
    end
end

//---------- FIR engine ----------
assign product_i = tap_Do * data_Do;
always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        acc <= 'd0;
    else begin
        case (cur_state)
            S_RUN: begin
                if (cnt == 'd10)
                    acc <= (y_done) ? acc : 'd0;    // next_state = S_WAIT
                else
                    acc <= acc + product_i; 
            end
            S_WAIT: acc <= (sm_tready) ? 'd0 : acc;
        endcase
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n)
        icnt <= 'd0;
    else begin
        if (cur_state == S_RUN && cnt == 'd10)
            icnt <= icnt + 1'b1;
    end
end


//=====================================================================
//   OUTPUT
//=====================================================================


endmodule