`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.07.2026 21:22:21
// Design Name: 
// Module Name: VGA_controller
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


module VGA_Controller(
input clk,rst,
output Hsync,Vsync,video_on,f_25mhz
);

reg[1:0]freq;
wire f_25mhz_reg;

parameter hp=680;
parameter hf=16;
parameter hr=96;
parameter hb=48;
parameter hmax=799;
parameter vmax=524;
parameter vp=680;
parameter vf=33;
parameter vr=2;
parameter vb=10;


reg [1:0] count;

    always @(posedge clk or posedge rst) begin
        if (rst)
            count <= 2'b00;
        else
            count <= count + 1'b1;
    end

    // High every 4th 100 MHz cycle
    assign f_25mhz_reg = (count == 2'b11);

reg[9:0] hcount_reg,vcount_reg;
reg[9:0] hcount_next,vcount_next;
reg Hsync_reg,Vsync_reg,video_on_reg;
wire Hsync_next,Vsync_next,video_on_next;

always @ (posedge clk or posedge rst) begin
          if(rst) begin
              hcount_reg<=0;
              vcount_reg<=0;
              Hsync_reg<=1'b0;
              Vsync_reg<=1'b0;
              video_on_reg<=1'b0;
          end
          else begin
              hcount_reg<=hcount_next;
              vcount_reg<=vcount_next;
              Hsync_reg<=Hsync_next;
              Vsync_reg<=Vsync_next;
              video_on_reg<= video_on_next;
          end
end

// ✅ CORRECT: Clocked cleanly on clk, qualified by the 25 MHz enable tick
always @(posedge clk or posedge rst) begin
    if (rst) begin
        hcount_next <= 0;
        vcount_next <= 0;
    end else if (f_25mhz_reg) begin   // <-- Only advances when the tick is HIGH
        if (hcount_reg == 799) begin
            hcount_next <= 0;
            if (vcount_reg == 524)
                vcount_next <= 0;
            else
                vcount_next <= vcount_next + 1'b1;
        end else begin
            hcount_next <= hcount_next + 1'b1;
        end
    end
end

assign Hsync_next = (hcount_reg >=656 && hcount_reg<752)?1'b0:1'b1;
assign Vsync_next = (vcount_reg >=490 && vcount_reg<492)?1'b0:1'b1;
assign video_on_next = (hcount_reg<=159 && vcount_reg<=119);
assign f_25mhz=f_25mhz_reg;

assign Hsync=Hsync_reg;
assign Vsync=Vsync_reg;
assign video_on=video_on_reg;
endmodule  
