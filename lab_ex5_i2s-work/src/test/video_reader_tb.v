`timescale 1ns/1ps
module video_reader_tb;
    parameter COMPACT=0, INDEXED=0, DYNAMIC=0, FPS=30;
    localparam SECTORS=DYNAMIC ? 304 : COMPACT ? (INDEXED ? 302 : 300) : 600;
    localparam TICKS=DYNAMIC ? 48000/FPS : COMPACT ? 2400 : 6000;
    wire pacing_wait;
    reg clk=0, rst=1, start=0, pcm_tick=0;
    reg contiguous=1;
    always #5 clk=~clk;
    wire frame_start, scale_go, write_req, pixel_valid, sd_read;
    wire [23:0] pixel_data;
    wire [31:0] sd_addr;
    wire active, error, frame_present, scale_ready, scale_done, wr_en;
    wire [23:0] wr_data;
    wire overflow;
    reg ack=0, committed=0, data_valid=0, read_end=0;
    reg [7:0] data=0;
    integer sectors=0, pixels=0, writes=0, presented=0, fat_reads=0;
    function [23:0] palette_color(input integer n);
 begin case(n%8)
 0:palette_color=24'h000000;1:palette_color=24'hff0000;
 2:palette_color=24'h00ff00;3:palette_color=24'h0000ff;
 4:palette_color=24'hffffff;5:palette_color=24'h00ffff;
 6:palette_color=24'hff00ff;7:palette_color=24'hffff00;
 endcase end
 endfunction
 function [7:0] indexed_byte(input integer absolute_byte);
 integer n,frame;
 reg [23:0] color;
 begin
 frame=DYNAMIC ? absolute_byte/77824 : 0;n=DYNAMIC ? absolute_byte%77824 : absolute_byte;
 if(n<4) case(n)0:indexed_byte="M";1:indexed_byte="V";2:indexed_byte="I";3:indexed_byte=DYNAMIC ? "4" : "3";endcase
 else if(n<772) begin color=palette_color((n-4)/3+frame);indexed_byte=color>>((2-(n-4)%3)*8);end
 else if(n==772 && DYNAMIC) indexed_byte=FPS;
 else if(n<1024) indexed_byte=0;
 else indexed_byte=(n-1024)%8;
 end endfunction
 integer expected_addr, index, entry, next_entry, tick_div=0;
    integer audio_ticks=0, first_present_tick=0;
    reg model_busy=0;
    exfat_raw_video_reader dut(
        .clk(clk),.rst(rst),.start(start),.restart(1'b0),.enable(1'b1),.rgb332_mode(COMPACT != 0),.indexed_mode(INDEXED != 0),.dynamic_mode(DYNAMIC != 0),.audio_finished(1'b0),.pacing_wait(pacing_wait),
        .first_lba(32'd1000),.first_cluster(32'd2),.file_bytes(DYNAMIC ? 32'd155648 : COMPACT ? (INDEXED ? 32'd154624 : 32'd153600) : 32'd307200),
        .no_fat_chain(contiguous),.volume_lba(32'd0),.fat_offset(32'd100),
        .heap_offset(32'd1000),.spc_shift(8'd2),.allow_frame(1'b1),
        .pcm_frame_tick(pcm_tick),.write_req_ack(ack),.scale_ready(scale_ready),
        .scale_done(scale_done),.frame_committed(committed),.frame_present(frame_present),
        .frame_start(frame_start),.scale_go(scale_go),.write_req(write_req),
        .pixel_valid(pixel_valid),.pixel_data(pixel_data),
        .sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),
        .sd_data(data),.sd_data_valid(data_valid),.sd_read_end(read_end),
        .active(active),.video_error(error)
    );
    bmp_fit_scaler scaler(
        .clk(clk),.rst(rst),.start(frame_start),.go(scale_go),
        .src_width(16'd320),.src_height(16'd240),.viewport_mode(2'd0),.aspect_mode(2'd0),
        .pixel_valid(pixel_valid),.pixel_data(pixel_data),.write_full(1'b0),
        .ready_for_pixels(scale_ready),.write_en(wr_en),.write_data(wr_data),
        .done(scale_done),.overflow(overflow)
    );
    always @(negedge clk) begin
        if (rst) begin ack=0; committed=0; tick_div=0; pcm_tick=0; end
        else begin
            ack=write_req;
            // Commit can arrive before the scaler's done indication.
            committed=wr_en && writes%307200==307199;
            pcm_tick=0;
            if (presented>0 && !pacing_wait) begin
                if (tick_div==199) begin tick_div=0; pcm_tick=1; audio_ticks=audio_ticks+1; end
                else tick_div=tick_div+1;
            end
            if (pixel_valid) begin
                if (pixel_data !== (INDEXED ? palette_color(pixels%8+(DYNAMIC ? pixels/76800 : 0)) : (pixels<(COMPACT ? 4 : 2) ? 24'h000000 : 24'hff0000)))
                    $fatal(1,"bad decoded pixel %0d = %h",pixels,pixel_data);
                pixels=pixels+1;
            end
            if (wr_en) writes=writes+1;
            if (overflow || error) $fatal(1,"scaler overflow / reader error");
            if (frame_present) begin
                if (presented==1 && audio_ticks-first_present_tick<TICKS)
                    $fatal(1,"second frame presented before audio deadline");
                if (presented==0) first_present_tick=audio_ticks;
                presented=presented+1;
            end
        end
    end
    // Physical sector model. A fragmented file jumps every four sectors.
    always @(negedge clk) if (!rst && sd_read && !model_busy) begin
        model_busy=1;
        if (sd_addr>=1000) begin
            expected_addr=1000+(contiguous ? sectors : (sectors/4)*8+sectors%4);
            if (sd_addr!==expected_addr) $fatal(1,"sector %0d LBA %0d expected %0d",sectors,sd_addr,expected_addr);
            for (index=0; index<512; index=index+1) begin
                repeat (COMPACT ? 23 : 11) @(negedge clk);
                data_valid=1;
                if(INDEXED) data=indexed_byte(sectors*512+index);
                else if (sectors==0 && index<4) begin
                    case(index) 0:data="M";1:data="V";2:data="I";3:data=COMPACT ? "2" : "1";endcase
                end else data=COMPACT ? 8'he0 : (index%2 ? 8'hf8 : 8'h00);
                @(negedge clk); data_valid=0;
            end
            sectors=sectors+1;
        end else begin
            fat_reads=fat_reads+1;
            for (index=0; index<512; index=index+1) begin
                entry=(sd_addr-100)*128+index/4;
                next_entry=entry+2;
                repeat (COMPACT ? 23 : 11) @(negedge clk);
                data_valid=1; data=(next_entry>>((index%4)*8))&255;
                @(negedge clk); data_valid=0;
            end
        end
        @(negedge clk); read_end=1;
        @(negedge clk); read_end=0;
        wait(!sd_read);
        @(negedge clk); model_busy=0;
    end
    initial begin
        if ($test$plusargs("fragmented")) contiguous=0;
        repeat(5) @(negedge clk); rst=0;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        wait(presented==2); repeat(10) @(negedge clk);
        if (COMPACT && audio_ticks-first_present_tick>TICKS+1) $fatal(1,"audio advanced past a late frame: %0d",audio_ticks);
        if (pixels!=153600 || writes!=614400 || sectors!=SECTORS || active)
            $fatal(1,"wrong totals pixels=%0d writes=%0d sectors=%0d active=%b",pixels,writes,sectors,active);
        if (!contiguous && fat_reads!=(COMPACT ? (INDEXED ? 75 : 74) : 149)) $fatal(1,"missing FAT traversals %0d",fat_reads);
        $display("PASS video + real scaler: compact=%b contiguous=%b, two complete frames, FAT=%0d, audio pacing",COMPACT,contiguous,fat_reads);
        $finish;
    end
    initial begin #60000000; $fatal(1,"timeout sectors=%0d pixels=%0d writes=%0d frames=%0d state=%0d",sectors,pixels,writes,presented,dut.state); end
endmodule
