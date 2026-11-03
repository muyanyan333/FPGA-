`timescale 1ns/1ps
module image_transition_control_tb;
    reg clk=0, rst=1, read_req=0, display_valid=0, geometry_edit=0;
    reg [1:0] committed_bank=0, effect=2;
    wire [1:0] read_bank, old_bank, new_bank, released_bank;
    wire slide_active;
    wire [9:0] slide_progress;
    wire [8:0] brightness;
    integer i;
    image_transition_control dut(.*);
    always #5 clk=~clk;
    task frame;
        begin
            @(negedge clk); read_req=1;
            repeat(8) @(negedge clk);
            read_req=0;
            repeat(8) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0; display_valid=1;
        frame;
        // A newly completed image must never leak into the current frame.
        committed_bank=1;
        repeat(20) @(negedge clk);
        if (read_bank!=0 || slide_active || released_bank!=0)
            $fatal(1,"mid-frame descriptor change");
        for(i=1;i<20;i=i+1) begin
            frame;
            if (!slide_active || slide_progress!=i*32 ||
                old_bank!=0 || new_bank!=1 || released_bank!=0)
                $fatal(1,"slide frame %0d invalid",i);
        end
        frame;
        if(slide_active || read_bank!=1 || released_bank!=1 || brightness!=256)
            $fatal(1,"slide did not commit cleanly");
        // Reverse direction and fade: swap bank only while fully black.
        effect=1; repeat(4) @(negedge clk); committed_bank=0;
        for(i=1;i<=16;i=i+1) begin
            frame;
            if(brightness!=256-i*16 || released_bank!=1)
                $fatal(1,"fade-out frame %0d invalid",i);
            if(i<16 && read_bank!=1) $fatal(1,"premature fade swap");
        end
        if(read_bank!=0) $fatal(1,"black frame did not switch bank");
        for(i=1;i<=16;i=i+1) begin
            frame;
            if(brightness!=i*16 || read_bank!=0)
                $fatal(1,"fade-in frame %0d invalid",i);
        end
        if(released_bank!=0) $fatal(1,"old bank never released");
        effect=0; committed_bank=1;
        repeat(5) @(negedge clk);
        if(read_bank!=0) $fatal(1,"cut changed mid-frame");
        frame;
        if(read_bank!=1 || released_bank!=1) $fatal(1,"cut failed");
        effect=2; repeat(4) @(negedge clk); committed_bank=0;
        frame; geometry_edit=1;
        frame;
        if(slide_active || read_bank!=0 || released_bank!=0 || brightness!=256)
            $fatal(1,"geometry preview cancellation failed");
        $display("PASS: frame-boundary cut/slide/fade, protected old bank, preview cancellation");
        $finish;
    end
endmodule
