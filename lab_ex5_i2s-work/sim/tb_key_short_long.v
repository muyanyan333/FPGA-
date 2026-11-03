`timescale 1ns/1ps
module tb_key_short_long;
reg clk = 0;
reg rst_n = 0;
reg key_n = 1;
wire short_pulse, long_pulse;
integer short_count = 0;
integer long_count = 0;

always #5 clk = ~clk;
always @(posedge clk) begin
    if(short_pulse) short_count = short_count + 1;
    if(long_pulse)  long_count = long_count + 1;
end

key_short_long #(
    .CLK_FREQ_HZ(1000),
    .DEBOUNCE_MS(2),
    .LONG_PRESS_MS(10)
) dut(
    .clk(clk), .rst_n(rst_n), .key_n(key_n),
    .short_pulse(short_pulse), .long_pulse(long_pulse)
);

initial begin
    #20 rst_n = 1;
    #20 key_n = 0; #70 key_n = 1; #50;
    if(short_count != 1 || long_count != 0) begin
        $display("FAIL short: short=%0d long=%0d", short_count, long_count);
        $finish_and_return(1);
    end
    key_n = 0; #180 key_n = 1; #50;
    if(short_count != 1 || long_count != 1) begin
        $display("FAIL long: short=%0d long=%0d", short_count, long_count);
        $finish_and_return(1);
    end
    // A brief bounce is ignored; an indefinitely held key fires long once.
    key_n = 0; #10 key_n = 1; #80;
    if(short_count != 1 || long_count != 1)
        $fatal(1,"bounce produced an event");
    key_n = 0; #600;
    if(short_count != 1 || long_count != 2)
        $fatal(1,"long hold repeated or missing long event");
    key_n = 1; #80;
    if(short_count != 1 || long_count != 2)
        $fatal(1,"long release generated a short event");
    $display("PASS short/long split, bounce rejection and one-shot long hold");
    $finish;
end
endmodule
