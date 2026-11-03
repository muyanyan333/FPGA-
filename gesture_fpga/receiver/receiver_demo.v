module receiver_demo(input wire clk,rst_n,gesture_rx,output reg [3:0] led);
 wire [7:0] code;wire valid,open_pulse,fist_pulse,left_pulse,right_pulse;
 gesture_link_rx #(.CLK_HZ(50000000),.BAUD(9600)) u_rx(
 .clk(clk),.rst(!rst_n),.rx(gesture_rx),.gesture_code(code),.gesture_valid(valid),
 .open_pulse(open_pulse),.fist_pulse(fist_pulse),.left_pulse(left_pulse),.right_pulse(right_pulse));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) led<=0;
  else if(valid) case(code)
   0:led<=0;1:led<=4'b0001;2:led<=4'b0010;
   3:led<=4'b0100;4:led<=4'b1000;
   default:led<=led;
  endcase
 end
 // Replace/extend the code above with your own functions.
 // open_pulse/fist_pulse/left_pulse/right_pulse last ONE 50MHz clock cycle.
endmodule
