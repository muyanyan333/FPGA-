`timescale 1ns/1ps
// Exercise the shared SD arbiter, WAV prefill and scaler together, before
// audio is permitted to drain. Video must be committed before audio starts.
module video_startup_tb #(parameter REAL_WRITER=0, COMPACT=0, REAL_EOF=0, TWO_FRAMES=0, STUCK_FINAL=0, INDEXED=0, DYNAMIC=0, FPS=30, MISSING_FINAL_COMMIT=0, DELAY_FINAL_COMMIT=0, PAUSE_AUDIO=0);
localparam SAMPLES=DYNAMIC ? 48000/FPS : 2400;
reg clk=0,rst=1,finish_toggle=0,memclk=0;
wire ack,full,writer_finish,app_write,fifo_reset;
wire [8:0] used;
wire [31:0] fifo_data;
wire [20:0] app_address;
integer committed=0;
always #5 memclk=~memclk;
reg [12:0] audio_count=0;
integer consumed=0, sample_div=0, commit_delay=0, pause_cycles=0;
reg prefilled=0, audio_toggle=0, pause_done=0;
reg [7:0] data=0;
reg data_valid=0,read_end=0,busy=0;
integer p,writes=0,video_sectors=0,audio_sectors=0;
reg [31:0] address;
wire req,wr,audio_wr,valid;
wire [31:0] wrdata;
sd_card_bmp #(.VIDEO_EOF_STALL_CYCLES(20000)) dut(.clk(clk),.rst(rst),.video_mode(1'b1),.music_mode(1'b0),
 .key_next(1'b1),.key_next_event(1'b0),.key_mode(1'b1),.key_mode_toggle(1'b0),
 .edit_active(1'b0),.image_size_step(1'b0),.image_aspect_step(1'b0),.image_size_edit(1'b0),
 .remote_size_set(1'b0),.remote_aspect_set(1'b0),.remote_select_valid(1'b0),
 .remote_auto(1'b0),.remote_manual(1'b0),.remote_next(1'b0),.remote_prev(1'b0),
 .music_prev_toggle(1'b0),.music_next_toggle(1'b0),.remote_music_prev(1'b0),
 .remote_music_next(1'b0),.remote_music_select(1'b0),.audio_frame_tick_toggle(audio_toggle),
 .write_finish_toggle(finish_toggle),.write_req_ack(ack),.video_clk(clk),.SD_MISO(1'b1),
 .audio_fifo_count(audio_count),.audio_fifo_full(1'b0),.audio_frame_valid(audio_wr),
 .write_full(full),.write_req(req),.write_en(wr),.write_data(wrdata),.display_valid(valid));
generate if(REAL_WRITER) begin
 wfifo_32_32_512 fifo(.clkw(clk),.clkr(memclk),.rst(fifo_reset),.we(wr),.di(wrdata),
  .re(app_write),.dout(fifo_data),.full_flag(full),.rdusedw(used));
 frame_fifo_write #(.BURST_SIZE(256)) writer(.rst(rst),.mem_clk(memclk),
  .Sdr_init_done(!rst),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
  .App_wr_en(app_write),.App_wr_addr(app_address),.write_req(req),.write_v_flip(1'b1),
  .write_req_ack(ack),.write_finish(writer_finish),.write_addr_0(21'd0),
  .write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(2'd0),.write_len(21'd307200),.fifo_aclr(fifo_reset),.rdusedw(used));
 always @(posedge memclk) begin
  if(app_write) committed=committed+1;
  if(writer_finish) finish_toggle<=~finish_toggle;
 end
end else begin
 assign ack=req;assign full=0;
end endgenerate
always #10 clk=~clk;
always @(negedge clk) begin
 if(commit_delay>0) begin
  commit_delay=commit_delay-1;
  if(commit_delay==0) finish_toggle=~finish_toggle;
 end
 if(!rst && audio_wr) audio_count=audio_count+1;
 if(REAL_EOF && !rst && valid) begin
  if(audio_count>=256) prefilled=1;
  if(PAUSE_AUDIO && consumed>=400 && !pause_done) begin
   pause_cycles=pause_cycles+1;
   if(dut.video_playback_done || dut.video_tail_stalled) $fatal(1,"user pause caused false EOF watchdog");
   if(pause_cycles==50000) pause_done=1;
  end else if(prefilled && !dut.video_audio_hold) begin
   sample_div=sample_div+1;
   if(sample_div==100) begin
    sample_div=0;
    if(audio_count>0) begin audio_count=audio_count-1;consumed=consumed+1;audio_toggle=~audio_toggle;end
   end
  end
 end
 if(!rst && wr) begin
  writes=writes+1;
  if(writes%307200==0 && !REAL_WRITER && !(MISSING_FINAL_COMMIT && writes==614400)) begin
   if(DELAY_FINAL_COMMIT && writes==614400) commit_delay=2500;
   else finish_toggle=~finish_toggle;
  end
 end
end
function [7:0] sector_byte;
input [31:0] a; input integer i;integer n;
begin
 n=DYNAMIC ? ((a-1000)*512+i)%77824 : (a-1000)*512+i;
 sector_byte=0;
 if(a>=1000) begin
  if(INDEXED) begin
   if(n<4) sector_byte=0;
   else if(n<772) sector_byte=((n-4)%3)==0 ? 255 : 0;
   else if(n==772 && DYNAMIC) sector_byte=FPS;
   else if(n<1024) sector_byte=0;
   else sector_byte=0;
  end else sector_byte=i%2 ? 8'hf8 : 0;
 end
 else if(a==100) begin
  case(i)
   0:sector_byte="R";1:sector_byte="I";2,3:sector_byte="F";
   8:sector_byte="W";9:sector_byte="A";10:sector_byte="V";11:sector_byte="E";
   12:sector_byte="f";13:sector_byte="m";14:sector_byte="t";15:sector_byte=" ";
   16:sector_byte=16;20:sector_byte=1;22:sector_byte=2;
   24:sector_byte=8'h80;25:sector_byte=8'hbb;29:sector_byte=8'hee;30:sector_byte=2;
   32:sector_byte=4;34:sector_byte=16;
   36:sector_byte="d";37:sector_byte="a";38:sector_byte="t";39:sector_byte="a";
   40,41,42,43:sector_byte=(REAL_EOF ? (TWO_FRAMES ? 2*SAMPLES*4 : SAMPLES*4) : 192000)>>((i-40)*8);
  endcase
 end
end
endfunction
always @(negedge clk) if(!rst && dut.sd_sec_read && !busy) begin
 busy=1;address=dut.sd_sec_read_addr;
 if(address>=1000) video_sectors=video_sectors+1;else audio_sectors=audio_sectors+1;
 for(p=0;p<512;p=p+1) begin
  repeat(15) @(negedge clk);data=sector_byte(address,p);data_valid=1;
  @(negedge clk);data_valid=0;
 end
 @(negedge clk);read_end=1;@(negedge clk);read_end=0;
 wait(!dut.sd_sec_read);@(negedge clk);busy=0;
end
initial begin
 force dut.sd_init_done=1'b1;force dut.scan_done=1'b0;force dut.bmp_sd_read=1'b0;
 force dut.wav_item_valid=1'b0;force dut.lyr_item_valid=1'b0;force dut.mvi_item_valid=1'b0;
 force dut.sd_sec_read_data=data;force dut.sd_sec_read_data_valid=data_valid;force dut.sd_sec_read_end=read_end;
 force dut.fs_volume_lba=0;force dut.fs_heap_offset=100;force dut.fs_fat_offset=24;force dut.fs_spc_shift=10;
 repeat(5) @(negedge clk);rst=0;
 force dut.video_found=1'b1;force dut.video_audio_found=1'b1;
 force dut.video_lba=1000;force dut.video_cluster=3;force dut.video_bytes=DYNAMIC ? (TWO_FRAMES ? 155648 : 77824) : INDEXED ? (TWO_FRAMES ? 154624 : 77824) : COMPACT ? (TWO_FRAMES ? 153600 : 76800) : 153600;
 force dut.video_rgb332=COMPACT != 0;force dut.video_indexed=INDEXED != 0;force dut.video_dynamic=DYNAMIC != 0;
 force dut.video_contiguous=1'b1;force dut.video_audio_meta=REAL_EOF ? {1'b1,((TWO_FRAMES ? 32'd2 : 32'd1)*SAMPLES*32'd4+32'd44),32'd2} : {1'b1,32'd192044,32'd2};
 force dut.scan_done=1'b1;
 wait(valid);repeat(5) @(negedge clk);
 if(writes!=307200 || video_sectors!=(INDEXED ? 152 : (COMPACT ? 150 : 300)) || audio_sectors!=0 || dut.wav_error)
  $fatal(1,"startup totals pixels=%d sectors=%d audio=%d",writes,video_sectors,audio_sectors);
 wait(audio_count>=256);
 if(REAL_WRITER && committed!=307200) $fatal(1,"incorrect SDRAM commit %d",committed);
 if(!dut.wav_stream_valid || dut.wav_error) $fatal(1,"soundtrack did not start after first frame");
 if(dut.video_playback_done) $fatal(1,"premature exit while audio remains buffered");
 if(REAL_EOF) begin
 wait(dut.wav_eof_pending);
 if(consumed>=(TWO_FRAMES ? 2*SAMPLES : SAMPLES)) $fatal(1,"late EOF");
 if(MISSING_FINAL_COMMIT) begin
  wait(writes==614400 && dut.video_audio_hold && dut.video_reader.state==6);
  if(audio_count==0) $fatal(1,"test failed to retain buffered tail audio");
  repeat(100000) @(negedge clk);
  if(!dut.video_playback_done)
   $fatal(1,"EOF deadlock: final commit absent, hold=%b buffered=%0d consumed=%0d",dut.video_audio_hold,audio_count,consumed);
  if(dut.video_reader.frame_present || !dut.video_status[2])
   $fatal(1,"stalled final frame must exit as error without being presented");
  $display("PASS missing final commit: bounded error exit without presenting incomplete frame");$finish;
 end
 if(STUCK_FINAL) force dut.video_active=1'b1;
 wait(audio_count==0);
 if(consumed!=(TWO_FRAMES ? 2*SAMPLES : SAMPLES)) $fatal(1,"lost soundtrack samples %d",consumed);
 if(dut.video_tail_stalled) $fatal(1,"normal playback or short commit delay triggered watchdog");
 if(PAUSE_AUDIO && !pause_done) $fatal(1,"pause scenario was not exercised");
 end else begin force dut.video_audio_eof_seen=1'b1;force audio_count=0;end
 repeat(1000) @(negedge clk);
 if(dut.video_playback_done) $fatal(1,"missing final I2S drain guard");
 wait(dut.video_playback_done);
 $display("PASS shared SD startup + EOF drain: video committed first, soundtrack then prefills");$finish;
end
initial begin #100000000;$fatal(1,"startup timeout state=%d owner=%d vsec=%d pixels=%d audio=%d",dut.video_reader.state,dut.sd_owner,video_sectors,writes,audio_count);end
endmodule
