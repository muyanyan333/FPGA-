`timescale 1ns/1ps
// Same video-clock domain as the recognized state. No last-gesture latch.
module gesture_sevenseg #(parameter CLK_HZ=25000000)(
 input wire clk,rst,input wire [2:0] gesture,
 output wire [7:0] seg_sel,seg_data
);
 wire [7:0] d0=gesture==1 ? 8'hf9 : 8'hff; // 1
 wire [7:0] d1=gesture==2 ? 8'ha4 : 8'hff; // 2
 wire [7:0] d3=gesture==4 ? 8'hc7 : 8'hff; // L
 wire [7:0] d4=gesture==5 ? 8'haf : 8'hff; // seven-segment lowercase r
 wire [7:0] scanned_sel,scanned_data;
 wire valid=gesture==1 || gesture==2 || gesture==4 || gesture==5;
 seg_scan #(.CLK_FREQ(CLK_HZ),.BLANK_COUNT(CLK_HZ/500000>0 ? CLK_HZ/500000 : 1)) scanner(
 .clk(clk),.rst_n(!rst),.seg_sel(scanned_sel),.seg_data(scanned_data),
 .seg_data_0(d0),.seg_data_1(d1),.seg_data_2(8'hff),.seg_data_3(d3),
 .seg_data_4(d4),.seg_data_5(8'hff),.seg_data_6(8'hff),.seg_data_7(8'hff));
 // Gate by both current gesture and selected digit, clearing an old slot
 // immediately when the recognized state changes (even during a scan).
 wire selected=(gesture==1 && scanned_sel==8'hfe) ||
               (gesture==2 && scanned_sel==8'hfd) ||
               (gesture==4 && scanned_sel==8'hf7) ||
               (gesture==5 && scanned_sel==8'hef);
 assign seg_sel=!rst && valid && selected ? scanned_sel : 8'hff;
 assign seg_data=!rst && valid && selected ?
                 (gesture==1 ? d0 : gesture==2 ? d1 : gesture==4 ? d3 : d4) : 8'hff;
endmodule
