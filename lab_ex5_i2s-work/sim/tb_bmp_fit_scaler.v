`timescale 1ns/1ps
module tb_bmp_fit_scaler;
    reg clk=0, rst=1, start=0, go=0, pixel_valid=0, write_full=0;
    reg [15:0] src_width=0, src_height=0;
    reg [23:0] pixel_data=0;
    wire ready_for_pixels, write_en, done, overflow;
    wire [23:0] write_data;
    integer x, y, count, errors, test_case, cycles;
    integer x0, x1;
    reg [23:0] expected;

    always #5 clk=~clk;
    bmp_fit_scaler dut(
        .clk(clk),.rst(rst),.start(start),.go(go),
        .src_width(src_width),.src_height(src_height),
        .pixel_valid(pixel_valid),.pixel_data(pixel_data),
        .write_full(write_full),.ready_for_pixels(ready_for_pixels),
        .write_en(write_en),.write_data(write_data),.done(done),.overflow(overflow)
    );

    always @(posedge clk) if (!rst && write_en) begin
        if (test_case == 1)
            expected = {8'((count%640)/2),8'((count/640)/2),8'h5a};
        else if ((count/640) < 60 || (count/640) >= 420)
            expected = 24'd0;
        else begin
            x0 = ((count%640)*2) % 256;
            x1 = ((count%640)*2+1) % 256;
            expected = {8'((x0+x1)/2),8'(((count/640)-60)*2+1),8'h5a};
        end
        if (write_data !== expected && errors < 12) begin
            $display("FAIL case=%0d pixel=%0d got=%h expected=%h",test_case,count,write_data,expected);
            errors=errors+1;
        end
        count=count+1;
    end

    task run_case;
        input integer w, h, which;
        begin
            @(negedge clk); rst=1; go=0; start=0; pixel_valid=0;
            count=0; errors=0; test_case=which;
            repeat(4) @(negedge clk);
            rst=0; src_width=w; src_height=h; start=1;
            @(negedge clk); start=0; go=1;
            wait(ready_for_pixels);
            for (y=0; y<h; y=y+1)
                for (x=0; x<w; x=x+1) begin
                    @(negedge clk); pixel_data={8'(x),8'(y),8'h5a}; pixel_valid=1;
                    @(negedge clk); pixel_valid=0;
                    repeat(14) @(negedge clk);
                end
            cycles=0;
            while (!done && cycles<1000000) begin
                @(negedge clk); cycles=cycles+1;
            end
            repeat(4) @(negedge clk);
            if (done && count==307200 && errors==0 && !overflow)
                $display("PASS scaler %0dx%0d -> 640x480",w,h);
            else
                $display("FAIL scaler %0dx%0d done=%b count=%0d errors=%0d overflow=%b",w,h,done,count,errors,overflow);
        end
    endtask

    initial begin
        run_case(320,240,1);
        run_case(1280,720,2);
        $finish;
    end
endmodule
