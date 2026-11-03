`timescale 1ns/1ps
module tb_player_keys;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg k2=0,k3=0,ks=0,kl=0,h2=0,h3=0,h4=0;
    reg remote=0;
    reg remote_play=0;
    wire edit_on,music_edit,playing,prev_song,next_song,next_bg,size_step,aspect_step;
    wire [2:0] item;
    wire [1:0] effect;
    wire [3:0] bright,contrast;
    integer backgrounds=0;
    always @(posedge clk) if(next_bg) backgrounds=backgrounds+1;
    player_key_control dut(
        .clk(clk),.rst_n(rst_n),.key2_pulse(k2),.key3_pulse(k3),
        .key4_short(ks),.key4_long(kl),.key2_held(h2),.key3_held(h3),.key4_held(h4),
        .remote_brightness(remote),.remote_brightness_value(4'd3),
        .remote_contrast(1'b0),.remote_contrast_value(4'd0),
        .remote_effect(1'b0),.remote_effect_value(2'd0),
        .remote_playing(remote_play),.remote_playing_value(1'b1),
        .edit_active(edit_on),.music_edit_active(music_edit),.menu_item(item),
        .brightness_level(bright),.contrast_level(contrast),.transition_effect(effect),
        .music_playing(playing),.music_prev_toggle(prev_song),.music_next_toggle(next_song),
        .next_background_pulse(next_bg),.image_size_step(size_step),.image_aspect_step(aspect_step)
    );
    // Exercise the real input filter separately from UI event routing.
    reg raw_key=1;
    wire press_event,held;
    integer presses=0;
    wire legacy_event;
    integer legacy_presses=0;
    player_button_debounce #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(3)) filter(
        .I_clk(clk),.I_rst_n(rst_n),.I_key_in(raw_key),
        .O_key_trig_out(press_event),.O_key_pressed(held)
    );
    always @(posedge clk) if(press_event) presses=presses+1;
    key_press_debounce #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(3)) legacy_filter(
        .clk(clk),.rst(!rst_n),.button_in(raw_key),.press_pulse(legacy_event)
    );
    always @(posedge clk) if(legacy_event) legacy_presses=legacy_presses+1;

    task event_key;
        input integer n;
        begin
            @(negedge clk);
            case(n) 2:k2=1; 3:k3=1; 4:ks=1; 5:kl=1; endcase
            @(negedge clk); k2=0;k3=0;ks=0;kl=0;
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        event_key(2); event_key(3);
        if(effect!=1 || backgrounds!=1) $fatal(1,"home key routing");
        @(negedge clk); k2=1;k3=1;
        @(negedge clk); k2=0;k3=0;
        @(negedge clk);
        if(effect!=1 || backgrounds!=1) $fatal(1,"chord was not ignored");
        // UART cannot swallow a simultaneous long press.
        remote=1;kl=1;
        @(negedge clk); remote=0;kl=0;
        @(negedge clk);
        if(!edit_on || item!=0 || bright!=3) $fatal(1,"remote/local arbitration");
        event_key(3);
        if(bright!=4 || backgrounds!=1) $fatal(1,"menu key leaked to background");
        // A held key does not repeat an action; long press exits the menu.
        h4=1; repeat(25) @(negedge clk);
        if(!edit_on) $fatal(1,"menu closed while holding KEY4");
        event_key(5); h4=0;
        if(edit_on || !playing) $fatal(1,"long exit or unintended pause");
        event_key(5); event_key(2); event_key(2);
        // H3 is a parameter page, not the music editor.
        if(item!=2 || music_edit) $fatal(1,"H3 image size selection");
        @(negedge clk); k3=1;
        @(negedge clk); k3=0;
        if(!size_step || next_song || backgrounds!=1) $fatal(1,"H3 size routing");
        event_key(4);
        if(edit_on || music_edit) $fatal(1,"H3 save must return home");
        event_key(5); event_key(2); event_key(2); event_key(2);
        if(item!=3 || music_edit) $fatal(1,"H4 aspect selection");
        @(negedge clk);k3=1;
        @(negedge clk);k3=0;
        if(!aspect_step || size_step || next_song || backgrounds!=1)
            $fatal(1,"H4 aspect routing");
        event_key(4);
        if(edit_on || music_edit) $fatal(1,"H4 save must return home");
        event_key(5);event_key(2);event_key(2);event_key(2);event_key(2);event_key(4);
        if(!music_edit || !edit_on || item!=4) $fatal(1,"H5 confirmation");
        event_key(3);
        if(!next_song || prev_song || effect!=1 || backgrounds!=1) $fatal(1,"H3 key leakage");
        repeat(25) @(negedge clk);
        if(!music_edit) $fatal(1,"H3 must not time out");
        event_key(2); event_key(4);
        if(!prev_song || playing) $fatal(1,"H3 previous/pause");
        event_key(5);
        if(edit_on || playing) $fatal(1,"exit H3 changed playback");
        event_key(5);
        repeat(25) @(negedge clk);
        if(!edit_on) $fatal(1,"idle menu closed without a key");
        event_key(4);
        if(edit_on) $fatal(1,"KEY4 did not save and exit");
        event_key(5);
        repeat(5) event_key(2);
        if(item!=0 || music_edit) $fatal(1,"five-item menu failed to wrap at H5");
        event_key(5);
        remote_play=1;
        @(negedge clk); remote_play=0;
        @(negedge clk);
        if(!playing) $fatal(1,"remote playback control failed");
        // Bounce shorter than filter interval must not generate a press.
        raw_key=0; @(negedge clk); raw_key=1;
        repeat(8) @(negedge clk);
        if(presses!=0) $fatal(1,"bounce accepted");
        raw_key=0; repeat(20) @(negedge clk);
        if(presses!=1 || legacy_presses!=1 || !held) $fatal(1,"hold repeats or missing press");
        raw_key=1; repeat(8) @(negedge clk);
        raw_key=0; repeat(8) @(negedge clk);
        if(presses!=2 || legacy_presses!=2) $fatal(1,"release failed to rearm");
        $display("PLAYER KEYS PASS (routing, chords, UART, manual exit, debounce)");
        $finish;
    end
    initial begin #20000; $fatal(1,"key test timeout"); end
endmodule
