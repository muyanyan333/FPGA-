`timescale 1ns/1ps
module tb_music_spectrum_visual;
    reg clk=0, rst=1, frame_start=0, de=1, waveform_on=0;
    reg [10:0] x=0;
    reg [9:0] y=479;
    reg [23:0] background=24'h808080;
    reg [5:0] level=6'd1;
    wire [6:0] bar_addr;
    wire [23:0] pixel;
    music_spectrum_visual dut(.clk(clk),.rst(rst),.frame_start(frame_start),
        .de(de),.x(x),.y(y),.background(background),.level(level),
        .waveform_on(waveform_on),.bar_addr(bar_addr),.pixel(pixel));
    always #5 clk=~clk;
    initial begin
        repeat(3) @(negedge clk); rst=0;
        #1; if(bar_addr!=0 || pixel==background) $fatal(1,"first bar missing");
        x=11'd6; #1; if(pixel!=background) $fatal(1,"bar gap missing");
        x=11'd636; #1; if(bar_addr!=7'd79 || pixel==background)
            $fatal(1,"last bar missing");
        x=11'd100; y=10'd240; waveform_on=1; #1;
        if(pixel==background) $fatal(1,"waveform blend missing");
        waveform_on=0; #1;
        if(pixel!=background) $fatal(1,"background incorrectly modified");
        $display("PASS 80 full-width bars, wave blend and transparent background");
        $finish;
    end
endmodule
