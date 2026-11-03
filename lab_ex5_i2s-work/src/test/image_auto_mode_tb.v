`timescale 1ns/1ps
module image_auto_mode_tb;
reg clk=0,rst=1,music=1,auto_cmd=0,manual_cmd=0,next_cmd=0;
always #5 clk=~clk;
sd_card_bmp #(.CLK_FREQ_HZ(10),.USE_KEY_NEXT_EVENT(1)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_next_event(1'b0),.key_mode(1'b1),
 .key_mode_toggle(1'b0),.edit_active(1'b0),.image_size_step(1'b0),.image_size_edit(1'b0),
 .image_aspect_step(1'b0),.remote_size_set(1'b0),.remote_size_value(2'b0),
 .remote_aspect_set(1'b0),.remote_aspect_value(2'b0),.remote_select_valid(1'b0),
 .remote_select_index(4'b0),.remote_auto(auto_cmd),.remote_manual(manual_cmd),
 .remote_next(next_cmd),.remote_prev(1'b0),.music_mode(music),
 .music_prev_toggle(1'b0),.music_next_toggle(1'b0),.remote_music_prev(1'b0),
 .remote_music_next(1'b0),.remote_music_select(1'b0),.remote_music_index(4'b0),
 .audio_frame_tick_toggle(1'b0),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_finish_toggle(1'b0),.display_released_bank(2'b0),.audio_fifo_count(13'b0),
 .audio_fifo_full(1'b0),.video_clk(clk),.pixel_x(11'b0),.pixel_y(10'b0),
 .write_req_ack(1'b0),.write_full(1'b0),.SD_MISO(1'b1));
task pulse_auto;
 begin @(negedge clk); auto_cmd=1; @(negedge clk); auto_cmd=0; end
endtask
task pulse_manual;
 begin @(negedge clk); manual_cmd=1; @(negedge clk); manual_cmd=0; end
endtask
initial begin
 force dut.sd_init_done=1; force dut.scan_done=1;
 force dut.bmp_ready=1; force dut.scan_found_valid=0;
 force dut.write_finish_pulse=0;
 repeat(4) @(negedge clk); rst=0;
 dut.scan_kicked=1; dut.first_image_committed=1;
 dut.display_valid=1; dut.img_found_count=3; dut.img_idx=0;
 dut.load_busy=0; dut.auto_mode_r=0;
 repeat(250) begin @(posedge clk); #1;
   if(dut.target_req_pending || dut.load_busy || dut.img_idx!=0 || dut.auto_cnt!=0)
      $fatal(1,"Manual music mode auto-switched");
 end
 music=0;
 repeat(35) begin @(posedge clk); #1;
   if(dut.target_req_pending || dut.load_busy) $fatal(1,"Manual image mode auto-switched");
 end
 music=1; repeat(5) @(negedge clk);
 pulse_auto();
 repeat(105) @(negedge clk);
 if(!dut.load_busy || !dut.load_is_auto) $fatal(1,"Auto music slideshow did not start");
 pulse_manual();
 force dut.write_finish_pulse=1; @(negedge clk); force dut.write_finish_pulse=0;
 if(dut.img_idx!=0 || dut.auto_mode_r) $fatal(1,"Cancelled automatic load committed");
 // A queued auto switch at the exact stop command must also be cancelled.
 pulse_auto();
 @(negedge clk); dut.auto_cnt=99;
 @(negedge clk); manual_cmd=1;
 @(negedge clk); manual_cmd=0;
 repeat(3) @(negedge clk);
 if(dut.target_req_pending || dut.load_busy) $fatal(1,"Pending auto request survived stop");
 // Explicit next remains available in manual mode.
 @(negedge clk); next_cmd=1; @(negedge clk); next_cmd=0;
 repeat(3) @(negedge clk);
 if(!dut.load_busy || dut.load_is_auto || dut.load_idx!=1) $fatal(1,"Manual next failed");
 $display("Image auto mode PASS: manual music/image hold, auto advance, pending/inflight cancellation, explicit next");
 $finish;
end
initial begin #100000; $fatal(1,"auto mode test timeout"); end
endmodule
