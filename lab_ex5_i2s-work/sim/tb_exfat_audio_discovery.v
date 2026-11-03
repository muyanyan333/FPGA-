`timescale 1ns/1ps
module tb_exfat_audio_discovery;
reg clk=0, rst=1, scan_start=0, load_start=0, sd_init_done=0;
reg [31:0] load_lba=0;
reg write_req_ack=0, sd_valid=0, sd_end=0;
reg [7:0] sd_data=0;
wire ready, scan_done, scan_found_valid, write_req, sd_read, bmp_we;
wire [31:0] found_sector, sd_addr;
wire [4:0] found_total;
wire wav_found; wire [31:0] wav_lba, wav_cluster, wav_bytes;
wire [3:0] state_code;
wire [23:0] bmp_data;
integer pos, found_pulses, timeout;
reg busy=0, cooldown=0;
reg [31:0] active_addr=0;

always #5 clk=~clk;

bmp_read dut(
 .clk(clk),.rst(rst),.ready(ready),
 .scan_start(scan_start),.scan_start_sector(0),.scan_max_sector(32'hffffffff),
 .scan_target_count(5'd7),.scan_done(scan_done),.scan_found_valid(scan_found_valid),
 .scan_found_sector(found_sector),.scan_found_total(found_total),
 .wav_found(wav_found),.wav_first_lba(wav_lba),.wav_first_cluster(wav_cluster),
 .wav_file_bytes(wav_bytes),
 .load_start(load_start),.load_sector(load_lba),.sd_init_done(sd_init_done),
 .state_code(state_code),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(write_req),.write_req_ack(write_req_ack),
 .sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),.sd_sec_read_data(sd_data),
 .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
 .bmp_data_wr_en(bmp_we),.bmp_data(bmp_data));

function [7:0] le32_byte;
 input [31:0] v; input integer n;
 begin case(n) 0:le32_byte=v[7:0];1:le32_byte=v[15:8];2:le32_byte=v[23:16];default:le32_byte=v[31:24];endcase end
endfunction

function [7:0] sector_byte;
 input [31:0] a; input integer p;
 integer ent, off, file_no;
 reg [31:0] fc;
 begin
  sector_byte=0;
  if(a==0 && p>=454 && p<=457) sector_byte=le32_byte(2048,p-454);
  else if(a==2048) begin
   case(p)
    3:sector_byte="E";4:sector_byte="X";5:sector_byte="F";6:sector_byte="A";7:sector_byte="T";
    8,9,10:sector_byte=8'h20;
    80:sector_byte=24; 88:sector_byte=128; 96:sector_byte=2;
    108:sector_byte=9; 109:sector_byte=3;
    default:sector_byte=0;
   endcase
  end else if(a==2176) begin
   ent=p/32; off=p%32; file_no=ent/3; fc=10+file_no*10;
   if(ent<15) begin
    if(ent%3==0 && off==0) sector_byte=8'h85;
    if(ent%3==1 && off==0) sector_byte=8'hc0;
    if(ent%3==1 && off==1) sector_byte=8'h02;
    if(ent%3==1 && off>=20 && off<=23) sector_byte=le32_byte(fc,off-20);
    if(ent%3==1 && file_no==4 && off>=24 && off<=27) sector_byte=le32_byte(556,off-24);
    if(ent%3==2 && off==0) sector_byte=8'hc1;
   end else if(ent==15 && off==0) sector_byte=0;
  end else if(a==2560) begin
   case(p)
    0:sector_byte="R";1:sector_byte="I";2:sector_byte="F";3:sector_byte="F";
    8:sector_byte="W";9:sector_byte="A";10:sector_byte="V";11:sector_byte="E";
   endcase
  end else if(a==2240 || a==2320 || a==2400 || a==2480) begin
   case(p)
    0:sector_byte="B";1:sector_byte="M";
    2:sector_byte=8'h36;3:sector_byte=8'h10;4:sector_byte=8'h0e;
    10:sector_byte=54;
    18:sector_byte=8'h80;19:sector_byte=8'h02;
    22:sector_byte=8'he0;23:sector_byte=8'h01;
    26:sector_byte=1;
    28:sector_byte=24;
    default:sector_byte=0;
   endcase
  end
 end
endfunction

always @(posedge clk) begin
 sd_valid<=0; sd_end<=0;
 if(cooldown) cooldown<=0;
 else if(!busy && sd_read) begin busy<=1; pos<=0; active_addr<=sd_addr; end
 else if(busy) begin
  if(pos<512) begin sd_valid<=1; sd_data<=sector_byte(active_addr,pos); pos<=pos+1; end
  else begin sd_end<=1; busy<=0; cooldown<=1; end
 end
 if(scan_found_valid) found_pulses<=found_pulses+1;
end

initial begin
 found_pulses=0; timeout=0;
 repeat(5) @(posedge clk); rst<=0; sd_init_done<=1;
 repeat(3) @(posedge clk); scan_start<=1;
 @(posedge clk); scan_start<=0;
 while(!scan_done && timeout<20000) begin @(posedge clk); timeout=timeout+1; end
 repeat(5) @(posedge clk);
 if(scan_done && found_total==4 && found_pulses==4 && wav_found && wav_lba==2560 && wav_cluster==50 && wav_bytes==556) $display("PASS exFAT BMPs plus WAV=%0d",found_total);
 else $fatal(1,"FAIL done=%0d total=%0d pulses=%0d wav=%b lba=%0d cluster=%0d bytes=%0d state=%0d addr=%0d",scan_done,found_total,found_pulses,wav_found,wav_lba,wav_cluster,wav_bytes,state_code,sd_addr);
 load_lba<=2480; load_start<=1;
 @(posedge clk); load_start<=0;
 repeat(8) @(posedge clk);
 if(dut.load_current_cluster==40 && dut.load_no_fat_chain==1)
   $display("PASS BMP load candidate lookup");
 else $fatal(1,"FAIL BMP load candidate lookup cluster=%0d",dut.load_current_cluster);
 $finish;
end
endmodule
