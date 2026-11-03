`timescale 1ns/1ps
// Real UART bytes -> shared command dispatcher -> asynchronous PCM clock ->
// serialized stereo output. No forced internal command or audio signals.
module voice_volume_audio_tb;
    reg clk=0, mclk=0, rst=1, voice_rx=1;
    always #5 clk=~clk;
    always #17 mclk=~mclk;
    wire [3:0] volume;
    wire muted, bclk, lrck, dout;
    integer level;
    uart_image_control #(.CLK_FREQ_HZ(153600), .BAUD_RATE(9600)) control (
        .clk(clk), .rst(rst), .uart_rx(1'b1), .voice_rx(voice_rx),
        .volume_level(volume), .volume_muted(muted),
        .image_count(5'd7), .current_index(4'd0), .auto_mode(1'b0), .scan_done(1'b1),
        .transition_effect(2'd0), .brightness_level(4'd9), .contrast_level(4'd5),
        .image_size(2'd0), .image_aspect(2'd0), .music_track_number(5'd1),
        .music_track_count(5'd7), .music_track_map(16'h007f), .music_playing(1'b1),
        .lyric_valid(1'b1), .title_valid(1'b1), .camera_mode(2'd0),
        .video_status(3'd0), .notice_rd_clk(clk), .notice_rd_addr(10'd0)
    );
    pcm_i2s_tx audio (
        .mclk(mclk), .rst(rst), .enable(1'b1),
        .volume_level(volume), .volume_muted(muted),
        .bclk(bclk), .lrck(lrck), .dout(dout), .fifo_rd_en(),
        .fifo_rd_data({16'd16000,16'hc180}), .fifo_empty(1'b0)
    );
    task send_byte(input [7:0] data);
        integer bit_no;
        begin
            @(negedge clk); voice_rx=0;
            repeat(16) @(negedge clk);
            for(bit_no=0;bit_no<8;bit_no=bit_no+1) begin
                voice_rx=data[bit_no]; repeat(16) @(negedge clk);
            end
            voice_rx=1; repeat(16) @(negedge clk);
        end
    endtask
    task command(input [7:0] cmd, input [7:0] arg);
        begin
            send_byte(8'ha5); send_byte(cmd); send_byte(arg);
            send_byte(8'ha5 ^ cmd ^ arg);
            repeat(10) @(negedge clk);
        end
    endtask
    function integer gain(input integer n);
        case(n)
            0:gain=0; 1:gain=26; 2:gain=51; 3:gain=77;
            4:gain=102; 5:gain=128; 6:gain=154; 7:gain=179;
            8:gain=205; 9:gain=230; default:gain=256;
        endcase
    endfunction
    task check_audio(input integer expected_level, input expected_mute);
        integer n, g;
        reg [15:0] left_sample, right_sample, expected_left, expected_right;
        begin
            // Flush synchronization and both prefetched sample registers.
            repeat(800) @(negedge mclk);
            if(volume !== expected_level[3:0] || muted !== expected_mute)
                $fatal(1,"UART volume/mute mismatch level=%0d",expected_level);
            g=expected_mute ? 0 : gain(expected_level);
            expected_left=(16000*g) >>> 8;
            expected_right=(-16000*g) >>> 8;
            @(negedge lrck); @(posedge bclk); // I2S one-bit delay
            for(n=0;n<16;n=n+1) begin
                @(posedge bclk); left_sample={left_sample[14:0],dout};
            end
            @(posedge lrck); @(posedge bclk);
            for(n=0;n<16;n=n+1) begin
                @(posedge bclk); right_sample={right_sample[14:0],dout};
            end
            if(left_sample !== expected_left || right_sample !== expected_right)
                $fatal(1,"I2S volume=%0d mute=%b got=%h/%h expected=%h/%h",
                    expected_level,expected_mute,left_sample,right_sample,expected_left,expected_right);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0;
        check_audio(10,0);
        for(level=0;level<=10;level=level+1) begin
            command(8'h20,level); check_audio(level,0);
        end
        command(8'h22,0); check_audio(9,0);
        command(8'h21,0); check_audio(10,0);
        command(8'h21,0); check_audio(10,0);
        command(8'h20,5); check_audio(5,0);
        command(8'h23,1); check_audio(5,1);
        command(8'h23,0); check_audio(5,0);
        command(8'h24,0); check_audio(5,1);
        command(8'h22,0); check_audio(4,0);
        command(8'h20,0); command(8'h22,0); check_audio(0,0);
        command(8'h20,11); check_audio(0,0);
        send_byte(8'ha5); send_byte(8'h20); send_byte(8'h0a); send_byte(8'h00);
        check_audio(0,0);
        command(8'h20,10); check_audio(10,0);
        $display("PASS: voice UART -> PCM -> serialized I2S, all 11 levels, mute, bounds, bad checksum, recovery");
        $finish;
    end
    initial begin #2000000; $fatal(1,"test timeout"); end
endmodule
