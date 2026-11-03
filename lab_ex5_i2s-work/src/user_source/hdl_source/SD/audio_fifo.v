
// 跨时钟域音频FIFO：写口100MHz(sd_clk)，读口12.288MHz(mclk)
// 深度2048 x 16bit = 4KB ≈ 42ms缓冲 @48kHz
module audio_fifo (
    input            wr_clk,
    input            wr_rst_n,
    input            wr_en,
    input      [15:0] wr_data,
    output reg       wr_full,
    output reg       wr_empty,
    output reg  [11:0] wr_count,

    input            rd_clk,
    input            rd_rst_n,
    input            rd_en,
    output reg [15:0] rd_data,
    output reg       rd_empty
);

    reg [10:0] wr_addr;       // 0~2047
    reg [10:0] rd_addr;
    reg [10:0] rd_addr_gray_sync0, rd_addr_gray_sync1;
    reg [10:0] wr_addr_gray_sync0, wr_addr_gray_sync1;
    wire [10:0] wr_gray, rd_gray;

    function [10:0] bin2gray;
        input [10:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction
    function [10:0] gray2bin;
        input [10:0] gray;
        integer k;
        reg [10:0] bin;
        begin
            bin[10] = gray[10];
            for(k = 9; k >= 0; k = k - 1)
                bin[k] = bin[k+1] ^ gray[k];
            gray2bin = bin;
        end
    endfunction

    assign wr_gray = bin2gray(wr_addr);
    assign rd_gray = bin2gray(rd_addr);

    // 双口RAM
    reg [15:0] ram [0:2047];

    always @(posedge wr_clk) begin
        if(wr_en && !wr_full)
            ram[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        if(rd_en && !rd_empty)
            rd_data <= ram[rd_addr];
    end

    // 写指针
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) wr_addr <= 11'd0;
        else if(wr_en && !wr_full) wr_addr <= wr_addr + 1'b1;
    end

    // 读指针
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) rd_addr <= 11'd0;
        else if(rd_en && !rd_empty) rd_addr <= rd_addr + 1'b1;
    end

    // 读指针->写时钟域同步
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            rd_addr_gray_sync0 <= 11'd0;
            rd_addr_gray_sync1 <= 11'd0;
        end else begin
            rd_addr_gray_sync0 <= rd_gray;
            rd_addr_gray_sync1 <= rd_addr_gray_sync0;
        end
    end

    // 写指针->读时钟域同步
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            wr_addr_gray_sync0 <= 11'd0;
            wr_addr_gray_sync1 <= 11'd0;
        end else begin
            wr_addr_gray_sync0 <= wr_gray;
            wr_addr_gray_sync1 <= wr_addr_gray_sync0;
        end
    end

    wire [10:0] rd_addr_wrclk = gray2bin(rd_addr_gray_sync1);
    wire [10:0] wr_addr_rdclk = gray2bin(wr_addr_gray_sync1);

    always @(*) begin
        wr_full  = (wr_addr + 1'b1) == rd_addr_wrclk;
        wr_empty = (wr_addr == rd_addr_wrclk);
        wr_count = wr_addr - rd_addr_wrclk;
    end

    always @(*) begin
        rd_empty = (rd_addr == wr_addr_rdclk);
    end

endmodule
