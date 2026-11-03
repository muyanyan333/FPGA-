`timescale 1ns/1ps
module tb_ov2640_sccb;
  reg clk=0, rst=1;
  wire scl, reset_n, pwdn, done, error;
  tri1 sda; // SCCB write ninth bits may float high (Don't-Care)
  always #10 clk=~clk;
  ov2640_sccb_init #(.CLK_HZ(1000),.TICK_DIV(2)) dut(
    .clk(clk),.rst(rst),.scl(scl),.sda(sda),
    .reset_n(reset_n),.pwdn(pwdn),.done(done),.error(error)
  );
  initial begin
    repeat(4) @(negedge clk); rst=0;
    wait(done || error);
    if (error || !reset_n || pwdn) $fatal(1,"SCCB init failed");
    $display("PASS OV2640 SCCB VGA init");
    $finish;
  end
  initial begin #20000000; $fatal(1,"timeout"); end
endmodule
