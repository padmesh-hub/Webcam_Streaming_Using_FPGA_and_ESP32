`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.10.2026 15:53:56
// Design Name: 
// Module Name: TOP
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module TOP(
input clk,rst,sclk,mosi,cs_n,
output wire Hsync,Vsync,
output wire [11:0]RGB
);

wire [7:0] data;
wire data_valid;
wire data_ready;
wire [11:0] data_mem;
wire wr_enb;
wire [14:0]wr_address;
wire [11:0]data_in;
wire video_on,f_25mhz;
wire [14:0] rd_address;
wire [11:0] bram_data;

// 1.SPI Receiver
SPI_Rx dut1 (
.clk(clk),.rst(rst),.sclk(sclk),.mosi(mosi),.cs_n(cs_n),
.data(data),.data_valid(data_valid)
);

// 2.FSM_8to16
FSM_8to16 dut2(
.clk(clk),.rst(rst),.data_valid(data_valid),.data(data),.cs_n(cs_n),
.data_ready(data_ready),.data_mem(data_mem)
);

// 3.Wr_Address
Wr_Address dut3(
.clk(clk),.rst(rst),.data_ready(data_ready),.data_mem(data_mem),
.wr_enb(wr_enb),.wr_address(wr_address),.data_in(data_in)
);

// 4. BRAM
blk_mem_gen_0 dut4(
    .clka(clk),
    .ena(1'b1),
    .wea({wr_enb}),
    .addra({wr_address}),
    .dina(data_mem),
    .clkb(clk),
    .enb(1'b1),
    .addrb(rd_address),
    .doutb(bram_data)
);

assign RGB = (video_on)? bram_data :12'b0;

// 5.VGA
VGA_Controller dut5(
.clk(clk),.rst(rst),
.Hsync(Hsync),.Vsync(Vsync),.video_on(video_on),.f_25mhz(f_25mhz)
);

// 6.Rd_Address
Rd_Address dut6(
.clk(clk),.rst(rst),.video_on(video_on),.f_25mhz(f_25mhz),
.rd_address(rd_address)
);

endmodule
