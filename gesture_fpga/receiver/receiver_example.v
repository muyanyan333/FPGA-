// Generic receiver-board top. Assign clk/rst_n/gesture_rx and function outputs
// to the receiving board's own pins; set CLK_HZ to its actual clock frequency.
module receiver_example #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,gesture_rx,
 output wire open_pulse,fist_pulse,left_pulse,right_pulse,
 output wire [7:0] last_code,output wire code_valid
);
 gesture_link_rx #(.CLK_HZ(CLK_HZ),.BAUD(9600)) u_rx(
  .clk(clk),.rst(!rst_n),.rx(gesture_rx),
  .gesture_code(last_code),.gesture_valid(code_valid),
  .open_pulse(open_pulse),.fist_pulse(fist_pulse),
  .left_pulse(left_pulse),.right_pulse(right_pulse));
 // Use *_pulse as a clock-enable in this clk domain. Do not use it as a clock.
endmodule
