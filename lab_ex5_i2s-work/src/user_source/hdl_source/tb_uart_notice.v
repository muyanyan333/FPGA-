`timescale 1ns/1ps
module tb_uart_notice;
reg clk = 0;
reg rst = 1;
reg uart_rx = 1;
reg voice_rx = 1;
reg gesture_rx = 1;
reg key_volume_up = 0, key_volume_down = 0;
reg key_volume_set = 0;
reg [3:0] key_volume_value = 0;
wire uart_tx;
wire voice_tx;
wire [7:0] voice_tx_byte;
wire voice_tx_valid;
integer voice_tx_count = 0;
reg [7:0] first_voice_byte = 0, second_voice_byte = 0;
wire spectrum_enabled;
wire [3:0] volume_level;
wire volume_muted;
reg seen_volume = 0;
wire notice_toggle;
wire [7:0] notice_flags;
wire [9:0] notice_width;
wire notice_receiving;
reg [9:0] notice_rd_addr = 0;
wire [7:0] notice_rd_data;
wire size_toggle, aspect_toggle;
wire [1:0] size_value, aspect_value;
wire music_select_toggle, playing_toggle, playing_value, lyric_enabled, title_enabled;
wire [3:0] music_select_index;
wire music_prev_pulse, music_next_pulse;
reg saw_music_prev = 0, saw_music_next = 0;
wire next_pulse, prev_pulse;
integer gesture_next_count = 0, gesture_prev_count = 0;
wire [7:0] tx_byte;
wire tx_valid;
reg [2:0] tx_index = 0;
reg seen_geometry = 0;
reg seen_music = 0;
reg seen_spectrum_hidden = 0;
reg [7:0] tx_frame [0:7];
integer i;
reg [7:0] checksum;
localparam integer CPB = 10;

always #5 clk = ~clk;
uart_rx_byte #(.CLK_FREQ_HZ(1_000_000), .BAUD_RATE(100_000)) monitor(
    .clk(clk), .rst(rst), .uart_rx(uart_tx), .data(tx_byte), .data_valid(tx_valid));
uart_rx_byte #(.CLK_FREQ_HZ(1_000_000), .BAUD_RATE(100_000)) voice_monitor(
    .clk(clk), .rst(rst), .uart_rx(voice_tx), .data(voice_tx_byte), .data_valid(voice_tx_valid));
always @(posedge clk) if (voice_tx_valid) begin
    if (voice_tx_count == 0) first_voice_byte <= voice_tx_byte;
    if (voice_tx_count == 1) second_voice_byte <= voice_tx_byte;
    voice_tx_count <= voice_tx_count + 1;
end
always @(posedge clk) if (tx_valid) begin
    tx_frame[tx_index] <= tx_byte;
    if (tx_index == 3'd7) begin
        if (tx_frame[1] == 8'h87 && tx_frame[2] == 8'd5 && tx_frame[3] == 8'd1 &&
            tx_frame[4] == 0 && tx_frame[5] == 0 && tx_frame[6] == 0 &&
            tx_byte == (8'h5A ^ 8'h87 ^ 8'd5 ^ 8'd1)) seen_volume <= 1'b1;
        if (tx_frame[1] == 8'h85 && tx_frame[4][6:5] == 2'b10 &&
            tx_byte == (8'h5A ^ tx_frame[1] ^ tx_frame[2] ^ tx_frame[3] ^
                        tx_frame[4] ^ tx_frame[5] ^ tx_frame[6]))
            seen_spectrum_hidden <= 1'b1;
        if (tx_frame[1] == 8'h84 && tx_frame[2] == 8'd1 && tx_frame[3] == 8'd2 &&
            tx_byte == (8'h5A ^ 8'h84 ^ 8'd1 ^ 8'd2)) seen_geometry <= 1'b1;
        if (tx_frame[1] == 8'h85 && tx_frame[2] == 8'd2 && tx_frame[3] == 8'd6 &&
            tx_frame[4] == 8'h7F && tx_frame[5] == 8'hA2 && tx_frame[6] == 8'h0E &&
            tx_byte == (8'h5A ^ 8'h85 ^ 8'd2 ^ 8'd6 ^ 8'h7F ^ 8'hA2 ^ 8'h0E))
            seen_music <= 1'b1;
        tx_index <= 3'd0;
    end else tx_index <= tx_index + 1'b1;
end
always @(posedge clk) begin
    if (music_prev_pulse) saw_music_prev <= 1;
    if (music_next_pulse) saw_music_next <= 1;
    if (next_pulse) gesture_next_count <= gesture_next_count + 1;
    if (prev_pulse) gesture_prev_count <= gesture_prev_count + 1;
end

task send_gesture_byte;
    input [7:0] value;
    integer bit_no;
    begin
        gesture_rx = 0; repeat(CPB) @(posedge clk);
        for(bit_no=0; bit_no<8; bit_no=bit_no+1) begin
            gesture_rx = value[bit_no]; repeat(CPB) @(posedge clk);
        end
        gesture_rx = 1; repeat(CPB) @(posedge clk);
    end
endtask

task send_byte;
    input [7:0] value;
    integer bit_no;
    begin
        uart_rx = 0; repeat(CPB) @(posedge clk);
        for(bit_no=0; bit_no<8; bit_no=bit_no+1) begin
            uart_rx = value[bit_no]; repeat(CPB) @(posedge clk);
        end
        uart_rx = 1; repeat(CPB) @(posedge clk);
    end
endtask

task send_voice_byte;
    input [7:0] value;
    integer bit_no;
    begin
        voice_rx = 0; repeat(CPB) @(posedge clk);
        for(bit_no=0; bit_no<8; bit_no=bit_no+1) begin
            voice_rx = value[bit_no]; repeat(CPB) @(posedge clk);
        end
        voice_rx = 1; repeat(CPB) @(posedge clk);
    end
endtask

uart_image_control #(.CLK_FREQ_HZ(1_000_000), .BAUD_RATE(100_000)) dut(
    .clk(clk), .rst(rst), .uart_rx(uart_rx), .voice_rx(voice_rx),
    .gesture_rx(gesture_rx), .key_volume_up(key_volume_up), .key_volume_down(key_volume_down),
    .key_volume_set(key_volume_set), .key_volume_value(key_volume_value),
    .uart_tx(uart_tx), .voice_tx(voice_tx),
    .image_count(5'd7), .current_index(4'd2), .auto_mode(1'b0), .scan_done(1'b1),
    .transition_effect(2'd1), .brightness_level(4'd8), .contrast_level(4'd6),
    .image_size(2'd1), .image_aspect(2'd2),
    .music_track_number(5'd2), .music_track_count(5'd6), .music_track_map(16'h0EA2),
    .music_playing(1'b1), .lyric_valid(1'b1), .title_valid(1'b1),
    .select_valid(), .select_index(), .auto_pulse(), .manual_pulse(),
    .next_pulse(next_pulse), .prev_pulse(prev_pulse),
    .music_prev_pulse(music_prev_pulse), .music_next_pulse(music_next_pulse),
    .effect_toggle(), .effect_value(),
    .brightness_toggle(), .brightness_value(), .contrast_toggle(), .contrast_value(),
    .size_toggle(size_toggle), .size_value(size_value),
    .aspect_toggle(aspect_toggle), .aspect_value(aspect_value),
    .music_select_toggle(music_select_toggle), .music_select_index(music_select_index),
    .playing_toggle(playing_toggle), .playing_value(playing_value),
    .lyric_enabled(lyric_enabled), .title_enabled(title_enabled), .spectrum_enabled(spectrum_enabled),
    .volume_level(volume_level), .volume_muted(volume_muted), .video_status(3'd0), .camera_mode(2'd0),
    .notice_toggle(notice_toggle), .notice_flags(notice_flags), .notice_width(notice_width),
    .notice_receiving(notice_receiving), .notice_rd_clk(clk), .notice_rd_addr(notice_rd_addr),
    .notice_rd_data(notice_rd_data)
);

initial begin
    repeat(5) @(posedge clk); rst = 0; repeat(5) @(posedge clk);
    repeat(4500) @(posedge clk);
    if (!seen_geometry || !seen_music) $fatal(1, "attribute status frames missing");
    if (voice_tx_count != 0) $fatal(1, "unsolicited ASRPRO reply");
    send_byte(8'hA5); send_byte(8'h0B); send_byte(8'h02); send_byte(8'hAC);
    repeat(30) @(posedge clk);
    if (size_toggle !== 1'b1 || size_value !== 2'd2) $fatal(1, "size command failed");
    send_byte(8'hA5); send_byte(8'h0C); send_byte(8'h03); send_byte(8'hAA);
    repeat(30) @(posedge clk);
    if (aspect_toggle !== 1'b1 || aspect_value !== 2'd3) $fatal(1, "aspect command failed");
    send_byte(8'hA5); send_byte(8'h0D); send_byte(8'h08); send_byte(8'hA0);
    repeat(30) @(posedge clk);
    if (music_select_toggle !== 1'b1 || music_select_index !== 4'd7)
        $fatal(1, "music selection failed");
    send_byte(8'hA5); send_byte(8'h0E); send_byte(8'h00); send_byte(8'hAB);
    repeat(30) @(posedge clk);
    if (playing_toggle !== 1'b1 || playing_value !== 1'b0)
        $fatal(1, "music pause failed");
    send_byte(8'hA5); send_byte(8'h0F); send_byte(8'h00); send_byte(8'hAA);
    send_byte(8'hA5); send_byte(8'h10); send_byte(8'h00); send_byte(8'hB5);
    repeat(30) @(posedge clk);
    if (lyric_enabled !== 1'b0 || title_enabled !== 1'b0)
        $fatal(1, "lyric/title controls failed");
    if (spectrum_enabled !== 1'b1) $fatal(1, "spectrum default failed");
    send_voice_byte(8'hA5); send_voice_byte(8'h1E); send_voice_byte(8'h00); send_voice_byte(8'hBB);
    repeat(30) @(posedge clk);
    if (spectrum_enabled !== 1'b0) $fatal(1, "voice spectrum hide failed");
    repeat(11000) @(posedge clk);
    if (!seen_spectrum_hidden) $fatal(1, "spectrum hidden status missing");
    send_byte(8'hA5); send_byte(8'h1E); send_byte(8'h02); send_byte(8'hB9);
    repeat(30) @(posedge clk);
    if (spectrum_enabled !== 1'b0) $fatal(1, "invalid spectrum argument accepted");
    send_byte(8'hA5); send_byte(8'h1F); send_byte(8'h00); send_byte(8'hBA);
    repeat(30) @(posedge clk);
    if (spectrum_enabled !== 1'b1) $fatal(1, "bluetooth spectrum toggle failed");
    checksum = 8'hA6;
    send_byte(8'hA6);
    send_byte(8'h07); checksum = checksum ^ 8'h07;
    send_byte(8'h2C); checksum = checksum ^ 8'h2C;
    send_byte(8'h01); checksum = checksum ^ 8'h01;
    for(i=0; i<1024; i=i+1) begin
        send_byte(i[7:0]);
        checksum = checksum ^ i[7:0];
    end
    send_byte(checksum);
    repeat(30) @(posedge clk);
    if(notice_flags !== 8'h07 || notice_width !== 10'd300 || notice_toggle !== 1'b1)
        $fatal(1, "notice commit failed flags=%h width=%d toggle=%b", notice_flags, notice_width, notice_toggle);
    notice_rd_addr = 10'd5; @(posedge clk); #1;
    if(notice_rd_data !== 8'h05) $fatal(1, "notice memory failed: %h", notice_rd_data);
    send_byte(8'hA5); send_byte(8'h0A); send_byte(8'h00); send_byte(8'hAF);
    repeat(30) @(posedge clk);
    if(notice_flags !== 8'h00 || notice_width !== 10'd0 || notice_toggle !== 1'b0)
        $fatal(1, "notice clear failed");
    // ASRPRO uses its own RX pin but executes the same command table.
    send_voice_byte(8'hA5); send_voice_byte(8'h0D); send_voice_byte(8'h07); send_voice_byte(8'hAF);
    repeat(30) @(posedge clk);
    if (music_select_toggle !== 1'b0 || music_select_index !== 4'd6)
        $fatal(1, "voice music selection failed");
    send_voice_byte(8'hA5); send_voice_byte(8'h0B); send_voice_byte(8'h01); send_voice_byte(8'h00);
    repeat(30) @(posedge clk);
    if (size_toggle !== 1'b1) $fatal(1, "invalid voice checksum accepted");
    send_voice_byte(8'hA5); send_voice_byte(8'h0B); send_voice_byte(8'h01); send_voice_byte(8'hAF);
    repeat(30) @(posedge clk);
    if (size_toggle !== 1'b0 || size_value !== 2'd1)
        $fatal(1, "voice image size failed");
    send_voice_byte(8'hA5); send_voice_byte(8'h18); send_voice_byte(8'h00); send_voice_byte(8'hBD);
    repeat(30) @(posedge clk);
    if (size_toggle !== 1'b1 || size_value !== 2'd2)
        $fatal(1, "voice next image size failed");
    send_voice_byte(8'hA5); send_voice_byte(8'h0B); // interrupted frame
    send_voice_byte(8'hA5); send_voice_byte(8'h0D); send_voice_byte(8'h06); send_voice_byte(8'hAE);
    repeat(30) @(posedge clk);
    if (music_select_toggle !== 1'b1 || music_select_index !== 4'd5)
        $fatal(1, "voice frame resynchronization failed");
    send_voice_byte(8'hA5); send_voice_byte(8'h11); send_voice_byte(8'h00); send_voice_byte(8'hB4);
    send_voice_byte(8'hA5); send_voice_byte(8'h12); send_voice_byte(8'h00); send_voice_byte(8'hB7);
    repeat(30) @(posedge clk);
    if (!saw_music_prev || !saw_music_next) $fatal(1, "voice music skip failed");
    if (volume_level !== 10 || volume_muted !== 0) $fatal(1,"volume defaults failed");
    // Set from Bluetooth, mute from ASRPRO, and require a valid reported state.
    send_byte(8'hA5); send_byte(8'h20); send_byte(8'h05); send_byte(8'h80);
    send_voice_byte(8'hA5); send_voice_byte(8'h23); send_voice_byte(8'h01); send_voice_byte(8'h87);
    repeat(12000) @(posedge clk);
    if (volume_level !== 5 || volume_muted !== 1 || !seen_volume) $fatal(1,"volume set/mute/status failed");
    send_voice_byte(8'hA5); send_voice_byte(8'h23); send_voice_byte(8'h00); send_voice_byte(8'h86);
    repeat(30) @(posedge clk);
    if(volume_level !== 5 || volume_muted !== 0) $fatal(1,"unmute did not preserve volume");
    send_byte(8'hA5); send_byte(8'h20); send_byte(8'h0B); send_byte(8'h8E);
    repeat(30) @(posedge clk);
    if(volume_level !== 5) $fatal(1,"invalid volume accepted");
    send_voice_byte(8'hA5); send_voice_byte(8'h21); send_voice_byte(8'h00); send_voice_byte(8'h84);
    repeat(30) @(posedge clk);
    if(volume_level !== 6) $fatal(1,"voice volume up failed");
    send_byte(8'hA5); send_byte(8'h22); send_byte(8'h00); send_byte(8'h87);
    repeat(30) @(posedge clk);
    if(volume_level !== 5) $fatal(1,"volume down failed");
    send_byte(8'hA5); send_byte(8'h24); send_byte(8'h00); send_byte(8'h81);
    repeat(30) @(posedge clk);
    if(volume_muted !== 1) $fatal(1,"mute toggle failed");
    send_byte(8'hA5); send_byte(8'h20); send_byte(8'h0A); send_byte(8'h8F);
    send_byte(8'hA5); send_byte(8'h21); send_byte(8'h00); send_byte(8'h84);
    repeat(30) @(posedge clk);
    if(volume_level !== 10 || volume_muted !== 0) $fatal(1,"upper bound failed");
    send_byte(8'hA5); send_byte(8'h20); send_byte(8'h00); send_byte(8'h85);
    send_byte(8'hA5); send_byte(8'h22); send_byte(8'h00); send_byte(8'h87);
    repeat(30) @(posedge clk);
    if(volume_level !== 0) $fatal(1,"lower bound failed");
    repeat(12000) @(posedge clk);
    if (voice_tx_count < 8 || (voice_tx_count % 8) != 0 ||
        first_voice_byte != 8'h5A || second_voice_byte != 8'h81)
        $fatal(1, "ASRPRO status reply failed: bytes=%0d first=%h second=%h",
               voice_tx_count, first_voice_byte, second_voice_byte);
    send_gesture_byte(8'hA5); send_gesture_byte(8'h04); send_gesture_byte(8'hFB); send_gesture_byte(8'h5A);
    send_gesture_byte(8'hA5); send_gesture_byte(8'h03); send_gesture_byte(8'hFC); send_gesture_byte(8'h5A);
    send_gesture_byte(8'hA5); send_gesture_byte(8'h01); send_gesture_byte(8'hFE); send_gesture_byte(8'h5A);
    send_gesture_byte(8'hA5); send_gesture_byte(8'h02); send_gesture_byte(8'hFD); send_gesture_byte(8'h5A);
    send_gesture_byte(8'hA5); send_gesture_byte(8'h00); send_gesture_byte(8'hFF); send_gesture_byte(8'h5A);
    send_gesture_byte(8'hA5); send_gesture_byte(8'h04); send_gesture_byte(8'h00); send_gesture_byte(8'h5A);
    send_gesture_byte(8'hA5); send_gesture_byte(8'h03); send_gesture_byte(8'hFC); send_gesture_byte(8'h00);
    repeat(30) @(posedge clk);
    if (gesture_next_count != 1 || gesture_prev_count != 1 || volume_level != 0)
        $fatal(1, "gesture navigation filtering failed");
    repeat(1050) @(posedge clk);
    if (dut.brightness_value != 4'd9 || dut.brightness_toggle != 1'b0)
        $fatal(1, "static gestures changed brightness");
    @(negedge clk); key_volume_up=1;
    @(negedge clk); key_volume_up=0;
    repeat(3) @(negedge clk);
    if (volume_level != 1) $fatal(1, "key volume up failed");
    @(negedge clk); key_volume_down=1;
    @(negedge clk); key_volume_down=0;
    repeat(3) @(negedge clk);
    if (volume_level != 0) $fatal(1, "key volume down failed");
    @(negedge clk); key_volume_value=4'd7; key_volume_set=1;
    @(negedge clk); key_volume_set=0;
    repeat(3) @(negedge clk);
    if (volume_level != 7) $fatal(1,"saved key volume failed");
    $display("W02, ASRPRO and gesture UART protocols PASS");
    $finish;
end
endmodule
