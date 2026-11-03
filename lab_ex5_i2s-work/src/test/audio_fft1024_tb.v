`timescale 1ns/1ps
module audio_fft1024_tb;
  reg clk=0, rst=1, sample_valid=0;
  reg signed [23:0] sample=0;
  reg [6:0] bar_addr=0;
  wire [5:0] bar_level;
  wire spectrum_ready;
  integer n, i, best_bar, best_level;
  real phase;
  always #5 clk=~clk;
  audio_fft1024 dut(.clk(clk),.rst(rst),.sample_valid(sample_valid),
                    .sample(sample),.bar_addr(bar_addr),
                    .bar_level(bar_level),.spectrum_ready(spectrum_ready));
  task tone(input integer hz);
    begin
      rst=1;
      repeat(3) @(negedge clk);
      rst=0;
      for(n=0;n<1024;n=n+1) begin
        phase=6.283185307179586*hz*n/48000.0;
        @(negedge clk) begin
          sample=$rtoi($sin(phase)*5000000.0);
          sample_valid=1;
        end
        @(negedge clk) sample_valid=0;
      end
      wait(spectrum_ready);
      best_bar=0;
      best_level=0;
      for(i=0;i<80;i=i+1) begin
        @(negedge clk) bar_addr=i;
        #1;
        if(bar_level>best_level) begin
          best_level=bar_level;
          best_bar=i;
        end
      end
      $display("%0d Hz: max bar %0d level %0d",hz,best_bar,best_level);
      if(best_level==0) $fatal(1,"FFT bars stayed at zero");
    end
  endtask
  initial begin
    tone(100);
    tone(4000);
    $finish;
  end
endmodule
