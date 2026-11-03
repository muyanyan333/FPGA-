`timescale 1ns/1ps
module tb_song_menu;
reg clk=0, rst=1;
always #5 clk=~clk;
reg [10:0] x=0;
reg [9:0] y=0;
reg [3:0] selected=0;
reg [15:0] track_map=16'h00ff;
reg music_menu=1;
reg menu_edit=1;
reg [3:0] menu_item=4'd4;
wire panel_on, text_on, selection_on;
property_panel dut(
    .clk(clk), .rst(rst), .de(1'b1), .x(x), .y(y), .enable(1'b1),
    .image_size_edit(1'b0), .image_size_mode(2'd0),
    .image_aspect_edit(1'b0), .image_aspect_mode(2'd0),
    .track_num(5'd1), .track_count(5'd8), .track_map(track_map),
    .selected_index(selected), .menu_item(menu_item), .menu_edit(menu_edit),
    .music_menu(music_menu), .volume(4'd5), .slideshow_auto(1'b0),
    .image_num(5'd1), .image_count(5'd12), .playing(1'b1),
    .lyric_enabled(1'b1), .title_enabled(1'b1), .effect(2'd0),
    .brightness(4'd9), .contrast(4'd5),
    .panel_on(panel_on), .text_on(text_on), .selection_on(selection_on)
);
initial begin
    repeat(3) @(negedge clk); rst=0;
    x=11'd344; y=10'd88;
    #1;
    if (dut.ch < 8'hB0) $fatal(1,"first song Chinese name missing");
    x=11'd276;
    @(negedge clk);
    if (!selection_on) $fatal(1,"selection frame missing");
    selected=4'd1;
    @(negedge clk);
    if (selection_on) $fatal(1,"old song remains highlighted");
    y=10'd104;
    @(negedge clk);
    if (!selection_on) $fatal(1,"selection frame did not move");
    x=11'd344; #1;
    if (dut.ch < 8'hB0 || dut.ch == dut.song_name_char(4'd0,4'd0))
        $fatal(1,"second song name missing");
    track_map=0; selected=0; x=11'd276; y=10'd88;
    @(negedge clk);
    if (!selection_on) $fatal(1,"empty catalogue hid selection frame");
    x=11'd280; #1;
    if (dut.ch != 8'h4E) $fatal(1,"empty catalogue message missing");
    music_menu=0; menu_edit=0; menu_item=4'd5; x=11'd500; y=10'd168;
    @(negedge clk);
    if (!selection_on) $fatal(1,"menu volume item frame missing");
    x=11'd504; #1;
    if (dut.ch != 8'h56) $fatal(1,"volume missing from full menu list");
    menu_item=4'd0; y=10'd88;
    @(negedge clk);
    if (!selection_on) $fatal(1,"menu highlight did not follow selected item");
    x=11'd504; #1;
    if (dut.ch != 8'h42) $fatal(1,"brightness missing from full menu list");
    menu_edit=1; menu_item=4'd5; x=11'd500; y=10'd104;
    @(negedge clk);
    if (!selection_on) $fatal(1,"volume edit page highlight missing");
    x=11'd504; y=10'd72; #1;
    if (dut.ch != 8'h56) $fatal(1,"volume edit page title missing");
    $display("SONG NAME AND SELECTION FRAME PASS"); $finish;
end
endmodule
