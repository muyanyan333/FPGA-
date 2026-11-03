`timescale 1ns/1ps
// Add this file to the OTHER FPGA. Set CLK_HZ to that board's clock frequency.
module gesture_link_rx #(parameter CLK_HZ=50000000,BAUD=9600)(
 input wire clk,rst,rx,output reg [7:0] gesture_code,output reg gesture_valid,
 output wire open_pulse,fist_pulse,left_pulse,right_pulse
);
 localparam TICKS=(CLK_HZ+BAUD/2)/BAUD;
 (* async_reg="true" *) reg [1:0] sync;
 reg [1:0] state,packet_state;
 reg [31:0] timer,timeout;
 reg [2:0] bit_index;reg [7:0] data,received,code;
 reg byte_valid;
 assign open_pulse=gesture_valid && gesture_code==1;
 assign fist_pulse=gesture_valid && gesture_code==2;
 assign left_pulse=gesture_valid && gesture_code==3;
 assign right_pulse=gesture_valid && gesture_code==4;
 always @(posedge clk or posedge rst) begin
  if(rst) begin sync<=3;state<=0;timer<=0;bit_index<=0;data<=0;received<=0;byte_valid<=0;end
  else begin
   sync<={sync[0],rx};byte_valid<=0;
   case(state)
   0:if(!sync[1]) begin state<=1;timer<=TICKS/2-1;end
   1:if(timer!=0) timer<=timer-1'b1;
     else if(sync[1]) state<=0;
     else begin state<=2;timer<=TICKS-1;bit_index<=0;end
   2:if(timer!=0) timer<=timer-1'b1;
     else begin
      data[bit_index]<=sync[1];timer<=TICKS-1;
      if(bit_index==7) state<=3;else bit_index<=bit_index+1'b1;
     end
   3:if(timer!=0) timer<=timer-1'b1;
     else begin state<=0;if(sync[1]) begin received<=data;byte_valid<=1;end end
   endcase
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin packet_state<=0;timeout<=0;code<=0;gesture_code<=0;gesture_valid<=0;end
  else begin
   gesture_valid<=0;
   if(packet_state!=0) begin
    if(timeout>=TICKS*60) begin packet_state<=0;timeout<=0;end
    else timeout<=timeout+1'b1;
   end
   if(byte_valid) begin
    timeout<=0;
    case(packet_state)
    0:if(received==8'ha5) packet_state<=1;
    1:begin code<=received;packet_state<=2;end
    2:if(received==~code) packet_state<=3;
      else packet_state<=received==8'ha5 ? 1 : 0;
    3:begin
     packet_state<=received==8'ha5 ? 1 : 0;
     if(received==8'h5a && code<=4) begin gesture_code<=code;gesture_valid<=1;end
    end
    endcase
   end
  end
 end
endmodule
