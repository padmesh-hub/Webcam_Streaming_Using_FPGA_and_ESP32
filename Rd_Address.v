`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.10.2026 15:51:17
// Design Name: 
// Module Name: Rd_Address
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


module Rd_Address(input clk,rst,video_on,f_25mhz,output reg[14:0] rd_address);

always @ (posedge clk or posedge rst) begin
         if(rst) begin
         rd_address<=10'b0;
         end
         else if(video_on && f_25mhz ) begin
              if(rd_address==19199) rd_address<=15'b0;
              else rd_address<=rd_address+1;
           end
         
end
endmodule
