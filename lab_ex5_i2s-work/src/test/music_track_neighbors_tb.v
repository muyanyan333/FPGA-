`timescale 1ns/1ps
module music_track_neighbors_tb;
    reg [15:0] valid;
    reg [3:0] current;
    wire [3:0] next_index, prev_index;
    integer mask, cur, j, expected_next, expected_prev;
    reg found_next, found_prev;
    music_track_neighbors dut(.*);
    initial begin
        for (mask=0; mask<65536; mask=mask+1)
            for (cur=0; cur<16; cur=cur+1) begin
                valid=mask; current=cur;
                expected_next=cur; expected_prev=cur;
                found_next=0; found_prev=0;
                for (j=1; j<16; j=j+1) begin
                    if (!found_next && valid[(cur+j)&15]) begin
                        expected_next=(cur+j)&15; found_next=1;
                    end
                    if (!found_prev && valid[(cur-j)&15]) begin
                        expected_prev=(cur-j)&15; found_prev=1;
                    end
                end
                #1;
                if (next_index!==expected_next[3:0] || prev_index!==expected_prev[3:0])
                    $fatal(1,"mask=%h cur=%0d next=%0d/%0d prev=%0d/%0d",
                        valid,cur,next_index,expected_next,prev_index,expected_prev);
            end
        $display("PASS: all 1048576 track map/current combinations");
        $finish;
    end
endmodule
