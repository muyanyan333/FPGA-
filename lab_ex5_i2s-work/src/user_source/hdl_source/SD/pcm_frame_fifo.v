// 4096 stereo PCM frames shared by the 100 MHz SD and audio master-clock domains.
// Full/empty use an extra wrap bit; a 12-bit address alone cannot distinguish them.
module pcm_frame_fifo(
    input wire wr_clk, input wire wr_rst,
    input wire wr_en, input wire [31:0] wr_data,
    output wire wr_full, output wire [12:0] wr_count,
    input wire rd_clk, input wire rd_rst,
    input wire rd_en, output reg [31:0] rd_data,
    output wire rd_empty
);
    reg [31:0] mem [0:4095];
    reg [12:0] wr_bin, wr_gray, rd_bin, rd_gray;
    reg [12:0] rd_gray_w1, rd_gray_w2;
    reg [12:0] wr_gray_r1, wr_gray_r2;
    wire [12:0] wr_bin_next = wr_bin + (wr_en && !wr_full);
    wire [12:0] rd_bin_next = rd_bin + (rd_en && !rd_empty);
    wire [12:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [12:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
    wire [12:0] wr_bin_plus_one = wr_bin + 13'd1;
    wire [12:0] wr_gray_plus_one = (wr_bin_plus_one >> 1) ^ wr_bin_plus_one;

    function [12:0] gray_to_bin;
        input [12:0] gray;
        integer k;
        begin
            gray_to_bin[12] = gray[12];
            for (k=11; k>=0; k=k-1)
                gray_to_bin[k] = gray_to_bin[k+1] ^ gray[k];
        end
    endfunction

    assign wr_full = (wr_gray_plus_one == {~rd_gray_w2[12:11], rd_gray_w2[10:0]});
    assign rd_empty = (rd_gray == wr_gray_r2);
    assign wr_count = wr_bin - gray_to_bin(rd_gray_w2);

    always @(posedge wr_clk) begin
        if (wr_en && !wr_full) mem[wr_bin[11:0]] <= wr_data;
    end
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_bin <= 13'd0; wr_gray <= 13'd0;
            rd_gray_w1 <= 13'd0; rd_gray_w2 <= 13'd0;
        end else begin
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
            if (wr_en && !wr_full) begin
                wr_bin <= wr_bin_next;
                wr_gray <= wr_gray_next;
            end
        end
    end
    always @(posedge rd_clk) begin
        if (rd_en && !rd_empty) rd_data <= mem[rd_bin[11:0]];
    end
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_bin <= 13'd0; rd_gray <= 13'd0;
            wr_gray_r1 <= 13'd0; wr_gray_r2 <= 13'd0;
        end else begin
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
            if (rd_en && !rd_empty) begin
                rd_bin <= rd_bin_next;
                rd_gray <= rd_gray_next;
            end
        end
    end
endmodule
