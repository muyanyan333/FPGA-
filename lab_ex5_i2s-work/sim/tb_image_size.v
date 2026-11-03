`timescale 1ns/1ps
module tb_image_size;
    reg clk=0,rst=1,start=0,go=0,valid=0,full=0;
    always #5 clk=~clk;
    reg [15:0] w=0,h=0;
    reg [1:0] mode=0;
    reg [1:0] aspect=0;
    wire ready,we,done,overflow;
    wire [23:0] data;
    integer count=0, errors=0, fw,fh,px,py,x,y,cycles;
    reg [23:0] expected;
    bmp_fit_scaler #(.USE_VIEWPORT(1),.USE_ASPECT(1)) dut(
        .clk(clk),.rst(rst),.start(start),.go(go),.src_width(w),.src_height(h),
        .viewport_mode(mode),.pixel_valid(valid),.pixel_data(24'h61a5cf),
        .aspect_mode(aspect),
        .write_full(full),.ready_for_pixels(ready),.write_en(we),
        .write_data(data),.done(done),.overflow(overflow)
    );
    always @(posedge clk) if(!rst && we) begin
        expected = ((count%640)>=px && (count%640)<px+fw &&
                    (count/640)>=py && (count/640)<py+fh) ? 24'h61a5cf : 24'd0;
        if(data!==expected) begin
            if(errors<4) $display("pixel mismatch mode=%0d pixel=%0d got=%h",mode,count,data);
            errors=errors+1;
        end
        count=count+1;
    end
    task run;
        input integer sw,sh,m,a,fitw,fith;
        begin
            @(negedge clk); rst=1; valid=0;start=0;go=0;full=0;
            count=0;errors=0;fw=fitw;fh=fith;px=(640-fw)/2;py=(480-fh)/2;
            repeat(4) @(negedge clk);
            rst=0;w=sw;h=sh;mode=m;aspect=a;start=1;go=1;
            @(negedge clk);start=0;go=0;
            wait(ready);
            // Deliberately change the external mode mid-frame: size must
            // remain latched until the next start.
            mode=(m+1)%3;
            aspect=(a+1)%4;
            for(y=0;y<sh;y=y+1) for(x=0;x<sw;x=x+1) begin
                @(negedge clk);valid=1;
                @(negedge clk);valid=0;
                repeat(14) @(negedge clk);
            end
            cycles=0;
            while(!done && cycles<1000000) begin @(negedge clk);cycles=cycles+1; end
            if(!done || count!=307200 || errors || overflow)
                $fatal(1,"size=%0d fit=%0dx%0d count=%0d errors=%0d overflow=%b",m,fw,fh,count,errors,overflow);
            $display("IMAGE SIZE PASS mode=%0d source=%0dx%0d content=%0dx%0d",m,sw,sh,fw,fh);
        end
    endtask
    initial begin
        run(320,240,0,0,640,480);
        run(320,240,1,0,512,384);
        run(320,240,2,0,320,240);
        run(320,480,2,0,160,240);
        run(640,360,1,0,512,288);
        run(320,240,0,1,640,480);
        run(320,240,0,2,480,360);
        run(640,360,0,2,640,360);
        run(640,360,0,3,480,270);
        run(320,240,2,3,240,180);
        run(640,335,0,3,480,251);
        run(320,668,0,2,172,360);
        $finish;
    end
    initial begin #500000000; $fatal(1,"scaler test timeout"); end
endmodule
