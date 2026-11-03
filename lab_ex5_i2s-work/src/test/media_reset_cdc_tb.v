`timescale 1ns/1ps
// Exercise the real top-level audio reset and HDMI lane reset at unrelated
// phases, including a sub-cycle reset and EOF-style media mode changes.
module media_reset_cdc_tb;
reg clk=0, pixel_clk=0, serial_clk=0, audio_clk=0;
reg rst_n=1, pll_lock=1, request=0, done=0;
reg [1:0] mode=0;
always #10 clk=~clk;
always #20 pixel_clk=~pixel_clk;
always #4 serial_clk=~serial_clk;
always #40.667 audio_clk=~audio_clk;
top #(.CAMERA_AVAILABLE(0)) dut(
    .clk(clk), .rst_n(rst_n), .key2(1'b1), .key3(1'b1), .key4(1'b1));
wire lane_rst = dut.u_hdmi2phy_wrapper.u0_lane_lvds_8_1.serial_rst;
wire pixel_rst = dut.u_hdmi2phy_wrapper.u0_lane_lvds_8_1.pixel_rst;
integer serial_cycle=0, last_load=-1, load_count=0, iteration;
reg [9:0] expected_shift;
reg check_shift;
realtime last_audio_edge=-1, last_serial_edge=-1, last_pixel_edge=-1;
always @(posedge audio_clk) last_audio_edge=$realtime;
always @(posedge serial_clk) last_serial_edge=$realtime;
always @(posedge pixel_clk) last_pixel_edge=$realtime;
always @(negedge dut.rst_audio_stream)
    if ($realtime != last_audio_edge) $fatal(1,"audio reset released off-clock");
always @(negedge lane_rst)
    if ($realtime != last_serial_edge) $fatal(1,"serial reset released off-clock");
always @(negedge pixel_rst)
    if ($realtime != last_pixel_edge) $fatal(1,"pixel reset released off-clock");

// Verify serializer load cadence and the complete ten-bit word after reset.
always @(posedge serial_clk) begin
    serial_cycle=serial_cycle+1;
    check_shift=!lane_rst;
    if (lane_rst) begin last_load=-1; end
    else if (dut.u_hdmi2phy_wrapper.u0_lane_lvds_8_1.S_load_en_2d) begin
        if(last_load>=0 && serial_cycle-last_load!=5)
            $fatal(1,"serializer lost its five-cycle word cadence");
        last_load=serial_cycle;
        load_count=load_count+1;
        expected_shift=10'b0110100011; // Wrapper reverses 10'b1100010110.
    end else begin
        expected_shift=dut.u_hdmi2phy_wrapper.u0_lane_lvds_8_1.S_shift_data << 2;
    end
    #0.001;
    if(check_shift && !lane_rst &&
       dut.u_hdmi2phy_wrapper.u0_lane_lvds_8_1.S_shift_data!==expected_shift)
        $fatal(1,"serializer word or shift corrupted after reset");
end

task check_release;
begin
    fork
        begin
            repeat(2) begin @(posedge audio_clk); #0.001;
                if(!dut.rst_audio_stream) $fatal(1,"early audio reset release");
            end
            @(posedge audio_clk); #0.001;
            if(dut.rst_audio_stream) $fatal(1,"audio reset stuck");
        end
        begin
            repeat(2) begin @(posedge serial_clk); #0.001;
                if(!lane_rst) $fatal(1,"early serial reset release");
            end
            @(posedge serial_clk); #0.001;
            if(lane_rst) $fatal(1,"serial reset stuck");
        end
        begin
            repeat(2) begin @(posedge pixel_clk); #0.001;
                if(!pixel_rst) $fatal(1,"early pixel reset release");
            end
            @(posedge pixel_clk); #0.001;
            if(pixel_rst) $fatal(1,"pixel reset stuck");
        end
    join
end
endtask

initial begin
    force dut.video_clk=pixel_clk;
    force dut.hdmi_5x_clk=serial_clk;
    force dut.audio_mclk=audio_clk;
    force dut.audio_pll_lock=pll_lock;
    force dut.camera_mode_request=request;
    force dut.camera_mode_value=mode;
    force dut.video_playback_done=done;
    force dut.image_scan_done=1'b0;
    force dut.image_count=5'd3;
    force dut.tmds_ch0_data=10'b1100010110;
    force dut.tmds_ch1_data=10'b1100010110;
    force dut.tmds_ch2_data=10'b1100010110;
    force dut.tmds_clk_data=10'b1100010110;
    force dut.audio_fifo_empty=1'b1;
    force dut.audio_fifo_count=13'd0;
    force dut.music_fifo_reset_toggle=1'b0;
    force dut.music_playing=1'b0;
    force dut.video_audio_hold=1'b0;

    // Every assertion must reset immediately, even without a clock edge.
    for(iteration=0; iteration<12; iteration=iteration+1) begin
        #(3.137+iteration*1.231); rst_n=0;
        #0.001;
        if(!dut.rst_audio_stream || !lane_rst || !pixel_rst)
            $fatal(1,"asynchronous reset assertion missed");
        #(1.173+iteration*0.719); rst_n=1;
        check_release;
        #300;
        if(dut.u_pcm_i2s_tx.fifo_rd_en!==0)
            $fatal(1,"audio fetched data while disabled");
    end

    // Repeated switch to video, then an EOF-triggered return to images.
    repeat(4) begin
        @(negedge clk); mode=2; request=1;
        @(negedge clk); request=0;
        if(dut.display_mode!==2) $fatal(1,"video mode entry failed");
        @(negedge dut.rst_all); check_release;
        #500;
        @(negedge clk); done=1;
        @(negedge clk); done=0;
        if(dut.display_mode!==0 || !dut.resume_images_pending)
            $fatal(1,"EOF return did not reset into images");
        @(negedge dut.rst_all); check_release;
        #500;
    end

    // PLL loss resets only audio and also releases synchronously.
    #13.317; pll_lock=0; #0.001;
    if(!dut.rst_audio_stream || lane_rst)
        $fatal(1,"audio PLL reset affected HDMI or missed audio");
    #7.213; pll_lock=1;
    repeat(2) begin @(posedge audio_clk); #0.001;
        if(!dut.rst_audio_stream) $fatal(1,"PLL reset released early");
    end
    @(posedge audio_clk); #0.001;
    if(dut.rst_audio_stream) $fatal(1,"PLL reset stuck");
    if(load_count<100) $fatal(1,"insufficient serialized words");
    $display("PASS media reset: 12 phase offsets, 4 video/EOF cycles, PLL recovery; %0d serialized words",load_count);
    $finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule

// Behavioral replacement for the vendor DDR output primitive, test only.
module EG_LOGIC_ODDR(input clk,rst,d1,d0,output reg q);
always @(posedge clk or negedge clk or posedge rst)
    if(rst) q<=0; else q<=clk ? d0 : d1;
endmodule
