`timescale 1ns/1ps
module uart_camera_status_snapshot_tb;
    parameter integer CPB = 10;
    parameter integer MODE = 1;
    reg clk = 0, rst = 1;
    reg [1:0] camera_mode = 0;
    wire uart_tx;
    wire [7:0] received;
    wire received_valid;
    integer byte_index = 0, camera_frames = 0, switches = 0;
    reg [7:0] frame [0:7];
    reg [7:0] checksum = 0;
    always #5 clk = ~clk;

    uart_image_control #(.CLK_FREQ_HZ(100_000 * CPB), .BAUD_RATE(100_000)) dut (
        .clk(clk), .rst(rst), .uart_rx(1'b1), .voice_rx(1'b1),
        .uart_tx(uart_tx), .voice_tx(),
        .image_count(5'd3), .current_index(4'd0), .auto_mode(1'b0), .scan_done(1'b1),
        .transition_effect(2'd0), .brightness_level(4'd9), .contrast_level(4'd5),
        .image_size(2'd0), .image_aspect(2'd0), .music_track_number(5'd1),
        .music_track_count(5'd1), .music_track_map(16'h0001), .music_playing(1'b1),
        .lyric_valid(1'b0), .title_valid(1'b0), .video_status(3'd3), .camera_mode(camera_mode),
        .notice_rd_clk(clk), .notice_rd_addr(10'd0)
    );
    uart_rx_byte #(.CLK_FREQ_HZ(100_000 * CPB), .BAUD_RATE(100_000)) monitor (
        .clk(clk), .rst(rst), .uart_rx(uart_tx),
        .data(received), .data_valid(received_valid)
    );

    // Observe actual serialized bytes; switch modes only after the payload has
    // reached the receiver, but before its checksum is serialized.
    always @(negedge clk) if (!rst && received_valid) begin
        frame[byte_index] = received;
        if (byte_index == 0 && received !== 8'h5A)
            $fatal(1, "bad frame header %h", received);
        if (byte_index == 2 && frame[1] == 8'h86 && switches < 2) begin
            camera_mode = camera_mode==0 ? MODE : 0;
            switches = switches + 1;
        end
        if (byte_index == 7) begin
            if (received !== checksum)
                $fatal(1, "frame %h payload=%h checksum=%h expected=%h",
                       frame[1], frame[2], received, checksum);
            if (frame[1] == 8'h86) begin
                if (frame[2] !== ((camera_frames == 1) ? MODE[7:0] : 8'd0))
                    $fatal(1, "camera update missing/out of order frame=%0d mode=%h",
                           camera_frames, frame[2]);
                camera_frames = camera_frames + 1;
                if (camera_frames == 3) begin
                    $display("PASS: mode changes 0->%0d->0 during UART frame; stable status/checksum CPB=%0d", MODE, CPB);
                    $finish;
                end
            end
            byte_index = 0;
            checksum = 0;
        end else begin
            checksum = checksum ^ received;
            byte_index = byte_index + 1;
        end
    end
    initial begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (CPB * 4000) @(negedge clk);
        $fatal(1, "timeout frames=%0d switches=%0d", camera_frames, switches);
    end
endmodule
