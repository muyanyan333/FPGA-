`timescale 1ns/1ps
module tb_pcm_i2s_path;
    reg wr_clk=0, mclk=0, video_clk=0, rst=1;
    always #1 wr_clk=~wr_clk;
    always #4 mclk=~mclk;
    always #2 video_clk=~video_clk;
    reg wr_en=0;
    reg [31:0] wr_data=0;
    wire wr_full, rd_empty, rd_en, bclk, lrck, dout, audio_valid;
    wire [12:0] wr_count;
    wire [31:0] rd_data;
    wire [23:0] left_data, right_data;
    integer cycles=0;
    reg seen=0;

    pcm_frame_fifo fifo(
        .wr_clk(wr_clk),.wr_rst(rst),.wr_en(wr_en),.wr_data(wr_data),
        .wr_full(wr_full),.wr_count(wr_count),
        .rd_clk(mclk),.rd_rst(rst),.rd_en(rd_en),.rd_data(rd_data),.rd_empty(rd_empty));
    pcm_i2s_tx tx(
        .mclk(mclk),.rst(rst),.enable(1'b1),
        .bclk(bclk),.lrck(lrck),.dout(dout),
        .fifo_rd_en(rd_en),.fifo_rd_data(rd_data),.fifo_empty(rd_empty));
    I2S_receiver rx(
        .I_clk(video_clk),.I_rst(rst),.I_i2s_BCLK(bclk),
        .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
        .O_audio_valid(audio_valid),
        .O_audio_left_data(left_data),.O_audio_right_data(right_data));

    always @(posedge video_clk) begin
        if (audio_valid && left_data==24'h123400 && right_data==24'h567800)
            seen <= 1'b1;
    end
    initial begin
        repeat(5) @(posedge wr_clk); rst<=0;
        @(negedge wr_clk); wr_data=32'h12345678; wr_en=1;
        repeat(16) @(negedge wr_clk);
        wr_en=0;
        while (!seen && cycles<10000) begin @(posedge video_clk); cycles=cycles+1; end
        if (seen) $display("PASS PCM FIFO to HDMI I2S receiver");
        else $display("FAIL no expected stereo sample");
        $finish;
    end
endmodule
