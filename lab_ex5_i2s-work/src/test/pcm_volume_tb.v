`timescale 1ns/1ps
module pcm_volume_tb;
reg clk=0, rst=1;
always #5 clk=~clk;
reg [3:0] volume=10;
reg muted=0;
reg [31:0] data=32'h7fff8000;
wire rd;
pcm_i2s_tx dut(.mclk(clk),.rst(rst),.enable(1'b1),
    .volume_level(volume),.volume_muted(muted),
    .bclk(),.lrck(),.dout(),.fifo_rd_en(rd),.fifo_rd_data(data),.fifo_empty(1'b0));
task check_frame;
    input [3:0] level;
    input mute;
    input [31:0] expected;
    begin
        @(negedge clk); volume=level; muted=mute;
        repeat(10) @(posedge clk);
        @(posedge rd); repeat(4) @(posedge clk); #1;
        if(dut.next_word !== expected)
            $fatal(1,"PCM scaling failed level=%d muted=%b got=%h expected=%h",level,mute,dut.next_word,expected);
    end
endtask
initial begin
    repeat(4) @(posedge clk); @(negedge clk); rst=0;
    check_frame(10,0,32'h7fff8000);
    check_frame(5,0,32'h3fffc000);
    check_frame(1,0,32'h0cfff300);
    check_frame(0,0,32'h00000000);
    check_frame(7,1,32'h00000000);
    check_frame(10,0,32'h7fff8000);
    @(negedge clk); data=32'hffff0001;
    check_frame(5,0,32'hffff0000);
    $display("PCM volume PASS: stereo signed scaling, unity, half, low, zero, mute, restore, negative samples");
    $finish;
end
initial begin #1000000; $fatal(1,"PCM test timeout"); end
endmodule
