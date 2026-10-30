// -----------------------------------------------------------------------------
// spi_rx : SPI slave receiver, mode 0 (CPOL=0, CPHA=0), MSB first, receive only.
//
// SCLK, MOSI and CS_N are asynchronous to clk. All three go through identical
// 2-FF synchronizers so MOSI stays aligned with SCLK, then SCLK rising edges
// are detected in the clk domain and MOSI is shifted in.
//
// Requirement: clk >= 5 x SCLK  (100 MHz clk -> SCLK <= 20 MHz).
//
// Outputs (clk domain):
//   data[7:0]   : last complete byte (holds its value until the next byte)
//   data_valid  : 1-clk pulse, high in the cycle data holds a new byte
// -----------------------------------------------------------------------------
module SPI_Rx (
    input  wire       clk,
    input  wire       rst,          // synchronous, active high
    input  wire       sclk,
    input  wire       mosi,
    input  wire       cs_n,

    output reg  [7:0] data,
    output reg        data_valid
);

    reg [1:0] sclk_sync, mosi_sync, cs_sync;
    reg       sclk_d, cs_d;

    always @(posedge clk) begin
        if (rst) begin
            sclk_sync <= 2'b00;
            mosi_sync <= 2'b00;
            cs_sync   <= 2'b11;     // idle: CS_N high
            sclk_d    <= 1'b0;
            cs_d      <= 1'b1;
        end else begin
            sclk_sync <= {sclk_sync[0], sclk};
            mosi_sync <= {mosi_sync[0], mosi};
            cs_sync   <= {cs_sync[0],   cs_n};
            sclk_d    <= sclk_sync[1];
            cs_d      <= cs_sync[1];
        end
    end

    wire sclk_rise = sclk_sync[1] & ~sclk_d;
    wire cs_active = ~cs_sync[1];
    wire cs_rise   =  cs_sync[1] & ~cs_d;
    wire cs_fall   = ~cs_sync[1] &  cs_d;

    reg [7:0] shreg;
    reg [2:0] bitcnt;                              // wraps 7 -> 0

    always @(posedge clk) begin
        if (rst) begin
            shreg      <= 8'd0;
            bitcnt     <= 3'd0;
            data       <= 8'd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (cs_fall || cs_rise) begin
                bitcnt <= 3'd0;                    // always realign at packet edges
            end else if (cs_active && sclk_rise) begin
                shreg  <= {shreg[6:0], mosi_sync[1]};
                bitcnt <= bitcnt + 3'd1;
                if (bitcnt == 3'd7) begin
                    data       <= {shreg[6:0], mosi_sync[1]};
                    data_valid <= 1'b1;
                end
            end
        end
    end

endmodule