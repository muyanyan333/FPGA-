`timescale 1ns/1ps
module tb_menu_navigation;
reg clk=0, rst_n=0, k2=0, k3=0, ks=0, kl=0;
always #5 clk=~clk;
wire edit_active, music_edit, menu_edit, playing, prev_song, next_song;
wire volume_up, volume_down;
wire [3:0] item, cursor, selected_index;
wire select_toggle, auto_pulse, manual_pulse;
wire [3:0] draft, volume_value;
wire volume_set, size_set, aspect_set;
wire [1:0] size_value, aspect_value;
reg saw_volume_set=0, saw_auto=0, saw_size_set=0, saw_aspect_set=0;
always @(posedge clk) begin
    if (volume_set) saw_volume_set<=1;
    if (auto_pulse) saw_auto<=1;
    if (size_set) saw_size_set<=1;
    if (aspect_set) saw_aspect_set<=1;
end
wire [3:0] bright, contrast;
wire [1:0] effect;
player_key_control dut(
    .clk(clk), .rst_n(rst_n), .key2_pulse(k2), .key3_pulse(k3),
    .key4_short(ks), .key4_long(kl), .key2_held(1'b0),
    .key3_held(1'b0), .key4_held(1'b0),
    .remote_brightness(1'b0), .remote_contrast(1'b0),
    .remote_effect(1'b0), .remote_playing(1'b0),
    .remote_playing_value(1'b0), .remote_brightness_value(4'd0),
    .remote_contrast_value(4'd0), .remote_effect_value(2'd0),
    .track_map(16'h00ff), .current_track(4'd0), .slideshow_auto(1'b0),
    .current_volume(4'd5), .current_size(2'd0), .current_aspect(2'd0),
    .edit_active(edit_active), .music_edit_active(music_edit),
    .menu_edit_active(menu_edit), .menu_item(item),
    .music_cursor(cursor), .music_select_toggle(select_toggle),
    .draft_value(draft), .volume_set(volume_set), .volume_value(volume_value),
    .size_set(size_set), .size_value(size_value),
    .aspect_set(aspect_set), .aspect_value(aspect_value),
    .music_select_index(selected_index), .auto_pulse(auto_pulse), .manual_pulse(manual_pulse),
    .brightness_level(bright), .contrast_level(contrast),
    .transition_effect(effect), .music_playing(playing),
    .music_prev_toggle(prev_song), .music_next_toggle(next_song),
    .volume_up(volume_up), .volume_down(volume_down),
    .next_background_pulse(), .image_size_step(), .image_aspect_step()
);
task press;
    input integer key;
    begin
        @(negedge clk);
        case(key) 2:k2=1; 3:k3=1; 4:ks=1; 5:kl=1; endcase
        @(negedge clk); k2=0; k3=0; ks=0; kl=0;
        @(negedge clk);
    end
endtask
integer i;
initial begin
    repeat(3) @(negedge clk); rst_n=1;
    press(5);
    if (!edit_active || item!=0) $fatal(1,"menu entry");
    @(negedge clk); k2=1; k3=1;
    @(negedge clk); k2=0; k3=0;
    @(negedge clk);
    if (item!=0) $fatal(1,"key chord changed menu selection");
    press(4); press(2);
    if (bright!=9 || draft!=8) $fatal(1,"brightness changed before save");
    press(5);
    if (edit_active || bright!=9) $fatal(1,"long exit did not discard draft");
    press(5); press(4); press(2); press(4);
    if (bright!=8) $fatal(1,"brightness save failed");
    press(3); press(3); press(4); press(3);
    if (saw_size_set || draft!=1) $fatal(1,"size applied before save");
    press(4);
    if (!saw_size_set || size_value!=1) $fatal(1,"size save failed");
    press(3); press(4); press(3);
    if (saw_aspect_set || draft!=1) $fatal(1,"aspect applied before save");
    press(4);
    if (!saw_aspect_set || aspect_value!=1) $fatal(1,"aspect save failed");
    press(3);
    if (item!=4) $fatal(1,"song menu selection");
    press(4);
    if (!music_edit || cursor!=0 || select_toggle) $fatal(1,"song menu entry");
    press(3);
    if (cursor!=1 || select_toggle || next_song) $fatal(1,"selection changed playback before confirmation");
    press(4);
    if (music_edit || !select_toggle || selected_index!=1) $fatal(1,"song confirmation");
    press(3);
    if (item!=5 || menu_edit) $fatal(1,"volume menu selection");
    press(4);
    press(3);
    if (draft!=6 || saw_volume_set) $fatal(1,"volume applied before save");
    press(4);
    if (!saw_volume_set || volume_value!=6) $fatal(1,"volume save failed");
    press(3);
    if (item!=6) $fatal(1,"play item");
    press(4); press(3);
    if (!playing || draft!=0) $fatal(1,"play applied before save");
    press(4);
    if (playing) $fatal(1,"play save failed");
    press(3);
    if (item!=7) $fatal(1,"effect item");
    press(4); press(3);
    if (effect!=0 || draft!=1) $fatal(1,"effect applied before save");
    press(4);
    if (effect!=1) $fatal(1,"effect save failed");
    press(3);
    if (item!=8) $fatal(1,"slideshow item");
    press(4); press(3);
    if (saw_auto || draft!=1) $fatal(1,"slideshow applied before save");
    press(4);
    if (!saw_auto) $fatal(1,"slideshow save pulse");
    press(3);
    if (item!=0) $fatal(1,"menu wrap");
    press(5);
    if (edit_active) $fatal(1,"menu exit");
    $display("MENU NAVIGATION PASS"); $finish;
end
endmodule
