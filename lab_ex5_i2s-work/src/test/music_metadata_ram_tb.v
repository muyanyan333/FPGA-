`timescale 1ns/1ps
// Exercise the shared metadata RAM at the scanner/playback boundary. In
// particular track 16 must remain distinct from track 1 and from lyrics.
module music_metadata_ram_tb;
reg clk=0,rst=1,wv=0,lv=0;
reg [4:0] id=1;
reg [7:0] lyric_id=1;
reg [3:0] selected=0;
reg [31:0] wbytes=0,lbytes=0,wlba=0,llba=0,wcluster=0;
integer n;
always #5 clk=~clk;
sd_card_bmp dut(.clk(clk),.rst(rst),.video_mode(1'b0),.music_mode(1'b0),
 .key_next(1'b1),.key_next_event(1'b0),.key_mode(1'b1),.key_mode_toggle(1'b0),
 .edit_active(1'b0),.image_size_step(1'b0),.image_aspect_step(1'b0),.image_size_edit(1'b0),
 .remote_size_set(1'b0),.remote_aspect_set(1'b0),.remote_select_valid(1'b0),
 .remote_auto(1'b0),.remote_manual(1'b0),.remote_next(1'b0),.remote_prev(1'b0),
 .music_prev_toggle(1'b0),.music_next_toggle(1'b0),.remote_music_prev(1'b0),
 .remote_music_next(1'b0),.remote_music_select(1'b0),.audio_frame_tick_toggle(1'b0),
 .write_finish_toggle(1'b0),.write_req_ack(1'b0),.video_clk(clk),.SD_MISO(1'b1));
initial begin
 force dut.sd_init_done=1'b1;
 force dut.scan_done=1'b0;
 force dut.wav_item_valid=wv;force dut.lyr_item_valid=lv;
 force dut.wav_item_track_id=id;force dut.lyr_item_track_id=lyric_id;
 force dut.wav_item_no_fat_chain=1'b1;force dut.lyr_item_no_fat_chain=1'b0;
 force dut.wav_item_file_bytes=wbytes;force dut.lyr_item_file_bytes=lbytes;
 force dut.wav_item_lba=wlba;force dut.lyr_item_lba=llba;
 force dut.wav_item_cluster=wcluster;
 force dut.wav_index=selected;
 repeat(5) @(negedge clk);rst=0;
 for(n=1;n<=16;n=n+1) begin
  @(negedge clk);id=n;lyric_id=n;wbytes=777+n;wlba=10000+n;wcluster=30000+n;wv=1;
  @(negedge clk);wv=0;lbytes=888+n;llba=20000+n;lv=1;
  @(negedge clk);lv=0;
 end
 for(n=0;n<16;n=n+1) begin
  @(negedge clk);selected=n;
  repeat(6) @(negedge clk);
  if(dut.selected_wav_meta!=={1'b1,32'd778+n,32'd30001+n} ||
     dut.selected_lyr_meta!=={1'b0,32'd889+n,32'd20001+n})
   $fatal(1,"shared RAM metadata cross-contamination at track %d",n+1);
 end
 $display("PASS shared dual-port RAM: all 16 WAV/lyric pairs, time-sliced reads");$finish;
end
endmodule
