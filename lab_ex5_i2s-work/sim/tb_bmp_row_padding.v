`timescale 1ns/1ps
module tb_bmp_row_padding;
    reg clk=0, rst=1, sd_valid=0;
    reg [7:0] sd_data=0;
    wire pixel_valid;
    wire [23:0] pixel;
    integer i, pixels, errors;
    always #5 clk=~clk;

    bmp_read dut(
        .clk(clk),.rst(rst),.scan_start(1'b0),.scan_start_sector(32'd0),
        .scan_max_sector(32'd0),.scan_target_count(5'd7),
        .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),
        .bmp_width(16'd640),.bmp_height(16'd480),
        .write_req_ack(1'b0),.scale_ready(1'b1),
        .sd_sec_read_data(sd_data),.sd_sec_read_data_valid(sd_valid),
        .sd_sec_read_end(1'b0),.bmp_data_wr_en(pixel_valid),.bmp_data(pixel)
    );
    always @(posedge clk) if (pixel_valid) begin
        if (pixels < 321 && pixel !== 24'h111111) errors=errors+1;
        if (pixels >= 321 && pixel !== 24'h222222) errors=errors+1;
        pixels=pixels+1;
    end
    initial begin
        pixels=0; errors=0;
        repeat(3) @(negedge clk);
        rst=0;
        dut.state=4'd7;
        dut.width=321; dut.height=240; dut.pixel_offset=54; dut.file_len=200000;
        for(i=0;i<54+964*2;i=i+1) begin
            @(negedge clk);
            sd_valid=1;
            if(i<54) sd_data=0;
            else if(i<54+963) sd_data=8'h11;
            else if(i==54+963) sd_data=8'hee;
            else sd_data=8'h22;
        end
        @(negedge clk); sd_valid=0;
        repeat(4) @(negedge clk);
        if(pixels==642 && errors==0) $display("PASS BMP 321-pixel rows and padding");
        else $display("FAIL BMP padding pixels=%0d errors=%0d",pixels,errors);
        $finish;
    end
endmodule
