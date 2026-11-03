`timescale 1ns/1ps
// Bit-level SD CMD17/token/data/CRC model; uses the real command FSM and
// SPI shifter in mode 3. The card changes MISO on falling SCLK edges.
module spi_video_fast_read_tb #(parameter FAST_ENGINE=1);
 reg clk=0,rst=1,fast_enable=0,cmd_req=0,block_req=0,miso=1;
 reg [15:0] divider=0;
 wire cs,sclk,mosi,ack,valid,read_done,cmd_done,cmd_error,stream,stream_more,wr_req;
 wire [7:0] data,spi_in,spi_out;wire [15:0] spi_div;
 wire cs_ctrl;integer cycle=0,words=0,bit_num=7,received=0,last_valid=0,interval=0;
 reg [7:0] rx=0;time last_edge=0;integer runs=0;
 reg strict_period=1,more_connected=1;
 always #10 clk=~clk;
 sd_card_cmd command(.sys_clk(clk),.rst(rst),.spi_clk_div(divider),
  .cmd_req(cmd_req),.cmd_req_ack(cmd_done),.cmd_req_error(cmd_error),
  .cmd({8'd17,32'h12345678,8'hff}),.cmd_r1(8'h00),.cmd_data_len(16'd0),
  .block_read_req(block_req),.block_read_valid(valid),.block_read_data(data),
  .block_read_req_ack(read_done),.block_write_req(1'b0),.block_write_data(8'd0),
  .block_write_data_rd(),.block_write_req_ack(),.read_stream(stream),.read_stream_more(stream_more),
  .nCS_ctrl(cs_ctrl),.clk_div(spi_div),.spi_wr_req(wr_req),.spi_wr_ack(ack),
  .spi_data_in(spi_in),.spi_data_out(spi_out));
 spi_master #(.FAST_DIV0(FAST_ENGINE)) master(.sys_clk(clk),.rst(rst),.nCS(cs),.DCLK(sclk),.MOSI(mosi),.MISO(miso),
  .CPOL(1'b1),.CPHA(1'b1),.nCS_ctrl(cs_ctrl),.clk_div(spi_div),.wr_req(wr_req),
  .read_stream((fast_enable===1'b1)&&stream),.read_stream_more(more_connected ? stream_more : 1'bz),.wr_ack(ack),.data_in(spi_in),.data_out(spi_out));
 function [7:0] pattern(input integer n);pattern=(n*73+19)&255;endfunction
 function [7:0] card_byte(input integer n);
 begin
  if(n==6) card_byte=0;
  else if(n==10) card_byte=8'hfe;
  else if(n>=11 && n<523) card_byte=pattern(n-11);
  else if(n==523) card_byte=8'ha5;
  else if(n==524) card_byte=8'h5a;
  else card_byte=8'hff;
 end endfunction
 reg [7:0] out_byte;
 always @(negedge cs) begin words=0;bit_num=7;rx=0;end
 always @(negedge sclk) if(!rst && !cs) begin
  out_byte=card_byte(words);miso=out_byte[bit_num];
 end
 always @(posedge sclk) if(!rst && !cs) begin
  rx={rx[6:0],mosi};
  if(bit_num==0) begin
   case(words)
    0:if(rx!==8'h51) $fatal(1,"CMD17 lost %h",rx);
    1:if(rx!==8'h12) $fatal(1,"address byte 1 lost");
    2:if(rx!==8'h34) $fatal(1,"address byte 2 lost");
    3:if(rx!==8'h56) $fatal(1,"address byte 3 lost");
    4:if(rx!==8'h78) $fatal(1,"address byte 4 lost");
    default:if(rx!==8'hff) $fatal(1,"read dummy byte changed %h",rx);
   endcase
   words=words+1;bit_num=7;
  end else bit_num=bit_num-1;
 end
 always @(sclk) if(!rst && !cs) begin
  if(last_edge!=0 && $time-last_edge<20) $fatal(1,"SCLK exceeds 25MHz edge limit");
  last_edge=$time;
 end
 always @(negedge clk) if(!rst) begin
  cycle=cycle+1;
  if(cmd_error) $fatal(1,"command error");
  if(valid) begin
   if(data!==pattern(received)) $fatal(1,"data n=%0d got=%h expected=%h",received,data,pattern(received));
   if(received>0) begin
    interval=cycle-last_valid;
    if(strict_period && FAST_ENGINE && divider==0 && fast_enable===1'b1 && interval!=(more_connected ? 17 : 18)) $fatal(1,"fast byte period %0d",interval);
    if(strict_period && FAST_ENGINE && divider==0 && fast_enable!==1'b1 && interval!=21) $fatal(1,"legacy byte period changed %0d",interval);
    if(strict_period && !FAST_ENGINE && divider==0 && interval!=36) $fatal(1,"legacy SPI engine changed %0d",interval);
    if(interval<17) $fatal(1,"byte interval too short %0d",interval);
    if(divider!=0 && interval<=21) $fatal(1,"low-speed path bypassed");
   end
   last_valid=cycle;received=received+1;
  end
 end
 task initialize(input reg enable_fast,input [15:0] div);
 begin
  @(negedge clk);rst=1;cmd_req=0;block_req=0;fast_enable=enable_fast;divider=div;
  received=0;cycle=0;last_valid=0;last_edge=0;miso=1;
  repeat(5) @(negedge clk);rst=0;
  repeat(3000) @(negedge clk);
 end endtask
 task begin_block;
 begin
  @(negedge clk);received=0;last_valid=0;cmd_req=1;
  wait(cmd_done);@(negedge clk);cmd_req=0;block_req=1;
 end endtask
 task finish_block;
 begin
  wait(read_done);@(negedge clk);block_req=0;
  repeat(32) @(negedge clk);
  if(received!=512 || words!=525 || bit_num!=7 || sclk!==1'b1)
   $fatal(1,"bad payload/CRC/end received=%d words=%d bit=%d sclk=%b",received,words,bit_num,sclk);
  $display("PASS physical CMD17: video_fast=%b divider=%0d bytes=512 CRC=2 period=%0d cycles",fast_enable,divider,interval);
  runs=runs+1;
 end endtask
 task run(input reg enable_fast,input [15:0] div);
 begin initialize(enable_fast,div);begin_block;finish_block;end endtask
 task abort_block(input integer byte_number);
 begin
  begin_block;
  wait(command.state==command.S_READ && command.byte_cnt==byte_number && ack);
  @(negedge clk);rst=1;cmd_req=0;block_req=0;
  repeat(5) @(negedge clk);
  if(cs!==1'b1 || ack!==1'b0 || valid!==1'b0) $fatal(1,"reset failed at byte %0d",byte_number);
  rst=0;received=0;last_valid=0;last_edge=0;
  repeat(3000) @(negedge clk);
  begin_block;finish_block;
  $display("PASS reset at block byte %0d, subsequent CMD17 intact",byte_number);
 end endtask
 initial begin
  run(0,0);run(1,0);run(1,2);run(1'bz,0);
  // The command engine stays alive across three blocks and mode changes.
  @(negedge clk);fast_enable=1;begin_block;finish_block;
  @(negedge clk);fast_enable=0;begin_block;finish_block;
  @(negedge clk);fast_enable=1;begin_block;finish_block;
  // Mode changes may happen while a byte is shifting. No data or CRC may
  // be lost, even when the next byte uses the other handshake path.
  strict_period=0;begin_block;
  wait(received==73);@(negedge clk);fast_enable=0;
  wait(received==149);@(negedge clk);fast_enable=1;
  finish_block;strict_period=1;
  abort_block(0);abort_block(511);abort_block(512);abort_block(513);
  more_connected=0;begin_block;finish_block;
  if(runs!=13) $fatal(1,"coverage missing");$finish;
 end
 initial begin #20000000;$fatal(1,"SPI timeout word=%d bit=%d received=%d",words,bit_num,received);end
endmodule
