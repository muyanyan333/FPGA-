`timescale 1ns/1ps
module frame_slide_read_tb;
    reg mem_clk=0, rst=1, read_req=0;
    reg slide_active=0;
    reg [9:0] slide_progress=0;
    reg [1:0] read_addr_index=0, slide_old_index=0, slide_new_index=1;
    wire read_req_ack, read_finish, App_rd_en;
    wire [20:0] App_rd_addr;
    integer n, expected, x, y, p, direction;
    frame_fifo_read #(.OUTPUT_WIDTH(640)) dut(
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .Sdr_rd_en(1'b0),
        .App_wr_busy(1'b0), .O_rd_busy(),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .read_req(read_req), .read_req_ack(read_req_ack), .read_finish(read_finish),
        .read_addr_0(21'd0), .read_addr_1(21'd307200),
        .read_addr_2(21'd0), .read_addr_3(21'd0),
        .read_addr_index(read_addr_index), .read_len(21'd3840),
        .slide_active(slide_active), .slide_progress(slide_progress),
        .slide_old_index(slide_old_index), .slide_new_index(slide_new_index),
        .fifo_aclr(), .wrusedw(9'd0)
    );
    always #4 mem_clk=~mem_clk;
    always @(posedge mem_clk) if(!rst && App_rd_en) begin
        x=n%640; y=n/640;
        if(slide_active) begin
            if(x<slide_progress)
                expected=slide_new_index*307200+y*640+640-slide_progress+x;
            else expected=slide_old_index*307200+y*640+x-slide_progress;
        end else expected=read_addr_index*307200+n;
        if(App_rd_addr!==expected[20:0])
            $fatal(1,"p=%0d n=%0d addr=%0d expected=%0d",slide_progress,n,App_rd_addr,expected);
        n=n+1;
    end
    task check_frame;
        begin
            n=0;
            repeat(4) @(negedge mem_clk);
            read_req=1;
            wait(read_req_ack);
            repeat(4) @(negedge mem_clk);
            read_req=0;
            wait(read_finish);
            @(negedge mem_clk);
            if(n!=3840) $fatal(1,"read count %0d",n);
            repeat(4) @(negedge mem_clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge mem_clk); rst=0;
        check_frame; read_addr_index=1; check_frame;
        slide_active=1;
        for(direction=0;direction<2;direction=direction+1) begin
            slide_old_index=direction; slide_new_index=1-direction;
            read_addr_index=slide_old_index;
            for(p=0;p<=640;p=p+32) begin
                slide_progress=p; check_frame;
            end
        end
        $display("PASS: 168960 SDRAM pixel addresses, both banks, all slide steps and row/burst boundaries");
        $finish;
    end
    initial begin #10000000; $fatal(1,"timeout"); end
endmodule
