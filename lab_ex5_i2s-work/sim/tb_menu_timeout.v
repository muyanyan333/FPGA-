`timescale 1ns/1ps
module tb_menu_timeout;
    reg clk=0, rst_n=0, enter_menu=0, adjust=0, save=0;
    always #5 clk=~clk;
    wire edit_active;
    wire [3:0] brightness;
    // 1 kHz gives one cycle per ms; the menu must stay open indefinitely.
    player_key_control dut (
        .clk(clk), .rst_n(rst_n), .key2_pulse(1'b0), .key3_pulse(adjust),
        .key4_short(save), .key4_long(enter_menu),
        .key2_held(1'b0), .key3_held(1'b0), .key4_held(1'b0),
        .remote_brightness(1'b0), .remote_brightness_value(4'd0),
        .remote_contrast(1'b0), .remote_contrast_value(4'd0),
        .remote_effect(1'b0), .remote_effect_value(2'd0),
        .remote_playing(1'b0), .remote_playing_value(1'b1),
        .edit_active(edit_active), .brightness_level(brightness)
    );
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1; enter_menu=1;
        @(negedge clk); enter_menu=0;
        repeat(3200) @(negedge clk);
        if(!edit_active) $fatal(1,"menu exited without a key");
        adjust=1;
        @(negedge clk); adjust=0;
        repeat(3200) @(negedge clk);
        if(!edit_active || brightness!=0) $fatal(1,"menu exited after adjustment");
        save=1;
        @(negedge clk); save=0;
        @(negedge clk);
        if(edit_active || brightness!=0) $fatal(1,"KEY4 save/exit failed");
        $display("MENU MANUAL EXIT PASS (no idle exit, KEY4 save, retained setting)");
        $finish;
    end
    initial begin #200000; $fatal(1,"test timeout"); end
endmodule
