`timescale 1ns/1ps
module video_catalog_tb;
parameter COMPACT=0, INDEXED=0, DYNAMIC=0;
wire dynamic_detected;
wire indexed_detected;
wire compact_detected;
reg clk=0,rst=1,scan_start=0,load_start=0,sd_valid=0,sd_end=0;
reg [7:0] sd_data=0;
reg busy=0;
wire scan_done,found,sd_read,write_req,wav_item,mvi_item;
wire [31:0] sd_addr,wlba,mlba,mbytes;
wire [4:0] wav_id;
integer pos,found_count=0,wav_count=0,mvi_count=0;
always #5 clk=~clk;
bmp_read dut(
 .clk(clk),.rst(rst),.ready(),.scan_start(scan_start),
 .scan_start_sector(32'd0),.scan_max_sector(32'hffffffff),.scan_target_count(5'd16),
 .scan_done(scan_done),.scan_found_valid(found),
 .load_start(load_start),.load_sector(32'd2400),.sd_init_done(!rst),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_req(write_req),
 .write_req_ack(1'b0),.scale_ready(1'b1),
 .wav_item_valid(wav_item),.wav_item_track_id(wav_id),.wav_item_lba(wlba),
 .mvi_item_valid(mvi_item),.mvi_item_rgb332(compact_detected),.mvi_item_indexed(indexed_detected),.mvi_item_dynamic(dynamic_detected),.mvi_item_lba(mlba),.mvi_item_file_bytes(mbytes),
 .sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),.sd_sec_read_data(sd_data),
 .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end));
function [7:0] byte32;
 input [31:0] n;input integer b;
 begin byte32=(n>>(8*b))&255;end
endfunction
function [7:0] sector_byte;
 input [31:0] a;input integer p;
 integer ent,off,fn;
 reg [31:0] cluster,len;
 begin
  sector_byte=0;ent=p/32;off=p%32;fn=ent/3;
  if(a==0 && p>=454 && p<=457) sector_byte=byte32(2048,p-454);
  else if(a==2048) begin
   case(p)
    3:sector_byte="E";4:sector_byte="X";5:sector_byte="F";6:sector_byte="A";7:sector_byte="T";
    8,9,10:sector_byte=32;80:sector_byte=24;88:sector_byte=128;96:sector_byte=2;
    108:sector_byte=9;109:sector_byte=3;
   endcase
  end else if(a==2176 || a==2560) begin
   cluster=a==2176 ? (fn==4 ? 50 : 10+fn*10) : (fn==0 ? 60 : 70);
   len=a==2176 ? 921654 : (fn==0 ? 192044 : 307200);
   if((a==2176 && ent<15)||(a==2560 && ent<6)) begin
    if(ent%3==0 && off==0) sector_byte=8'h85;
    if(a==2176 && fn==4 && ent%3==0 && off==4) sector_byte=8'h10;
    if(ent%3==1 && off==0) sector_byte=8'hc0;
    if(ent%3==1 && off==1) sector_byte=2;
    if(ent%3==1 && off>=20 && off<=23) sector_byte=byte32(cluster,off-20);
    if(ent%3==1 && off>=24 && off<=27) sector_byte=byte32(len,off-24);
    if(ent%3==2 && off==0) sector_byte=8'hc1;
    if(a==2560 && ent%3==2 && off==2) sector_byte="0";
    if(a==2560 && ent%3==2 && off==4) sector_byte=fn==0 ? "0" : "1";
   end
  end else if(a==2240 || a==2320 || a==2400 || a==2480) begin
   case(p)
    0:sector_byte="B";1:sector_byte="M";2:sector_byte=8'h36;3:sector_byte=8'h10;4:sector_byte=8'h0e;
    10:sector_byte=54;18:sector_byte=8'h80;19:sector_byte=2;
    22:sector_byte=8'he0;23:sector_byte=1;26:sector_byte=1;28:sector_byte=24;
   endcase
  end else if(a==2640) begin
   case(p)0:sector_byte="R";1:sector_byte="I";2,3:sector_byte="F";
    8:sector_byte="W";9:sector_byte="A";10:sector_byte="V";11:sector_byte="E";endcase
  end else if(a==2720) begin
   case(p)0:sector_byte="M";1:sector_byte="V";2:sector_byte="I";3:sector_byte=DYNAMIC ? "4" : INDEXED ? "3" : (COMPACT ? "2" : "1");endcase
  end
 end
endfunction
always @(negedge clk) if(!rst && sd_read && !busy) begin
 busy=1;
 for(pos=0;pos<512;pos=pos+1) begin
  @(negedge clk);sd_valid=1;sd_data=sector_byte(sd_addr,pos);
 end
 @(negedge clk);sd_valid=0;sd_end=1;
 @(negedge clk);sd_end=0;
 wait(!sd_read);@(negedge clk);busy=0;
end
always @(posedge clk) if(!rst) begin
 if(found) found_count=found_count+1;
 if(wav_item) begin
  if(wav_id!==17 || wlba!==2640) $fatal(1,"00.wav metadata mismatch id=%d LBA=%d",wav_id,wlba);
  wav_count=wav_count+1;
 end
 if(mvi_item) begin
  if(dynamic_detected !== (DYNAMIC != 0)) $fatal(1,"wrong dynamic palette profile");
  if(indexed_detected !== (INDEXED != 0)) $fatal(1,"wrong indexed profile");
  if(compact_detected !== (COMPACT != 0)) $fatal(1,"wrong MVI pixel profile");
  if(mlba!==2720 || mbytes!==307200) $fatal(1,"MVI metadata mismatch");
  mvi_count=mvi_count+1;
 end
end
initial begin
 repeat(5) @(negedge clk);rst=0;
 @(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
 wait(scan_done);repeat(5) @(negedge clk);
 if(found_count!=4 || wav_count!=1 || mvi_count!=1)
  $fatal(1,"catalog counts bmp=%d wav=%d mvi=%d",found_count,wav_count,mvi_count);
 load_start=1;@(negedge clk);load_start=0;
 wait(write_req);
 if(dut.candidate_meta_latched[31:0]!==2400 || dut.load_current_cluster!==30)
  $fatal(1,"synchronous catalog lookup selected wrong image");
 $display("PASS synchronous catalog: 4 BMP, reserved 00.wav, MVI, non-first image reload");$finish;
end
initial begin #2000000;$fatal(1,"catalog timeout state=%d addr=%d",dut.state,sd_addr);end
endmodule
