`timescale 1ns/1ps
module tb_seg_scan_blank;
reg clk = 0;
reg rst_n = 0;
wire [7:0] seg_sel;
wire [7:0] seg_data;
reg [7:0] prev_sel;
reg [7:0] seen;
integer i;

always #5 clk = ~clk;

seg_scan #(.SCAN_COUNT(3), .BLANK_COUNT(2)) dut(
    .clk(clk), .rst_n(rst_n), .seg_sel(seg_sel), .seg_data(seg_data),
    .seg_data_0(8'hc0), .seg_data_1(8'hf9),
    .seg_data_2(8'ha4), .seg_data_3(8'hb0),
    .seg_data_4(8'h99), .seg_data_5(8'h92),
    .seg_data_6(8'h82), .seg_data_7(8'hf8)
);

initial begin
    prev_sel = 8'hff;
    seen = 8'h00;
    #20 rst_n = 1;
    for(i = 0; i < 100; i = i + 1) begin
        @(posedge clk); #1;
        if(seg_sel != 8'hff) begin
            seen = seen | ~seg_sel;
            if(prev_sel != 8'hff && prev_sel != seg_sel) begin
                $display("FAIL direct digit switch %h -> %h", prev_sel, seg_sel);
                $finish_and_return(1);
            end
        end
        prev_sel = seg_sel;
    end
    if(seen != 8'hff) begin
        $display("FAIL digits not all scanned: %h", seen);
        $finish_and_return(1);
    end
    $display("PASS inter-digit blanking");
    $finish;
end
endmodule
