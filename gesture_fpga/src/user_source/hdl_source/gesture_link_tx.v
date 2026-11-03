`timescale 1ns/1ps
// A5 CODE ~CODE 5A, UART 9600 8N1, same domain as the vision pipeline.
module gesture_link_tx #(parameter CLK_HZ=25000000,BAUD=9600)(
 input wire clk,rst,ready,sample,input wire [1:0] pose,
 input wire swipe_valid,input wire [1:0] swipe_direction,
 output reg tx,output reg overflow
);
 localparam TICKS=(CLK_HZ+BAUD/2)/BAUD;
 reg [1:0] last_pose;reg [7:0] suppress;
 wire motion=ready && swipe_valid && (swipe_direction==1 || swipe_direction==2);
 wire static_change=ready && sample && suppress==0 && pose!=3 && pose!=last_pose;
 wire push=motion || static_change;
 wire [7:0] code=motion ? (swipe_direction==1 ? 8'd3 : 8'd4) : {6'd0,pose};
 reg [7:0] fifo[0:3];reg [1:0] wr,rd;reg [2:0] count;
 reg active;reg [7:0] current;
 reg [1:0] byte_index;reg [3:0] bit_index;
 reg [31:0] ticks;
 wire pop=!active && count!=0;
 wire accept=push && (count<4 || pop);
 function [7:0] packet_byte;
 input [1:0] i;input [7:0] c;
 begin case(i) 0:packet_byte=8'ha5;1:packet_byte=c;2:packet_byte=~c;3:packet_byte=8'h5a;endcase end
 endfunction
 wire [7:0] value=packet_byte(byte_index,current);
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   tx<=1;overflow<=0;last_pose<=0;suppress<=0;wr<=0;rd<=0;count<=0;
   active<=0;current<=0;byte_index<=0;bit_index<=0;ticks<=0;
  end else begin
   if(!ready) begin last_pose<=0;suppress<=0;end
   else begin
    if(sample) begin
     if(suppress!=0) suppress<=suppress-1'b1;

    end
    if(motion) suppress<=60;
   end
   if(accept && !motion) last_pose<=pose;
   if(accept) begin fifo[wr]<=code;wr<=wr+1'b1;end
   else if(push) overflow<=1;
   case({accept,pop}) 2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:count<=count;endcase
   if(pop) begin
    current<=fifo[rd];rd<=rd+1'b1;active<=1;byte_index<=0;bit_index<=0;
    tx<=0;ticks<=TICKS-1;
   end else if(active) begin
    if(ticks!=0) ticks<=ticks-1'b1;
    else begin
     ticks<=TICKS-1;
     if(bit_index<8) begin tx<=value[bit_index];bit_index<=bit_index+1'b1;end
     else if(bit_index==8) begin tx<=1;bit_index<=9;end
     else if(byte_index==3) begin active<=0;tx<=1;end
     else begin byte_index<=byte_index+1'b1;bit_index<=0;tx<=0;end
    end
   end
  end
 end
endmodule
