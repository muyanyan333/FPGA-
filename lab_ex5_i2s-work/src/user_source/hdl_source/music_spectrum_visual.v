// Full-screen music display adapted from the reference project's 800x480
// composition to the local 640x480 HDMI timing. No vendor display IP.
module music_spectrum_visual(
    input wire clk,
    input wire rst,
    input wire frame_start,
    input wire de,
    input wire [10:0] x,
    input wire [9:0] y,
    input wire [23:0] background,
    input wire [5:0] level,
    input wire waveform_on,
    output wire [6:0] bar_addr,
    output wire [23:0] pixel
);
    reg [2:0] frame_div;
    reg [6:0] color_phase;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_div <= 0;
            color_phase <= 0;
        end else if (frame_start) begin
            if (frame_div == 3'd4) begin
                frame_div <= 0;
                color_phase <= color_phase + 1'b1;
            end else frame_div <= frame_div + 1'b1;
        end
    end

    // 80 six-pixel bars with two-pixel gaps span the complete width.
    wire [6:0] column = x[9:3];
    assign bar_addr = column;
    wire bar_on = de && x < 11'd640 && x[2:0] < 3'd6 &&
                  y < 10'd480 &&
                  y >= (10'd480 - {level,3'b000});
    wire draw_on = bar_on || waveform_on;

    // HSL(S=0.85,L=0.60), 128 hue steps, approximated in RGB565 by
    // six linear segments to keep the palette in local logic.
    function [23:0] palette;
        input [6:0] hue;
        reg [4:0] red5, blue5;
        reg [5:0] green6;
        begin
            if (hue < 7'd22) begin
                red5=5'd30; green6=6'd16+{hue[4:0],1'b0}; blue5=5'd8;
            end else if (hue < 7'd43) begin
                red5=5'd30-(hue-7'd22); green6=6'd60; blue5=5'd8;
            end else if (hue < 7'd64) begin
                red5=5'd8; green6=6'd60; blue5=5'd8+(hue-7'd43);
            end else if (hue < 7'd85) begin
                red5=5'd8; green6=6'd60-((hue-7'd64)<<1); blue5=5'd30;
            end else if (hue < 7'd106) begin
                red5=5'd8+(hue-7'd85); green6=6'd16; blue5=5'd30;
            end else begin
                red5=5'd30; green6=6'd16; blue5=5'd30-(hue-7'd106);
            end
            palette={red5,3'b000,green6,2'b00,blue5,3'b000};
        end
    endfunction
    wire [6:0] bar_hue = column + color_phase;
    wire [6:0] wave_hue = color_phase + 7'd104;
    wire [23:0] bar_color = palette(bar_hue);
    wire [23:0] wave_color = palette(wave_hue);
    wire [23:0] fore = waveform_on ? wave_color : bar_color;

    function [7:0] hard_light;
        input [7:0] back;
        input [7:0] front;
        reg [15:0] product;
        begin
            if (front < 8'd128) begin
                product = back * front;
                hard_light = product[14:7];
            end else begin
                product = (8'd255-back) * (8'd255-front);
                hard_light = 8'd255 - product[14:7];
            end
        end
    endfunction
    assign pixel = !draw_on ? background :
                   {hard_light(background[23:16], fore[23:16]),
                    hard_light(background[15:8], fore[15:8]),
                    hard_light(background[7:0], fore[7:0])};
endmodule
