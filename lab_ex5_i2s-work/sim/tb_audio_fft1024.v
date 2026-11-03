`timescale 1ns/1ps
module tb_audio_fft1024;
    reg clk=0, rst=1, sample_valid=0;
    reg signed [23:0] sample=0;
    reg [6:0] bar_addr=0;
    wire [5:0] bar_level;
    wire spectrum_ready;
    integer n, cycles;
    reg [5:0] peak, neighbor;
    audio_fft1024 dut(.clk(clk), .rst(rst), .sample_valid(sample_valid),
        .sample(sample), .bar_addr(bar_addr), .bar_level(bar_level),
        .spectrum_ready(spectrum_ready));
    always #5 clk=~clk;
    initial begin
        repeat(4) @(negedge clk); rst=0;
        for(n=0;n<1024;n=n+1) begin
            @(negedge clk);
            sample_valid=1;
            sample=$rtoi(4000000.0*$sin(6.283185307179586*21.0*n/1024.0));
        end
        @(negedge clk); sample_valid=0;
        cycles=0;
        while(!spectrum_ready && cycles<50000) begin
            @(negedge clk); cycles=cycles+1;
        end
        if(!spectrum_ready) $fatal(1,"FFT did not finish");
        bar_addr=7'd20; #1; peak=bar_level;
        bar_addr=7'd50; #1; neighbor=bar_level;
        if(peak<6'd20 || peak<=neighbor+6'd10)
            $fatal(1,"FFT peak bar=%0d distant bar=%0d",peak,neighbor);
        $display("PASS FFT 1024 tone peak=%0d distant=%0d cycles=%0d",peak,neighbor,cycles);
        $finish;
    end
endmodule
