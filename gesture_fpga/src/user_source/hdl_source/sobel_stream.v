`timescale 1ns/1ps
// Streaming 3x3 Sobel edge detector for the existing 640x480 RGB888 video path.
// Output is delayed by two pixel clocks. The edge at (x-1,y-1) is displayed at
// (x,y); the first two rows/columns and inactive video are black.
module sobel_stream #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter [10:0] THRESHOLD = 11'd200
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        in_vs,
    input  wire        in_de,
    input  wire [23:0] in_rgb,
    output reg         out_vs,
    output reg         out_de,
    output reg  [23:0] out_rgb,
    output reg  [11:0] out_magnitude
);
    // This weighting needs no multiplier and maps RGB888 to an 8-bit intensity.
    wire [7:0] gray = {2'b0,in_rgb[23:18]} +
                      {1'b0,in_rgb[15:9]} +
                      {2'b0,in_rgb[7:2]};

    // Three banks avoid relying on FPGA-specific read-during-write behavior.
    reg [7:0] line0 [0:WIDTH-1];
    reg [7:0] line1 [0:WIDTH-1];
    reg [7:0] line2 [0:WIDTH-1];
    reg [10:0] x;
    reg [10:0] y;
    reg [1:0] bank;
    reg prev_de, prev_vs;
    wire frame_start = in_vs != prev_vs;
    wire line_start = in_de && !prev_de;
    wire [10:0] cur_x = line_start ? 11'd0 : x;
    wire [10:0] cur_y = frame_start ? 11'd0 :
                          line_start && prev_line_seen ? y + 11'd1 : y;
    wire [1:0] cur_bank = frame_start ? 2'd0 :
                          line_start && prev_line_seen ?
                            (bank == 2'd2 ? 2'd0 : bank + 2'd1) : bank;
    reg prev_line_seen;

    reg [7:0] top_read, mid_read, gray_d;
    reg [10:0] x_d, y_d;
    reg de_d, vs_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x <= 0; y <= 0; bank <= 0;
            prev_de <= 0; prev_vs <= 0; prev_line_seen <= 0;
            top_read <= 0; mid_read <= 0; gray_d <= 0;
            x_d <= 0; y_d <= 0; de_d <= 0; vs_d <= 0;
        end else begin
            prev_de <= in_de;
            prev_vs <= in_vs;
            vs_d <= in_vs;
            de_d <= in_de;
            if (frame_start) begin
                x <= 0; y <= 0; bank <= 0; prev_line_seen <= 0;
            end
            if (in_de) begin
                x <= cur_x + 11'd1;
                y <= cur_y;
                bank <= cur_bank;
                if (line_start) prev_line_seen <= 1'b1;
                if (cur_x < WIDTH) begin
                    case (cur_bank)
                        2'd0: begin
                            top_read <= line1[cur_x];
                            mid_read <= line2[cur_x];
                            line0[cur_x] <= gray;
                        end
                        2'd1: begin
                            top_read <= line2[cur_x];
                            mid_read <= line0[cur_x];
                            line1[cur_x] <= gray;
                        end
                        default: begin
                            top_read <= line0[cur_x];
                            mid_read <= line1[cur_x];
                            line2[cur_x] <= gray;
                        end
                    endcase
                end else begin
                    top_read <= 0; mid_read <= 0;
                end
                gray_d <= gray;
                x_d <= cur_x;
                y_d <= cur_y;
            end
        end
    end

    reg [7:0] tl, tm, tr, ml, mm, mr, bl, bm, br;
    reg win_de, win_vs, win_valid;
    wire signed [11:0] gx = $signed({4'b0,tr}) + $signed({3'b0,mr,1'b0}) +
                            $signed({4'b0,br}) - $signed({4'b0,tl}) -
                            $signed({3'b0,ml,1'b0}) - $signed({4'b0,bl});
    wire signed [11:0] gy = $signed({4'b0,bl}) + $signed({3'b0,bm,1'b0}) +
                            $signed({4'b0,br}) - $signed({4'b0,tl}) -
                            $signed({3'b0,tm,1'b0}) - $signed({4'b0,tr});
    wire [10:0] abs_gx = gx < 0 ? -gx : gx;
    wire [10:0] abs_gy = gy < 0 ? -gy : gy;
    wire [11:0] magnitude = {1'b0,abs_gx} + {1'b0,abs_gy};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tl<=0; tm<=0; tr<=0; ml<=0; mm<=0; mr<=0;
            bl<=0; bm<=0; br<=0;
            win_de<=0; win_vs<=0; win_valid<=0;
            out_vs<=0; out_de<=0; out_rgb<=0; out_magnitude<=0;
        end else begin
            win_de <= de_d;
            win_vs <= vs_d;
            win_valid <= de_d && x_d >= 2 && x_d < WIDTH &&
                         y_d >= 2 && y_d < HEIGHT;
            if (de_d) begin
                if (x_d == 0) begin
                    tl<=0; tm<=0; ml<=0; mm<=0; bl<=0; bm<=0;
                end else begin
                    tl<=tm; tm<=tr; ml<=mm; mm<=mr; bl<=bm; bm<=br;
                end
                tr<=top_read; mr<=mid_read; br<=gray_d;
            end
            out_vs <= win_vs;
            out_de <= win_de;
            out_magnitude <= win_valid ? magnitude : 12'd0;
            out_rgb <= (win_valid && magnitude >= {1'b0,THRESHOLD}) ?
                       24'hffffff : 24'h000000;
        end
    end
endmodule
