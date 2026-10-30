`timescale 1ns / 1ps
module FSM_8to16(
    input  clk, rst,
    input  cs_n,                       // NEW: raw SPI chip-select from TOP
    input  data_valid,
    input  wire [7:0] data,
    output reg data_ready,
    output reg [11:0] data_mem
);

localparam WAIT = 2'd0,   // waiting for a packet that starts at line 0
           RUN  = 2'd1,   // passing pixels through
           PAD  = 2'd2;   // a packet was lost: finish the frame, then re-sync

reg [1:0]  state;
reg [1:0]  cs_sync;
reg        cs_d;
reg        armed;                      // seen a real packet start since reset
reg [10:0] byte_cnt;                   // byte index inside current packet
reg [3:0]  red;
reg        pkt_ok;                     // this packet is accepted
reg [6:0]  expected_line;
reg [14:0] pix_cnt;                    // mirrors Wr_Address's counter

wire cs_fall = ~cs_sync[1] & cs_d;
wire [6:0] line = data[6:0];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= WAIT;  cs_sync <= 2'b00;  cs_d <= 1'b0;  armed <= 1'b0;
        byte_cnt <= 0;  red <= 0;  pkt_ok <= 0;
        expected_line <= 0;  pix_cnt <= 0;
        data_ready <= 0;  data_mem <= 0;
    end else begin
        cs_sync    <= {cs_sync[0], cs_n};
        cs_d       <= cs_sync[1];
        data_ready <= 1'b0;                       // default: no pixel this cycle

        // Same counting rule as Wr_Address, so the two always agree
        if (data_ready)
            pix_cnt <= (pix_cnt == 15'd19199) ? 15'd0 : pix_cnt + 15'd1;

        if (cs_fall) begin                        // new packet begins
            byte_cnt <= 0;
            pkt_ok   <= 0;
            armed    <= 1'b1;
        end
        else if (data_valid && armed) begin
            if (byte_cnt != 11'h7FF) byte_cnt <= byte_cnt + 1;

            if (byte_cnt == 11'd1) begin          // header byte 1 = start_line
                if (state == WAIT) begin
                    if (line == 0) begin          // frame start: begin streaming
                        state <= RUN;  pkt_ok <= 1;  expected_line <= 7'd4;
                    end
                end else if (state == RUN) begin
                    if (line == expected_line) begin
                        pkt_ok <= 1;
                        expected_line <= (line >= 7'd116) ? 7'd0 : line + 7'd4;
                    end else begin                // packet lost -> recover
                        pkt_ok <= 0;
                        state  <= (pix_cnt == 0) ? WAIT : PAD;
                    end
                end
            end
            else if (byte_cnt >= 11'd4 && pkt_ok) begin   // payload bytes
                if (!byte_cnt[0]) red <= data[3:0];       // 1st byte of pixel
                else begin                                // 2nd byte: pixel done
                    data_mem   <= {red, data};
                    data_ready <= 1'b1;
                end
            end
        end

        // PAD: push dummy pixels until Wr_Address wraps back to 0
        if (state == PAD) begin
            if (data_ready && pix_cnt == 15'd19199) state <= WAIT;
            else data_ready <= 1'b1;
        end
    end
end
endmodule