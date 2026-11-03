`timescale 1ns/1ps
// LYR2 reader test: header validation, title block, 500 ms frame advance,
// double-banked frame switch and restart.
module tb_lyric_title;
    reg clk = 0;
    reg rst = 1, start = 0, restart = 0, pcm_tick = 0;
    always #5 clk = ~clk;
    reg video_clk = 0;
    always #13 video_clk = ~video_clk;

    wire [31:0] sd_addr;
    reg [7:0] sd_data = 0;
    reg sd_valid = 0, sd_end = 0;
    wire req;
    wire pixel_on, title_on, frame_valid, title_valid;
    wire err;

    reg [7:0] mem [0:4095];
    integer i, r, errors = 0, ticks;

    // File: LBA 100, header | title | frame0 | frame1 | frame2.
    initial begin
        for (i = 0; i < 4096; i = i + 1) mem[i] = 8'h00;
        // LYR1 / v2 / flags 0 / 512x16 / 500 ms / 3 frames / 1500 ms / offset 1024
        mem[0]="L"; mem[1]="Y"; mem[2]="R"; mem[3]="1";
        mem[4]=8'd2; mem[5]=8'd0;
        mem[6]=8'd0; mem[7]=8'd2;       // width 512 little-endian
        mem[8]=8'd16; mem[9]=8'd0;      // height 16
        mem[10]=8'hf4; mem[11]=8'h01;   // 500
        mem[12]=8'd3; mem[13]=8'd0; mem[14]=8'd0; mem[15]=8'd0;
        mem[16]=8'hdc; mem[17]=8'h05; mem[18]=8'd0; mem[19]=8'd0; // 1500
        mem[20]=8'd0; mem[21]=8'd4; mem[22]=8'd0; mem[23]=8'd0;   // 1024
        // Title block: each row's high byte is FF, low byte is 00.
        for (r = 0; r < 256; r = r + 1) begin
            mem[512 + r*2]     = 8'hff;
            mem[512 + r*2 + 1] = 8'h00;
        end
        // Frames.
        for (i = 1024; i < 2048; i = i + 1) mem[i] = 8'haa;
        for (i = 2048; i < 3072; i = i + 1) mem[i] = 8'h55;
        for (i = 3072; i < 4096; i = i + 1) mem[i] = 8'hf0;
    end

    // Simple sector-streaming model.  One byte per clock, then sd_read_end.
    reg busy = 0, cooldown = 0;
    reg [31:0] active_addr;
    integer pos;
    always @(posedge clk) begin
        if (rst) begin
            busy <= 0; cooldown <= 0; pos <= 0;
            sd_valid <= 0; sd_end <= 0; active_addr <= 0;
        end else begin
            sd_end <= 0;
            if (cooldown) begin
                // Give the reader one cycle to publish the next sector address
                // (as the real SD controller does when starting a new CMD17).
                cooldown <= 0;
                sd_valid <= 0;
            end else if (!busy) begin
                sd_valid <= 0;
                if (req) begin
                    busy <= 1;
                    active_addr <= sd_addr;
                    pos <= 0;
                end
            end else if (pos < 512) begin
                sd_data <= mem[(active_addr - 32'd100) * 512 + pos];
                sd_valid <= 1;
                pos <= pos + 1;
            end else begin
                sd_valid <= 0;
                sd_end <= 1;
                busy <= 0;
                cooldown <= 1;
            end
        end
    end

    exfat_lyric_bitmap_reader dut(
        .clk(clk), .rst(rst), .start(start), .restart(restart),
        .first_lba(32'd100), .file_bytes(32'd4096), .no_fat_chain(1'b1),
        .pcm_frame_tick(pcm_tick), .video_clk(video_clk),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .sd_sec_read(req), .sd_sec_read_addr(sd_addr),
        .sd_data(sd_data), .sd_data_valid(sd_valid), .sd_read_end(sd_end),
        .pixel_on(pixel_on), .title_pixel_on(title_on),
        .frame_valid(frame_valid), .title_valid(title_valid),
        .lyric_error(err)
    );

    reg [10:0] pixel_x = 0;
    reg [9:0]  pixel_y = 0;

    task check_pixel;
        input expected;
        input [255:0] label;
        begin
            @(posedge video_clk);
            #1;
            if (pixel_on !== expected) begin
                $display("FAIL %0s: pixel_on=%b expected %b", label, pixel_on, expected);
                errors = errors + 1;
            end else
                $display("PASS %0s: pixel_on=%b", label, pixel_on);
        end
    endtask

    task tick_500ms;
        begin
            for (ticks = 0; ticks < 24000; ticks = ticks + 1) begin
                @(negedge clk); pcm_tick = 1;
                @(negedge clk); pcm_tick = 0;
            end
        end
    endtask

    initial begin
        #1;
        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);
        start = 1; repeat(2) @(posedge clk); start = 0;

        // Wait for the first frame and title.
        for (i = 0; i < 5000 && !(frame_valid && title_valid); i = i + 1)
            @(posedge clk);
        if (!frame_valid || !title_valid) begin
            $display("FAIL: frame/title not valid (err=%b)", err);
            errors = errors + 1;
        end else
            $display("PASS: header, title and frame 0 loaded");

        // Frame 0 is 0xAA everywhere: local (10,3) -> byte 193 bit 5 = 1.
        pixel_x = 11'd74; pixel_y = 10'd5;
        repeat(4) @(posedge video_clk);
        check_pixel(1'b1, "frame0 bit");

        // Title row 10, local x=1 -> byte 20 (0xFF) bit 6 = 1; x=9 -> 0x00.
        pixel_x = 11'd617; pixel_y = 10'd122;
        repeat(4) @(posedge video_clk);
        if (title_on !== 1'b1) begin
            $display("FAIL: title high bit");
            errors = errors + 1;
        end else
            $display("PASS: title high bit");
        pixel_x = 11'd625;
        repeat(4) @(posedge video_clk);
        if (title_on !== 1'b0) begin
            $display("FAIL: title low bit");
            errors = errors + 1;
        end else
            $display("PASS: title low bit");

        // Advance to frame 1 (0x55): bit 5 becomes 0.
        pixel_x = 11'd74; pixel_y = 10'd5;
        tick_500ms();
        for (i = 0; i < 3000; i = i + 1) @(posedge clk);
        check_pixel(1'b0, "frame1 bit");

        // Advance to frame 2 (0xF0): bit 5 becomes 1 again.
        tick_500ms();
        for (i = 0; i < 3000; i = i + 1) @(posedge clk);
        check_pixel(1'b1, "frame2 bit");

        // Restart and start again -> frame 0 (0xAA) is visible again.
        restart = 1; repeat(2) @(posedge clk); restart = 0;
        repeat(4) @(posedge video_clk);
        start = 1; repeat(2) @(posedge clk); start = 0;
        for (i = 0; i < 5000 && !frame_valid; i = i + 1)
            @(posedge clk);
        pixel_x = 11'd74; pixel_y = 10'd5;
        repeat(4) @(posedge clk);
        check_pixel(1'b1, "restart frame0 bit");
        if (!title_valid) begin
            $display("FAIL: title not valid after restart");
            errors = errors + 1;
        end

        // Reject incompatible geometry and oversized frame counts instead of
        // reading outside the file (a left shift used to wrap at 32 bits).
        @(negedge clk); restart = 1;
        repeat(2) @(negedge clk); restart = 0;
        mem[4] = 8'd1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        repeat(700) @(negedge clk);
        if (!err) $fatal(1, "old lyric version accepted");
        @(negedge clk); restart = 1;
        repeat(2) @(negedge clk); restart = 0;
        mem[4] = 8'd2;
        mem[15] = 8'h40;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        repeat(700) @(negedge clk);
        if (!err) $fatal(1, "overflowing frame count accepted");
        if (errors == 0) $display("LYRIC TITLE TEST PASS (asynchronous clocks + malformed headers)");
        else $fatal(1, "LYRIC TITLE TEST FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
