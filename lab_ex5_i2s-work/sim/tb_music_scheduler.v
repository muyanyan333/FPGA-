`timescale 1ns/1ps
// Isolate the scheduler from SPI/SDRAM. Force only peripheral status wires;
// keep the catalogue, track selection and restart logic under test intact.
module tb_music_scheduler;
    reg clk=0, rst=1, next_toggle=0;
    reg [12:0] fifo_count=0;
    reg eof_pulse=0, wav_request=0;
    reg size_edit=0,size_event=0;
    reg aspect_event=0;
    reg remote_music_select=0;
    reg remote_music_prev=0, remote_music_next=0;
    reg [3:0] remote_music_index=4'd1;
    wire [1:0] image_aspect;
    wire [1:0] image_size;
    wire reset_toggle;
    always #10 clk=~clk;
    sd_card_bmp #(.CLK_FREQ_HZ(50000000)) dut(
        .clk(clk), .rst(rst), .music_mode(1'b1),
        .image_size_edit(size_edit),.image_size_step(size_event),
        .current_image_size(image_size),.key_next_event(1'b0),
        .image_aspect_step(aspect_event),.current_image_aspect(image_aspect),
        .remote_size_set(1'b0), .remote_size_value(2'd0),
        .remote_aspect_set(1'b0), .remote_aspect_value(2'd0),
        .music_prev_toggle(1'b0), .music_next_toggle(next_toggle),
        .remote_music_prev(remote_music_prev), .remote_music_next(remote_music_next),
        .remote_music_select(remote_music_select), .remote_music_index(remote_music_index),
        .audio_frame_tick_toggle(1'b0),
        .audio_fifo_count(fifo_count), .audio_fifo_full(1'b0),
        .music_fifo_reset_toggle(reset_toggle),
        .video_clk(clk), .pixel_x(11'd0), .pixel_y(10'd0),
        .key_next(1'b1), .key_mode(1'b1), .key_mode_toggle(1'b0),
        .edit_active(1'b0), .write_req_ack(1'b0), .write_full(1'b0),
        .write_finish_toggle(1'b0), .remote_select_valid(1'b0),
        .remote_select_index(4'd0), .remote_auto(1'b0),
        .remote_manual(1'b0), .remote_next(1'b0), .remote_prev(1'b0),
        .bmp_width(16'd640), .bmp_height(16'd480), .SD_MISO(1'b1)
    );
    initial begin
        force dut.sd_init_done=1'b1;
        force dut.scan_done=1'b1;
        force dut.bmp_ready=1'b1;
        force dut.bmp_sd_read=1'b0;
        force dut.lyr_sd_read=1'b0;
        force dut.wav_sd_read=wav_request;
        force dut.wav_eof=eof_pulse;
        force dut.wav_item_valid=1'b0;
        force dut.lyr_item_valid=1'b0;
        force dut.sd_sec_read_end=1'b0;
        repeat(4) @(negedge clk); rst=0;
        // Sparse tracks 02 and 06; only track 02 has lyrics.
        dut.wav_track_valid[1]=1; dut.wav_track_valid[5]=1;
        dut.lyr_track_valid[1]=1;
        dut.wav_count=2; dut.lyr_count=1;
        dut.wav_index=1; dut.tracks_initialized=1;
        repeat(10) @(negedge clk);
        if (!dut.lyric_catalog_ok) $fatal(1,"unrelated missing lyric disabled track 02");
        fifo_count=128; eof_pulse=1;
        @(negedge clk); eof_pulse=0;
        repeat(20) @(negedge clk);
        if (dut.wav_index != 1 || reset_toggle) $fatal(1,"EOF truncated buffered audio");
        fifo_count=0;
        repeat(4200) @(negedge clk);
        if (dut.wav_index != 5 || !reset_toggle) $fatal(1,"EOF failed to advance after drain");
        if (dut.lyric_catalog_ok) $fatal(1,"missing lyric incorrectly matched");
        // A manual request must not clear FIFO during an outstanding sector.
        force dut.sd_owner=2'd2;
        wav_request=1; next_toggle=1;
        repeat(10) @(negedge clk);
        if (!dut.wav_restart_pending || !reset_toggle) $fatal(1,"unsafe manual restart");
        wav_request=0; force dut.sd_owner=2'd0;
        repeat(10) @(negedge clk);
        if (dut.wav_restart_pending || reset_toggle) $fatal(1,"restart did not complete at boundary");
        remote_music_select=1;
        @(negedge clk); remote_music_select=0;
        @(negedge clk);
        if (dut.wav_index != 1)
            $fatal(1,"remote track selection failed: index=%0d pending=%b", dut.wav_index, dut.wav_restart_pending);
        remote_music_next=1;
        @(negedge clk); remote_music_next=0;
        @(negedge clk);
        if (dut.wav_index != 5) $fatal(1,"voice next track failed");
        remote_music_prev=1;
        @(negedge clk); remote_music_prev=0;
        @(negedge clk);
        if (dut.wav_index != 1) $fatal(1,"voice previous track failed");
        // Per-image settings remain independent and coalesce preview requests.
        force dut.bmp_ready=1'b0;
        force dut.display_valid=1'b1;
        force dut.img_idx=4'd0;
        size_edit=1;size_event=1;
        @(negedge clk);size_event=0;
        @(negedge clk);
        if(image_size!=1 || dut.target_req_idx!=0 || !dut.target_req_pending)
            $fatal(1,"first image resize request");
        force dut.img_idx=4'd1;
        @(negedge clk);
        if(image_size!=0) $fatal(1,"size leaked to another image");
        size_event=1; @(negedge clk);size_event=0;
        @(negedge clk);
        size_event=1; @(negedge clk);size_event=0;
        @(negedge clk);
        if(image_size!=2) $fatal(1,"second image resize");
        force dut.img_idx=4'd0;
        @(negedge clk);
        if(image_size!=1) $fatal(1,"saved per-image size lost");
        repeat(10) @(negedge clk);
        if(dut.auto_cnt!=0) $fatal(1,"H3 did not freeze slideshow");
        size_event=1; @(negedge clk);size_event=0;
        @(negedge clk);
        size_event=1; @(negedge clk);size_event=0;
        @(negedge clk);
        if(image_size!=0 || dut.image_size_table[1]!=2)
            $fatal(1,"size wrap or per-image isolation");
        aspect_event=1; @(negedge clk);aspect_event=0;
        @(negedge clk);
        if(image_aspect!=1 || image_size!=0 || dut.image_aspect_table[1]!=0)
            $fatal(1,"aspect/size settings not isolated");
        repeat(3) begin
            aspect_event=1; @(negedge clk);aspect_event=0;
            @(negedge clk);
        end
        if(image_aspect!=0) $fatal(1,"four aspect modes do not wrap");
        // A different image was already in flight when H3 opened. Its SDRAM
        // completion must not switch the displayed image under the editor.
        dut.disp_buf_idx=0;
        force dut.load_busy=1'b1;
        force dut.source_done_seen=1'b1;
        force dut.load_idx=4'd1;
        force dut.pending_buf_idx=2'd1;
        force dut.write_finish_pulse=1'b1;
        @(negedge clk);
        if(dut.disp_buf_idx!=0) $fatal(1,"in-flight background displaced H3 image");
        $display("MUSIC SCHEDULER PASS (pairing, EOF, restart, per-image sizes)");
        $finish;
    end
    initial begin #200000; $fatal(1,"scheduler timeout"); end
endmodule
