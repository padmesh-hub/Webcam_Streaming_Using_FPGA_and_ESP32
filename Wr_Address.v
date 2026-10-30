`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.10.2026 15:15:26
// Design Name: 
// Module Name: Wr_Address
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


module Wr_Address(input clk,rst,data_ready,
input wire [11:0]data_mem,
output reg wr_enb,output reg[14:0] wr_address,output reg[11:0]data_in);

reg [14:0] count;

always @ (posedge clk or posedge rst) begin
      if(rst) begin
      wr_enb<=0;
      wr_address<=0;
      data_in<=0;
      end    
      else if (data_ready) begin
       wr_enb<=1;
       data_in<=data_mem;
       if(wr_address==19199) wr_address<=0;
       else wr_address<=wr_address+1;
      end 
      else wr_enb<=0;
 
end

endmodule
