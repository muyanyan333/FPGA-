`timescale 1ns/1ps
module uart_video_control_tb;
reg clk=0,rst=1,rx=1;
reg [1:0] mode=0;
wire request;
wire [1:0] requested_mode;
wire [3:0] volume;
wire muted;
integer requests=0;
always #5 clk=~clk;
uart_image_control #(.CLK_FREQ_HZ(1000000),.BAUD_RATE(100000)) dut(
 .clk(clk),.rst(rst),.uart_rx(rx),.voice_rx(1'b1),
 .camera_mode(mode),.video_status(3'd3),.camera_mode_request(request),
 .camera_mode_value(requested_mode),.volume_level(volume),.volume_muted(muted),
 .image_count(5'd1),.current_index(4'd0),.auto_mode(1'b0),.scan_done(1'b1),
 .transition_effect(2'd0),.brightness_level(4'd9),.contrast_level(4'd5),
 .image_size(2'd0),.image_aspect(2'd0),.music_track_number(5'd1),
 .music_track_count(5'd1),.music_track_map(16'd1),.music_playing(1'b1),
 .lyric_valid(1'b0),.title_valid(1'b0),.notice_rd_clk(clk),.notice_rd_addr(10'd0));
always @(posedge clk) if(request) begin mode<=requested_mode;requests=requests+1;end
task send_byte;
 input [7:0] value;
 integer bit_no;
 begin
  @(negedge clk);rx=0;repeat(10) @(negedge clk);
  for(bit_no=0;bit_no<8;bit_no=bit_no+1) begin rx=value[bit_no];repeat(10) @(negedge clk);end
  rx=1;repeat(15) @(negedge clk);
 end
endtask
task command;
 input [7:0] cmd,arg;
 begin send_byte(8'ha5);send_byte(cmd);send_byte(arg);send_byte(8'ha5^cmd^arg);repeat(10) @(negedge clk);end
endtask
initial begin
 repeat(5) @(negedge clk);rst=0;
 command(8'h20,4);command(8'h23,1);command(8'h1d,2);
 if(mode!==2 || volume!==4 || !muted) $fatal(1,"video mode / retained volume / mute failed");
 command(8'h1d,3);
 if(requests!=1 || mode!==2) $fatal(1,"invalid mode accepted");
 command(8'h21,0);
 if(volume!==5 || muted) $fatal(1,"volume up or unmute failed");
 command(8'h20,10);command(8'h21,0);
 if(volume!==10) $fatal(1,"volume upper clamp failed");
 command(8'h22,0);command(8'h20,11);
 if(volume!==9) $fatal(1,"volume down or invalid level failed");
 send_byte(8'ha5);send_byte(8'h20);send_byte(0);send_byte(0);
 repeat(20) @(negedge clk);
 if(volume!==9) $fatal(1,"bad checksum accepted");
 $display("PASS actual UART RX: video command, invalid modes, volume/mute retention, bounds, checksum rejection");$finish;
end
initial begin #2000000;$fatal(1,"UART command timeout");end
endmodule
