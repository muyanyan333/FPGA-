`timescale 1ns/1ps
// Render the property panel to a PGM so the layout/font can be checked.
module tb_property_panel;
    parameter SIZE_EDIT = 0;
    parameter ASPECT_EDIT = 0;
    reg clk = 0, rst = 1, de = 1, enable = 1;
    always #5 clk = ~clk;

    reg [10:0] x = 0;
    reg [9:0]  y = 0;
    wire panel_on, text_on;

    property_panel dut(
        .clk(clk), .rst(rst), .de(de), .x(x), .y(y), .enable(enable),
        .image_size_edit(SIZE_EDIT != 0), .image_size_mode(2'd1),
        .image_aspect_edit(ASPECT_EDIT != 0),.image_aspect_mode(2'd2),
        .track_num(5'd10), .track_count(5'd3),
        .track_map(16'h03ff), .selected_index(4'd0), .menu_item(4'd5), .menu_edit(1'b0),
        .music_menu(1'b0), .volume(4'd7), .slideshow_auto(1'b0),
        .image_num(5'd5), .image_count(5'd12),
        .playing(1'b1), .effect(2'd1),
        .lyric_enabled(1'b1), .title_enabled(1'b1),
        .brightness(4'd9), .contrast(4'd5),
        .panel_on(panel_on), .text_on(text_on), .selection_on()
    );

    integer fx, fy;
    integer file;
    reg [7:0] pixel;

    initial begin
        repeat(4) @(posedge clk);
        rst = 0;
        if (ASPECT_EDIT) file = $fopen("lab_ex5_i2s-work/sim/image_aspect_panel_preview.pgm", "wb");
        else if (SIZE_EDIT) file = $fopen("lab_ex5_i2s-work/sim/image_size_panel_preview.pgm", "wb");
        else file = $fopen("lab_ex5_i2s-work/sim/property_panel_preview.pgm", "wb");
        $fwrite(file, "P5\n640 480\n255\n");
        for (fy = 0; fy < 480; fy = fy + 1) begin
            for (fx = 0; fx < 640; fx = fx + 1) begin
                x = fx[10:0];
                y = fy[9:0];
                repeat (2) @(posedge clk);
                if (text_on) pixel = 8'd255;
                else if (panel_on) pixel = 8'd70;
                else pixel = 8'd0;
                $fwrite(file, "%c", pixel);
            end
        end
        $fclose(file);
        $display("panel preview written");
        $finish;
    end
endmodule
