`timescale 1ns/1ps
module tb_exfat_pcm_wav_reader #(parameter USE_CLUSTER_START=0);
    reg clk=0, rst=1, start=0;
    always #5 clk=~clk;
    wire req, out_valid, wav_valid, wav_error;
    wire [31:0] addr, out_data;
    reg [7:0] sd_data=0;
    reg sd_valid=0, sd_end=0;
    reg busy=0;
    reg [1:0] cooldown=0;
    integer pos=0, frames=0, cycles=0;
    reg [31:0] active_addr;

    exfat_pcm_wav_reader #(.USE_CLUSTER_START(USE_CLUSTER_START)) dut(
        .clk(clk),.rst(rst),.start(start),.restart(1'b0),
        .first_lba(32'd100),.first_cluster(32'd7),.file_bytes(32'd556),
        .no_fat_chain(1'b1),.volume_lba(32'd0),.fat_offset(32'd24),
        .heap_offset(32'd60),.spc_shift(8'd3),
        .fifo_count(13'd0),.fifo_full(1'b0),
        .fifo_wr_en(out_valid),.fifo_wr_data(out_data),
        .wav_valid(wav_valid),.wav_error(wav_error),
        .sd_sec_read(req),.sd_sec_read_addr(addr),
        .sd_data(sd_data),.sd_data_valid(sd_valid),.sd_read_end(sd_end)
    );

    function [7:0] sector_byte;
        input [31:0] a;
        input integer p;
        integer f, q;
        begin
            sector_byte=0;
            if (a==100) begin
                case(p)
                    0:sector_byte="R"; 1:sector_byte="I";
                    2:sector_byte="F"; 3:sector_byte="F";
                    8:sector_byte="W"; 9:sector_byte="A";
                    10:sector_byte="V"; 11:sector_byte="E";
                    12:sector_byte="f"; 13:sector_byte="m";
                    14:sector_byte="t"; 15:sector_byte=" ";
                    16:sector_byte=16;
                    20:sector_byte=1; 22:sector_byte=2;
                    24:sector_byte=8'h80; 25:sector_byte=8'hbb;
                    28:sector_byte=8'h00; 29:sector_byte=8'hee;
                    30:sector_byte=8'h02;
                    32:sector_byte=4; 34:sector_byte=16;
                    36:sector_byte="d"; 37:sector_byte="a";
                    38:sector_byte="t"; 39:sector_byte="a";
                    41:sector_byte=2;
                    default: ;
                endcase
            end
            if (a==100 && p>=44) begin
                f=(p-44)/4; q=(p-44)%4;
                case(q)
                    0:sector_byte=f;
                    1:sector_byte=0;
                    2:sector_byte=f+1;
                    3:sector_byte=0;
                endcase
            end else if (a==101 && p<44) begin
                f=(468+p)/4; q=(468+p)%4;
                case(q)
                    0:sector_byte=f;
                    1:sector_byte=0;
                    2:sector_byte=f+1;
                    3:sector_byte=0;
                endcase
            end
        end
    endfunction

    always @(posedge clk) begin
        sd_valid<=0; sd_end<=0;
        if (cooldown != 0) cooldown<=cooldown-1'b1;
        if (!busy && cooldown==0 && req) begin
            busy<=1; pos<=0; active_addr<=addr;
        end else if (busy) begin
            if (pos<512) begin
                sd_valid<=1; sd_data<=sector_byte(active_addr,pos);
                pos<=pos+1;
            end else begin sd_end<=1; busy<=0; cooldown<=2'd2; end
        end
        if (out_valid) begin
            if (out_data[31:16] !== frames[15:0] ||
                out_data[15:0] !== ((frames+1) & 16'hffff)) begin
                $display("FAIL frame=%0d data=%h",frames,out_data); $finish;
            end
            frames<=frames+1;
        end
    end

    initial begin
        repeat(4) @(posedge clk); rst<=0;
        repeat(2) @(posedge clk); start<=1;
        @(posedge clk); start<=0;
        while (frames<128 && cycles<5000) begin @(posedge clk); cycles=cycles+1; end
        if (frames==128 && wav_valid && !wav_error) $display("PASS WAV 128 stereo frames");
        else $display("FAIL frames=%0d valid=%b error=%b",frames,wav_valid,wav_error);
        $finish;
    end
endmodule
