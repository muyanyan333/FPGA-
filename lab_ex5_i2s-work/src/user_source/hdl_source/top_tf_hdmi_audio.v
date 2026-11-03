
module top(
    input                       clk,
    input                       rst_n,
    input                       key2,           // 图片模式=转场；音乐模式=上一首
    input                       key3,           // 图片模式=下一张；音乐模式=下一首
    input                       key4,           // 短按=模式内操作，长按=图片/音乐模式切换

    // Bluetooth UART on J1: GPIOA1=RX(G11), GPIOA0=TX(D14)
    input                       uart_rx,
    output                      uart_tx,
    // ASRPRO TX -> J1 GPIOA2 (G12), FPGA TX -> J1 GPIOA3 (F13) -> ASRPRO RX.
    input                       voice_rx,
    output                      voice_tx,
    input                       gesture_rx,
    input                       cam_pclk,
    input                       cam_vsync,
    input                       cam_href,
    input [7:0]                 cam_data,
    output                      cam_scl,
    inout                       cam_sda,
    output                      cam_reset_n,
    output                      cam_pwdn,

    output [7:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MV_ONLY_TEST = 1'b0;
parameter CAMERA_PREVIEW = 1'b0;
parameter CAMERA_AVAILABLE = 1'b0;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
// 位宽与 frame_read_write 的 ADDR_BITS(21) 端口对齐，避免 24bit -> 21bit 位宽告警
parameter [ADDR_BITS-1:0] FRAME_PIXELS = 21'd307200;   // 640*480
parameter [ADDR_BITS-1:0] OUTPUT_PIXELS = 21'd921600;  // 1280*720
parameter [ADDR_BITS-1:0] BUF0_ADDR    = 21'd0;
parameter [ADDR_BITS-1:0] BUF1_ADDR    = FRAME_PIXELS;

wire Sdr_init_done;
wire rst_all;
wire camera_mode;
wire camera_mode_request;
wire [1:0] camera_mode_value;
reg video_mode_reg;
wire video_mode = video_mode_reg;
reg [1:0] display_release_meta, display_release_sync;
wire [2:0] video_status;
wire [2:0] video_startup_stage;
wire video_playback_done;
wire video_audio_hold;
wire [1:0] display_mode = video_mode ? 2'd2 : {1'b0,camera_mode};
reg camera_mode_reg;
reg [5:0] mode_reset_count;
reg resume_images_pending;
wire resume_images_pulse = resume_images_pending && !video_mode &&
    mode_reset_count==0 && image_scan_done && image_count!=0;
reg [25:0] camera_key_hold;
reg camera_key_latched;
assign camera_mode = CAMERA_PREVIEW || (CAMERA_AVAILABLE && camera_mode_reg);
// Key2+Key3 held for 0.8 s toggles the source. Keep this controller out of
// rst_all so a mode change can reset the TF/SDRAM/camera pipelines safely.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        camera_mode_reg <= 1'b0;
        video_mode_reg <= 1'b0;
        mode_reset_count <= 0;
        resume_images_pending <= 0;
        camera_key_hold <= 0;
        camera_key_latched <= 0;
    end else begin
        if(resume_images_pulse) resume_images_pending<=0;
        if (mode_reset_count != 0) mode_reset_count <= mode_reset_count - 1'b1;
        if (CAMERA_AVAILABLE && !key2 && !key3) begin
            if (camera_key_hold < 26'd40_000_000)
                camera_key_hold <= camera_key_hold + 1'b1;
            else if (!camera_key_latched) begin
                camera_mode_reg <= ~camera_mode_reg;
                video_mode_reg <= 1'b0;
                mode_reset_count <= 6'd40;
                camera_key_latched <= 1'b1;
            end
        end else begin
            camera_key_hold <= 0;
            camera_key_latched <= 0;
        end
        if (camera_mode_request && camera_mode_value != display_mode &&
            (camera_mode_value != 2'd1 || CAMERA_AVAILABLE)) begin
            camera_mode_reg <= camera_mode_value == 2'd1;
            video_mode_reg <= camera_mode_value == 2'd2;
            resume_images_pending <= 0;
            mode_reset_count <= 6'd40;
        end
        if (video_mode && video_playback_done) begin
            resume_images_pending <= 1;
            video_mode_reg <= 1'b0;
            camera_mode_reg <= 1'b0;
            mode_reset_count <= 6'd40;
        end
    end
end
wire rst_audio;
// Reset both PCM FIFO domains together when changing the media source.
// UART is outside this reset so volume/mute survive mode changes.
wire rst_audio_stream_request = rst_audio | rst_all;
// Mode changes originate at 50 MHz. Assert immediately, but release the
// PCM state and read-side FIFO only after three audio-clock edges.
(* async_reg = "true" *) reg [2:0] audio_reset_release;
wire rst_audio_stream = audio_reset_release[2];
always @(posedge audio_mclk or posedge rst_audio_stream_request) begin
    if (rst_audio_stream_request) audio_reset_release <= 3'b111;
    else audio_reset_release <= {audio_reset_release[1:0], 1'b0};
end
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_pll_clk_unused;
// SD/MV/WAV control runs from the board 50 MHz clock.  The design needs
// roughly 12 ns at worst after routing, so driving it at 100 MHz is unsafe.
wire sd_card_clk = clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire [23:0] video_base_data;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
wire [3:0]  img_index;        // 当前显示图片序号(0-based)
wire [4:0]  disp_img_num;     // 显示用序号(1-based, 无图=0)
wire [3:0]  disp_tens;        // 十位
wire [3:0]  disp_units;       // 个位
wire [6:0]  seg_tens;         // 十位段码
wire [6:0]  seg_level;        // 亮度档位段码
wire [6:0]  seg_volume;
wire [3:0]  volume_units = (uart_volume_level == 4'd10) ? 4'd0 : uart_volume_level;
// 图片模式下用右侧两个空闲数码管显示当前选中的音乐序号。
wire [6:0]  seg_music_tens;
wire [6:0]  seg_music_units;
wire [4:0]  music_disp_num = (music_track_count != 5'd0) ?
                             music_track_number : 5'd0;
wire [3:0]  music_disp_tens  = (music_disp_num >= 5'd10) ? 4'd1 : 4'd0;
wire [3:0]  music_disp_units = (music_disp_num >= 5'd10) ?
                               (music_disp_num[3:0] - 4'd10) :
                               music_disp_num[3:0];
wire [3:0]  edit_level;       // 当前编辑属性档位
wire        auto_mode;        // 1=自动轮播模式, 0=手动模式
wire [4:0]  image_count;
wire        image_scan_done;
wire        uart_select_valid;
wire [3:0]  uart_select_index;
wire        uart_auto_pulse;
wire        uart_manual_pulse;
wire        uart_next_pulse;
wire        uart_prev_pulse;
wire        uart_music_prev_pulse;
wire        uart_music_next_pulse;
wire        uart_effect_toggle;
wire [1:0]  uart_effect_value;
wire        uart_brightness_toggle;
wire [3:0]  uart_brightness_value;
wire        uart_contrast_toggle;
wire [3:0]  uart_contrast_value;
wire        uart_notice_toggle;
wire [7:0]  uart_notice_flags;
wire [9:0]  uart_notice_width;
wire        uart_notice_receiving;
wire [9:0]  uart_notice_rd_addr;
wire [7:0]  uart_notice_rd_data;

// 转场效果选择（KEY2 循环切换）
// 2'd0 = C 直接切换(cut)，2'd1 = F 淡入淡出(fade)，2'd2 = S 滑动(slide)
wire [1:0]  transition_effect;
wire        key2_trig;
wire        key3_ui_trig;
wire        key4_short_pulse;
wire        key4_long_pulse;
wire        key2_pressed, key3_pressed, key4_pressed;
wire        next_background_pulse;
wire [6:0]  seg_mode_char;    // 模式字符段码：自动=A，手动=n
reg  [6:0]  seg_effect_char;  // 效果字符段码：C/F/S
wire        edit_active;
wire        volume_edit_active;
wire        key_volume_up, key_volume_down;
wire [2:0]  menu_item;        // H1 brightness, H2 contrast, H3 size, H4 aspect, H5 music
wire        image_size_edit = edit_active && !music_edit_active && (menu_item == 2'd2);
wire        image_size_step;
wire        image_aspect_edit = edit_active && !music_edit_active && (menu_item == 3'd3);
wire        image_geometry_edit = image_size_edit || image_aspect_edit;
wire        image_aspect_step;
wire [1:0]  current_image_aspect;
wire        uart_size_toggle, uart_aspect_toggle;
wire        uart_music_select_toggle;
wire [3:0]  uart_music_select_index;
reg         uart_music_select_seen;
wire        uart_music_select = uart_music_select_toggle ^ uart_music_select_seen;
wire        uart_playing_toggle, uart_playing_value;
wire        uart_lyric_enabled, uart_title_enabled, uart_spectrum_enabled;
wire [3:0] uart_volume_level;
wire uart_volume_muted;
wire [1:0]  uart_size_value, uart_aspect_value;
reg         uart_size_seen, uart_aspect_seen;
wire        uart_size_set = uart_size_toggle ^ uart_size_seen;
wire        uart_aspect_set = uart_aspect_toggle ^ uart_aspect_seen;
reg [1:0]   panel_aspect_v0, panel_aspect_v1;
reg         panel_aspect_edit_v0, panel_aspect_edit_v1;
wire [1:0]  current_image_size;

always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        uart_size_seen <= 1'b0;
        uart_aspect_seen <= 1'b0;
        uart_music_select_seen <= 1'b0;
        music_playing_sd0 <= 1'b1;
        music_playing_sd1 <= 1'b1;
        lyric_valid_sd0 <= 1'b0;
        lyric_valid_sd1 <= 1'b0;
        title_valid_sd0 <= 1'b0;
        title_valid_sd1 <= 1'b0;
    end else begin
        uart_size_seen <= uart_size_toggle;
        uart_aspect_seen <= uart_aspect_toggle;
        uart_music_select_seen <= uart_music_select_toggle;
        music_playing_sd0 <= music_playing;
        music_playing_sd1 <= music_playing_sd0;
        lyric_valid_sd0 <= lyric_valid;
        lyric_valid_sd1 <= lyric_valid_sd0;
        title_valid_sd0 <= title_valid;
        title_valid_sd1 <= title_valid_sd0;
    end
end
reg [1:0]   panel_size_v0, panel_size_v1;
reg         panel_size_edit_v0, panel_size_edit_v1;
wire        edit_property = (menu_item == 2'd1);
wire [3:0]  brightness_level;
wire [3:0]  contrast_level;
wire        mode_short_toggle = 1'b0;
wire        music_mode = 1'b1; // Unified player: music with background images.
wire        music_playing;
wire        music_prev_toggle, music_next_toggle;
wire [3:0]  music_track_index;
wire [4:0]  music_track_count;
wire [4:0]  music_track_number;
wire [15:0] music_track_map;
wire        lyric_pixel_on;
wire        title_pixel_on;
wire        lyric_valid;
wire        title_valid;
wire        music_fifo_reset_toggle;
reg         music_fifo_rst_sd_seen;
reg  [2:0]  music_fifo_rst_audio_sync;
wire        music_fifo_rst_wr_pulse = music_fifo_reset_toggle ^ music_fifo_rst_sd_seen;
wire        music_fifo_rst_rd_pulse = music_fifo_rst_audio_sync[2] ^ music_fifo_rst_audio_sync[1];
reg         music_mode_v0, music_mode_v1;
// H3 音乐属性编辑状态，以及右侧属性面板的 video_clk 域同步值。
wire        music_edit_active;
reg  [4:0]  panel_track_v0, panel_track_v1;
reg  [4:0]  panel_tcount_v0, panel_tcount_v1;
reg  [4:0]  panel_image_v0, panel_image_v1;
reg  [4:0]  panel_icount_v0, panel_icount_v1;
reg  [1:0]  panel_effect_v0, panel_effect_v1;
reg         panel_playing_v0, panel_playing_v1;
reg         panel_lyric_v0, panel_lyric_v1, panel_title_v0, panel_title_v1;
reg         panel_enable_v0, panel_enable_v1;
wire        panel_on, panel_text_on;
wire [4:0]  panel_track_src = (music_track_count != 5'd0) ?
                              music_track_number : 5'd0;
wire        panel_enable_src = music_edit_active ||
                               (edit_active && (menu_item >= 2'd2));
reg  [1:0]  music_enable_audio;
reg [1:0] video_hold_audio;
always @(posedge audio_mclk or posedge rst_audio_stream) begin
    if (rst_audio_stream) video_hold_audio<=0;
    else video_hold_audio<={video_hold_audio[0],video_audio_hold};
end
reg         uart_effect_meta, uart_effect_sync, uart_effect_seen;
reg  [1:0]  uart_effect_value_meta, uart_effect_value_sync;
reg         uart_brightness_meta, uart_brightness_sync, uart_brightness_seen;
reg  [3:0]  uart_brightness_value_meta, uart_brightness_value_sync;
reg         uart_contrast_meta, uart_contrast_sync, uart_contrast_seen;
reg  [3:0]  uart_contrast_value_meta, uart_contrast_value_sync;
reg         uart_playing_meta, uart_playing_sync, uart_playing_seen;
reg         uart_playing_value_meta, uart_playing_value_sync;
wire        uart_playing_event = uart_playing_sync ^ uart_playing_seen;
reg         music_playing_sd0, music_playing_sd1;
reg         lyric_valid_sd0, lyric_valid_sd1, title_valid_sd0, title_valid_sd1;
wire        uart_effect_event = uart_effect_sync ^ uart_effect_seen;
wire        uart_brightness_event = uart_brightness_sync ^ uart_brightness_seen;
wire        uart_contrast_event = uart_contrast_sync ^ uart_contrast_seen;

// ===================== 转场引擎（fade to black，video_clk 域）=====================
reg  [1:0]  disp_sync0, disp_sync1, disp_sync2;
wire [8:0]  brightness;
wire [1:0]  disp_buf_idx_eff;
wire        slide_active_eff;
wire [9:0]  slide_progress_eff;
wire [1:0]  slide_old_buf_eff;
wire [1:0]  slide_new_buf_eff;
reg         vs_d;
wire        vs_pos;
wire [16:0] r_scaled, g_scaled, b_scaled;
wire [23:0] vout_dim;
reg  [3:0]  brightness_level_v0, brightness_level_v1;
reg  [3:0]  contrast_level_v0, contrast_level_v1;
reg         edit_property_v0, edit_property_v1;
reg         edit_active_v0, edit_active_v1;
reg  [8:0]  user_brightness;
reg  [9:0]  user_contrast;
wire [17:0] brightness_product;
wire [8:0]  effective_brightness;
wire [7:0]  r_contrast, g_contrast, b_contrast;
reg         osd_de_d;
reg         osd_line_seen;
reg  [10:0] osd_x;
reg  [9:0]  osd_y;
wire        osd_box_on;
wire        osd_l_on;
wire        osd_level_on;
wire        osd_text_on;
wire        picture_area_on;
wire        time_panel_on, time_text_on;
wire        waveform_trace_on = 1'b0; // 关闭屏幕中部波形，仅保留底部FFT频谱柱
wire        notice_panel_on, notice_text_on;
wire [23:0] overlay_base_data;
reg  [24:0] uptime_div;
reg  [5:0]  uptime_sec, uptime_min;
reg  [6:0]  uptime_hour;
reg         notice_toggle_meta, notice_toggle_sync, notice_toggle_seen;
reg  [7:0]  notice_flags_meta, notice_flags_video;
reg  [9:0]  notice_width_meta, notice_width_video;
reg         notice_receiving_meta, notice_receiving_video;
reg  [2:0]  notice_frame_div;
reg  signed [11:0] notice_scroll_x;
wire signed [12:0] notice_local_x;
wire        notice_update_event = notice_toggle_sync ^ notice_toggle_seen;
wire [3:0]  notice_row;
wire [3:0]  time_char_index;
wire [3:0]  time_char_code;
wire [2:0]  time_font_row, time_font_col;
wire [4:0]  time_row_bits;
wire [6:0] fft_bar_addr;
wire [5:0] fft_bar_level;
wire       fft_spectrum_ready;
wire [23:0] music_visual_pixel;
wire [2:0]  osd_l_col;
wire [2:0]  osd_level_col;
wire [2:0]  osd_row;
wire [4:0]  osd_l_row_bits;
wire [4:0]  osd_level_row_bits;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        sd_card_write_full;
wire        frame_write_v_flip;
wire        frame_write_finish;
reg         frame_write_toggle_mem;
reg         cam_frame_finish_toggle_mem;
wire cam_cfg_done, cam_cfg_error;
wire cam_write_req, cam_write_en, cam_write_bank, cam_display_bank;
wire cam_display_valid, cam_frame_error;
wire [31:0] cam_write_data;
wire cam_write_full;
wire cam_debug_ack_seen, cam_debug_href_seen, cam_debug_fifo_overflow;
wire cam_debug_short_frame, cam_debug_pixels_complete, cam_debug_finish_seen;
reg [5:0] cam_debug_sync0, cam_debug_sync1;
reg [1:0] cam_display_bank_sync, cam_display_valid_sync;
// HDMI diagnostic colors before the first complete camera frame:
// blue=initializing, red=SCCB failed, cyan=no PCLK, yellow=no VSYNC,
// magenta=frame/FIFO path has not produced a complete frame.
reg [15:0] cam_pclk_div;
reg cam_pclk_heartbeat, cam_vsync_seen;
reg [1:0] cam_heartbeat_sync, cam_vsync_seen_sync;
reg [1:0] cam_cfg_done_sync, cam_cfg_error_sync;
reg [1:0] cam_write_req_sync, cam_sdram_ready_sync;
reg cam_write_req_seen;
reg cam_pclk_seen;
always @(posedge cam_pclk or posedge rst_all) begin
  if (rst_all) begin
    cam_pclk_div <= 0;
    cam_pclk_heartbeat <= 0;
    cam_vsync_seen <= 0;
  end else begin
    cam_pclk_div <= cam_pclk_div + 1'b1;
    if (cam_pclk_div == 16'hffff)
      cam_pclk_heartbeat <= ~cam_pclk_heartbeat;
    if (cam_vsync)
      cam_vsync_seen <= 1;
  end
end
always @(posedge video_clk or posedge rst_all) begin
  if (rst_all) begin
    cam_heartbeat_sync <= 0;
    cam_vsync_seen_sync <= 0;
    cam_cfg_done_sync <= 0;
    cam_cfg_error_sync <= 0;
    cam_write_req_sync <= 0;
    cam_sdram_ready_sync <= 0;
    cam_write_req_seen <= 0;
    cam_pclk_seen <= 0;
    cam_debug_sync0 <= 0;
    cam_debug_sync1 <= 0;
  end else begin
    cam_heartbeat_sync <= {cam_heartbeat_sync[0],cam_pclk_heartbeat};
    cam_vsync_seen_sync <= {cam_vsync_seen_sync[0],cam_vsync_seen};
    cam_cfg_done_sync <= {cam_cfg_done_sync[0],cam_cfg_done};
    cam_cfg_error_sync <= {cam_cfg_error_sync[0],cam_cfg_error};
    cam_write_req_sync <= {cam_write_req_sync[0],cam_write_req};
    cam_sdram_ready_sync <= {cam_sdram_ready_sync[0],Sdr_init_done};
    if (cam_write_req_sync[1]) cam_write_req_seen <= 1;
    cam_debug_sync0 <= {cam_debug_ack_seen,cam_debug_href_seen,
                        cam_debug_fifo_overflow,cam_debug_short_frame,
                        cam_debug_pixels_complete,cam_debug_finish_seen};
    cam_debug_sync1 <= cam_debug_sync0;
    if (cam_heartbeat_sync[1] != cam_heartbeat_sync[0])
      cam_pclk_seen <= 1;
  end
end
generate if (CAMERA_PREVIEW || CAMERA_AVAILABLE) begin : g_camera
  ov2640_sccb_init u_cam_init(
    .clk(clk), .rst(rst_all | !camera_mode), .scl(cam_scl), .sda(cam_sda),
    .reset_n(cam_reset_n), .pwdn(cam_pwdn),
    .done(cam_cfg_done), .error(cam_cfg_error)
  );
  ov2640_dvp_capture u_cam_capture(
    .pclk(cam_pclk), .rst(rst_all | !camera_mode), .init_done(cam_cfg_done),
    .vsync(cam_vsync), .href(cam_href), .data(cam_data),
    .write_ack(sd_card_write_req_ack), .write_finish_toggle(cam_frame_finish_toggle_mem),
    .write_full(cam_write_full), .write_req(cam_write_req),
    .write_en(cam_write_en), .write_data(cam_write_data),
    .write_bank(cam_write_bank), .display_bank(cam_display_bank),
    .display_valid(cam_display_valid), .frame_error(cam_frame_error),
    .debug_ack_seen(cam_debug_ack_seen),
    .debug_href_seen(cam_debug_href_seen),
    .debug_fifo_overflow(cam_debug_fifo_overflow),
    .debug_short_frame(cam_debug_short_frame),
    .debug_pixels_complete(cam_debug_pixels_complete),
    .debug_finish_seen(cam_debug_finish_seen)
  );
end else begin : g_no_camera
  assign cam_scl = 1'b1;
  assign cam_sda = 1'bz;
  assign cam_reset_n = 1'b0;
  assign cam_pwdn = 1'b1;
  assign cam_cfg_done = 1'b0;
  assign cam_cfg_error = 1'b0;
  assign cam_write_req = 1'b0;
  assign cam_write_en = 1'b0;
  assign cam_write_data = 32'd0;
  assign cam_write_bank = 1'b0;
  assign cam_display_bank = 1'b0;
  assign cam_display_valid = 1'b0;
  assign cam_frame_error = 1'b0;
  assign cam_debug_ack_seen = 1'b0;
  assign cam_debug_href_seen = 1'b0;
  assign cam_debug_fifo_overflow = 1'b0;
  assign cam_debug_short_frame = 1'b0;
  assign cam_debug_pixels_complete = 1'b0;
  assign cam_debug_finish_seen = 1'b0;
end endgenerate
always @(posedge video_clk or posedge rst_all) begin
  if (rst_all) begin
    cam_display_bank_sync <= 0;
    cam_display_valid_sync <= 0;
  end else begin
    cam_display_bank_sync <= {cam_display_bank_sync[0],cam_display_bank};
    cam_display_valid_sync <= {cam_display_valid_sync[0],cam_display_valid};
  end
end

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        pcm_i2s_bclk, pcm_i2s_lrck, pcm_i2s_dout;
wire        audio_frame_valid, audio_fifo_full, audio_fifo_empty;
wire [31:0] audio_frame_data, audio_fifo_rd_data;
wire [12:0] audio_fifo_count;
wire        audio_fifo_rd_en, wav_stream_valid;
reg         wav_play_started;
reg         audio_frame_tick_toggle;
reg [1:0]   wav_play_sync;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 视频/TF/SDRAM 不应被音频 PLL 锁定状态拖住，否则音频 PLL 未锁定会导致整机黑屏。
assign rst_all   = ~rst_n | (mode_reset_count != 0);
assign rst_audio = ~rst_n | ~audio_pll_lock;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_pll_clk_unused),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// ===================== Bluetooth UART image control =====================
// RX frame : A5 CMD ARG CHECK, CHECK=A5^CMD^ARG
// CMD 01=query, 02=play ARG(1..16), 03=auto, 04=next, 05=previous,
//     06=manual, 07=effect, 08=brightness, 09=contrast
// TX frame : 5A 81 COUNT CURRENT MODE MAP_L MAP_H CHECK
uart_image_control #(
    .CLK_FREQ_HZ       (50_000_000),
    .BAUD_RATE         (9600)
) u_uart_image_control(
    .clk               (sd_card_clk),
    .rst               (!rst_n),
    .uart_rx           (uart_rx),
    .voice_rx          (voice_rx),
    .voice_tx          (voice_tx),
    .gesture_rx        (gesture_rx),
    .key_volume_up     (key_volume_up),
    .key_volume_down   (key_volume_down),
    .key_volume_set    (1'b0),
    .key_volume_value  (4'd0),
    .uart_tx           (uart_tx),
    .image_count       (image_count),
    .current_index     (img_index),
    .auto_mode         (auto_mode),
    .scan_done         (image_scan_done),
    .transition_effect (transition_effect),
    .brightness_level  (brightness_level),
    .contrast_level    (contrast_level),
    .image_size        (current_image_size),
    .image_aspect      (current_image_aspect),
    .music_track_number(music_track_number),
    .music_track_count (music_track_count),
    .music_track_map   (music_track_map),
    .music_playing     (music_playing_sd1),
    .lyric_valid       (lyric_valid_sd1),
    .title_valid       (title_valid_sd1),
    .camera_mode       (display_mode),
    .video_status      (video_status),
    .camera_mode_request(camera_mode_request),
    .camera_mode_value (camera_mode_value),
    .select_valid      (uart_select_valid),
    .select_index      (uart_select_index),
    .auto_pulse        (uart_auto_pulse),
    .manual_pulse      (uart_manual_pulse),
    .next_pulse        (uart_next_pulse),
    .prev_pulse        (uart_prev_pulse),
    .music_prev_pulse  (uart_music_prev_pulse),
    .music_next_pulse  (uart_music_next_pulse),
    .effect_toggle     (uart_effect_toggle),
    .effect_value      (uart_effect_value),
    .brightness_toggle (uart_brightness_toggle),
    .brightness_value  (uart_brightness_value),
    .contrast_toggle   (uart_contrast_toggle),
    .contrast_value    (uart_contrast_value),
    .size_toggle       (uart_size_toggle),
    .size_value        (uart_size_value),
    .aspect_toggle     (uart_aspect_toggle),
    .aspect_value      (uart_aspect_value),
    .music_select_toggle(uart_music_select_toggle),
    .music_select_index(uart_music_select_index),
    .playing_toggle    (uart_playing_toggle),
    .playing_value     (uart_playing_value),
    .lyric_enabled     (uart_lyric_enabled),
    .title_enabled     (uart_title_enabled),
    .spectrum_enabled  (uart_spectrum_enabled),
    .volume_level      (uart_volume_level),
    .volume_muted      (uart_volume_muted),
    .notice_toggle     (uart_notice_toggle),
    .notice_flags      (uart_notice_flags),
    .notice_width      (uart_notice_width),
    .notice_receiving  (uart_notice_receiving),
    .notice_rd_clk     (video_clk),
    .notice_rd_addr    (uart_notice_rd_addr),
    .notice_rd_data    (uart_notice_rd_data)
);

// 音频 PLL 只提供音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish && !camera_mode)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all) cam_frame_finish_toggle_mem <= 1'b0;
    else if (frame_write_finish && camera_mode)
        cam_frame_finish_toggle_mem <= ~cam_frame_finish_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (50_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (5'd12),
    .FAST_DIV0         (!MV_ONLY_TEST),
    .USE_KEY_NEXT_EVENT(1),
    .WAIT_DISPLAY_RELEASE(1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all | camera_mode),
    .key_next          (1'b1),
    .key_next_event    (next_background_pulse),
    .display_released_bank(display_release_sync),
    .image_size_step   (image_size_step),
    .image_size_edit   (image_geometry_edit),
    .current_image_size(current_image_size),
    .image_aspect_step (image_aspect_step),
    .remote_size_set   (uart_size_set),
    .remote_size_value (uart_size_value),
    .remote_aspect_set (uart_aspect_set),
    .remote_aspect_value(uart_aspect_value),
    .current_image_aspect(current_image_aspect),
    .key_mode          (1'b1),
    .key_mode_toggle   (mode_short_toggle),
    .edit_active       (edit_active),
    .remote_select_valid(uart_select_valid),
    .remote_select_index(uart_select_index),
    .remote_auto       (uart_auto_pulse || resume_images_pulse),
    .remote_manual     (uart_manual_pulse),
    .remote_next       (uart_next_pulse),
    .remote_prev       (uart_prev_pulse),
    .music_mode        (music_mode && !video_mode),
    .video_mode        (video_mode),
    .video_startup_stage(video_startup_stage),
    .video_playback_done(video_playback_done),
    .video_audio_hold(video_audio_hold),
    .video_status      (video_status),
    .music_prev_toggle (music_prev_toggle),
    .music_next_toggle (music_next_toggle),
    .remote_music_prev (uart_music_prev_pulse),
    .remote_music_next (uart_music_next_pulse),
    .remote_music_select(uart_music_select),
    .remote_music_index (uart_music_select_index),
    .audio_frame_tick_toggle(audio_frame_tick_toggle),
    .auto_mode         (auto_mode),
    .image_count       (image_count),
    .scan_complete     (image_scan_done),
    .audio_fifo_count  (audio_fifo_count),
    .audio_fifo_full   (audio_fifo_full),
    .audio_frame_valid (audio_frame_valid),
    .audio_frame_data  (audio_frame_data),
    .wav_stream_valid  (wav_stream_valid),
    .music_track_index (music_track_index),
    .music_track_count (music_track_count),
    .music_track_number(music_track_number),
    .music_track_map   (music_track_map),
    .music_fifo_reset_toggle(music_fifo_reset_toggle),
    .video_clk         (video_clk),
    .pixel_x           (osd_x),
    .pixel_y           (osd_y),
    .lyric_pixel_on    (lyric_pixel_on),
    .title_pixel_on    (title_pixel_on),
    .lyric_valid       (lyric_valid),
    .title_valid       (title_valid),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .img_index         (img_index),

    .write_req         (sd_card_write_req),
    .write_req_ack     (camera_mode ? 1'b0 : sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .frame_write_v_flip(frame_write_v_flip),
    .write_full        (sd_card_write_full),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_units(
    .bin_data          (disp_units),
    .seg_data          (seg_data_0)
);

seg_decoder seg_decoder_tens(
    .bin_data          (disp_tens),
    .seg_data          (seg_tens)
);

seg_decoder seg_decoder_level(
    .bin_data          (edit_level),
    .seg_data          (seg_level)
);

seg_decoder seg_decoder_volume(
    .bin_data          (volume_units),
    .seg_data          (seg_volume)
);

seg_decoder seg_decoder_music_tens(
    .bin_data          (music_disp_tens),
    .seg_data          (seg_music_tens)
);

seg_decoder seg_decoder_music_units(
    .bin_data          (music_disp_units),
    .seg_data          (seg_music_units)
);

assign edit_level = image_aspect_edit ? ({2'b00,current_image_aspect} + 4'd1) :
                    image_size_edit ? ({2'b00,current_image_size} + 4'd1) :
                    edit_property ? contrast_level : brightness_level;

// ===================== KEY2：转场效果选择 =====================
// 按下一次循环切换：C(直接切) -> F(淡入淡出) -> S(滑动) -> C
player_button_debounce u_key2_deb(
    .I_clk             (clk),
    .I_rst_n           (rst_n),
    .I_key_in          (key2),
    .O_key_trig_out    (key2_trig),
    .O_key_pressed     (key2_pressed)
);

player_button_debounce u_key3_ui_deb(
    .I_clk             (clk),
    .I_rst_n           (rst_n),
    .I_key_in          (key3),
    .O_key_trig_out    (key3_ui_trig),
    .O_key_pressed     (key3_pressed)
);

key_short_long #(
    .CLK_FREQ_HZ       (50_000_000),
    .DEBOUNCE_MS       (20),
    .LONG_PRESS_MS     (2000)
) u_key4_short_long(
    .clk               (clk),
    .rst_n             (rst_n),
    .key_n             (key4),
    .short_pulse       (key4_short_pulse),
    .long_pulse        (key4_long_pulse),
    .pressed           (key4_pressed)
);

// UART属性命令从100MHz SD时钟域以toggle方式同步到板载50MHz时钟域。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_effect_meta <= 1'b0;
        uart_effect_sync <= 1'b0;
        uart_effect_seen <= 1'b0;
        uart_effect_value_meta <= 2'd0;
        uart_effect_value_sync <= 2'd0;
        uart_brightness_meta <= 1'b0;
        uart_brightness_sync <= 1'b0;
        uart_brightness_seen <= 1'b0;
        uart_brightness_value_meta <= 4'd9;
        uart_brightness_value_sync <= 4'd9;
        uart_contrast_meta <= 1'b0;
        uart_contrast_sync <= 1'b0;
        uart_contrast_seen <= 1'b0;
        uart_contrast_value_meta <= 4'd5;
        uart_contrast_value_sync <= 4'd5;
        uart_playing_meta <= 1'b0;
        uart_playing_sync <= 1'b0;
        uart_playing_seen <= 1'b0;
        uart_playing_value_meta <= 1'b1;
        uart_playing_value_sync <= 1'b1;
    end else begin
        uart_effect_meta <= uart_effect_toggle;
        uart_effect_sync <= uart_effect_meta;
        uart_effect_seen <= uart_effect_sync;
        uart_effect_value_meta <= uart_effect_value;
        uart_effect_value_sync <= uart_effect_value_meta;
        uart_brightness_meta <= uart_brightness_toggle;
        uart_brightness_sync <= uart_brightness_meta;
        uart_brightness_seen <= uart_brightness_sync;
        uart_brightness_value_meta <= uart_brightness_value;
        uart_brightness_value_sync <= uart_brightness_value_meta;
        uart_contrast_meta <= uart_contrast_toggle;
        uart_contrast_sync <= uart_contrast_meta;
        uart_contrast_seen <= uart_contrast_sync;
        uart_contrast_value_meta <= uart_contrast_value;
        uart_contrast_value_sync <= uart_contrast_value_meta;
        uart_playing_meta <= uart_playing_toggle;
        uart_playing_sync <= uart_playing_meta;
        uart_playing_seen <= uart_playing_sync;
        uart_playing_value_meta <= uart_playing_value;
        uart_playing_value_sync <= uart_playing_value_meta;
    end
end

// One owner for UI state, key actions and parameter updates.
player_key_control u_player_keys(
    .clk(clk), .rst_n(rst_n),
    .key2_pulse(key2_trig), .key3_pulse(key3_ui_trig),
    .key4_short(key4_short_pulse), .key4_long(key4_long_pulse),
    .key2_held(key2_pressed), .key3_held(key3_pressed), .key4_held(key4_pressed),
    .remote_brightness(uart_brightness_event),
    .remote_brightness_value(uart_brightness_value_sync),
    .remote_contrast(uart_contrast_event),
    .remote_contrast_value(uart_contrast_value_sync),
    .remote_effect(uart_effect_event), .remote_effect_value(uart_effect_value_sync),
    .remote_playing(uart_playing_event), .remote_playing_value(uart_playing_value_sync),
    .edit_active(edit_active), .music_edit_active(music_edit_active),
    .volume_edit_active(volume_edit_active),
    .menu_item(menu_item), .brightness_level(brightness_level),
    .contrast_level(contrast_level), .transition_effect(transition_effect),
    .music_playing(music_playing),
    .music_prev_toggle(music_prev_toggle), .music_next_toggle(music_next_toggle),
    .next_background_pulse(next_background_pulse),
    .image_size_step(image_size_step), .image_aspect_step(image_aspect_step),
    .key_volume_up(key_volume_up), .key_volume_down(key_volume_down)
);


// 模式数字段码（共阳低有效，{g,f,e,d,c,b,a}）：自动=1，手动=2
// 1=7'b111_1001(b,c 亮)，2=7'b010_0100(a,b,d,e,g 亮)
assign seg_mode_char = music_mode ? (music_playing ? 7'b000_1100 : 7'b001_0010) :
                       (auto_mode ? 7'b111_1001 : 7'b010_0100); // P / 1 / 2

// 效果字符段码：C=7'b1000110(a,d,e,f)，F=7'b0001110(a,e,f,g)，S=7'b0010010(a,c,d,f,g)
always @(*) begin
    case(transition_effect)
        2'd1:    seg_effect_char = 7'b0001110; // F
        2'd2:    seg_effect_char = 7'b0010010; // S
        default: seg_effect_char = 7'b1000110; // C
    endcase
end

// ===================== 转场状态机 =====================
// disp_buf_idx 来自 sd_card_clk 域，打三拍同步到 video_clk 域
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        disp_sync0 <= 2'd0; disp_sync1 <= 2'd0; disp_sync2 <= 2'd0;
    end else begin
        disp_sync0 <= disp_buf_idx;
        disp_sync1 <= disp_sync0;
        disp_sync2 <= disp_sync1;
    end
end

// 手机通知同步到视频域，并在屏幕上方循环滚动。
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        notice_toggle_meta    <= 1'b0;
        notice_toggle_sync    <= 1'b0;
        notice_toggle_seen    <= 1'b0;
        notice_flags_meta     <= 8'd0;
        notice_flags_video    <= 8'd0;
        notice_width_meta     <= 10'd0;
        notice_width_video    <= 10'd0;
        notice_receiving_meta <= 1'b0;
        notice_receiving_video<= 1'b0;
        notice_frame_div      <= 3'd0;
        notice_scroll_x       <= 12'sd640;
    end else begin
        notice_toggle_meta     <= uart_notice_toggle;
        notice_toggle_sync     <= notice_toggle_meta;
        notice_toggle_seen     <= notice_toggle_sync;
        notice_flags_meta      <= uart_notice_flags;
        notice_flags_video     <= notice_flags_meta;
        notice_width_meta      <= uart_notice_width;
        notice_width_video     <= notice_width_meta;
        notice_receiving_meta  <= uart_notice_receiving;
        notice_receiving_video <= notice_receiving_meta;

        if(notice_update_event) begin
            notice_scroll_x  <= 12'sd640;
            notice_frame_div <= 3'd0;
        end else if(vs_pos && notice_flags_video[0] && !notice_receiving_video &&
                    (notice_width_video != 10'd0)) begin
            if((notice_flags_video[3:2] == 2'd0 && notice_frame_div >= 3'd3) ||
               (notice_flags_video[3:2] == 2'd1 && notice_frame_div >= 3'd1) ||
               (notice_flags_video[3:2] >= 2'd2)) begin
                notice_frame_div <= 3'd0;
                notice_scroll_x <= (notice_scroll_x <= -$signed({2'b00,notice_width_video})) ?
                                   12'sd640 : notice_scroll_x - 1'b1;
            end else begin
                notice_frame_div <= notice_frame_div + 1'b1;
            end
        end
    end
end

always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) vs_d <= 1'b0;
    else        vs_d <= vs;
end
assign vs_pos = ~vs_d & vs;

// Read descriptors and brightness change together before frame prefetch.
wire [1:0] display_released_bank;

always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        display_release_meta <= 0;
        display_release_sync <= 0;
    end else begin
        display_release_meta <= display_released_bank;
        display_release_sync <= display_release_meta;
    end
end
image_transition_control u_image_transition (
    .clk(video_clk), .rst(rst_all), .read_req(video_read_req),
    .committed_bank(disp_sync2), .display_valid(display_valid),
    .effect(video_mode ? 2'd0 : transition_effect), .geometry_edit(panel_size_edit_v1),
    .read_bank(disp_buf_idx_eff), .slide_active(slide_active_eff),
    .slide_progress(slide_progress_eff), .old_bank(slide_old_buf_eff),
    .new_bank(slide_new_buf_eff), .brightness(brightness),
    .released_bank(display_released_bank)
);
// 用户亮度/对比度及编辑属性跨到video_clk域。
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        brightness_level_v0 <= 4'd9;
        brightness_level_v1 <= 4'd9;
        contrast_level_v0   <= 4'd5;
        contrast_level_v1   <= 4'd5;
        edit_property_v0    <= 1'b0;
        edit_property_v1    <= 1'b0;
        edit_active_v0      <= 1'b0;
        edit_active_v1      <= 1'b0;
        music_mode_v0       <= 1'b0;
        music_mode_v1       <= 1'b0;
        panel_track_v0      <= 5'd0;
        panel_track_v1      <= 5'd0;
        panel_tcount_v0     <= 5'd0;
        panel_tcount_v1     <= 5'd0;
        panel_image_v0      <= 5'd0;
        panel_image_v1      <= 5'd0;
        panel_icount_v0     <= 5'd0;
        panel_icount_v1     <= 5'd0;
        panel_effect_v0     <= 2'd0;
        panel_effect_v1     <= 2'd0;
        panel_playing_v0    <= 1'b0;
        panel_playing_v1    <= 1'b0;
        panel_lyric_v0      <= 1'b1;
        panel_lyric_v1      <= 1'b1;
        panel_title_v0      <= 1'b1;
        panel_title_v1      <= 1'b1;
        panel_enable_v0     <= 1'b0;
        panel_enable_v1     <= 1'b0;
        panel_size_v0       <= 2'd0;
        panel_size_v1       <= 2'd0;
        panel_size_edit_v0  <= 1'b0;
        panel_size_edit_v1  <= 1'b0;
        panel_aspect_v0     <= 2'd0;
        panel_aspect_v1     <= 2'd0;
        panel_aspect_edit_v0 <= 1'b0;
        panel_aspect_edit_v1 <= 1'b0;
    end else begin
        brightness_level_v0 <= brightness_level;
        brightness_level_v1 <= brightness_level_v0;
        contrast_level_v0   <= contrast_level;
        contrast_level_v1   <= contrast_level_v0;
        edit_property_v0    <= edit_property;
        edit_property_v1    <= edit_property_v0;
        edit_active_v0      <= edit_active;
        edit_active_v1      <= edit_active_v0;
        music_mode_v0       <= music_mode;
        music_mode_v1       <= music_mode_v0;
        panel_track_v0      <= panel_track_src;
        panel_track_v1      <= panel_track_v0;
        panel_tcount_v0     <= music_track_count;
        panel_tcount_v1     <= panel_tcount_v0;
        panel_image_v0      <= disp_img_num;
        panel_image_v1      <= panel_image_v0;
        panel_icount_v0     <= image_count;
        panel_icount_v1     <= panel_icount_v0;
        panel_effect_v0     <= transition_effect;
        panel_effect_v1     <= panel_effect_v0;
        panel_playing_v0    <= music_playing;
        panel_playing_v1    <= panel_playing_v0;
        panel_lyric_v0      <= uart_lyric_enabled;
        panel_lyric_v1      <= panel_lyric_v0;
        panel_title_v0      <= uart_title_enabled;
        panel_title_v1      <= panel_title_v0;
        panel_enable_v0     <= panel_enable_src;
        panel_enable_v1     <= panel_enable_v0;
        panel_size_v0       <= current_image_size;
        panel_size_v1       <= panel_size_v0;
        panel_size_edit_v0  <= image_geometry_edit;
        panel_size_edit_v1  <= panel_size_edit_v0;
        panel_aspect_v0     <= current_image_aspect;
        panel_aspect_v1     <= panel_aspect_v0;
        panel_aspect_edit_v0 <= image_aspect_edit;
        panel_aspect_edit_v1 <= panel_aspect_edit_v0;
    end
end

always @(*) begin
    case(brightness_level_v1)
        4'd0: user_brightness = 9'd26;
        4'd1: user_brightness = 9'd51;
        4'd2: user_brightness = 9'd77;
        4'd3: user_brightness = 9'd102;
        4'd4: user_brightness = 9'd128;
        4'd5: user_brightness = 9'd154;
        4'd6: user_brightness = 9'd179;
        4'd7: user_brightness = 9'd205;
        4'd8: user_brightness = 9'd230;
        default: user_brightness = 9'd256;
    endcase
end

// S0~S9从低对比度到高对比度，S5为原图100%。
always @(*) begin
    case(contrast_level_v1)
        4'd0: user_contrast = 10'd64;
        4'd1: user_contrast = 10'd96;
        4'd2: user_contrast = 10'd128;
        4'd3: user_contrast = 10'd160;
        4'd4: user_contrast = 10'd192;
        4'd5: user_contrast = 10'd256;
        4'd6: user_contrast = 10'd320;
        4'd7: user_contrast = 10'd384;
        4'd8: user_contrast = 10'd448;
        default: user_contrast = 10'd512;
    endcase
end

function [7:0] apply_contrast;
    input [7:0] pixel;
    input [9:0] factor;
    reg signed [10:0] centered;
    reg signed [21:0] adjusted;
    begin
        centered = $signed({1'b0,pixel}) - 11'sd128;
        adjusted = (centered * $signed({1'b0,factor})) >>> 8;
        adjusted = adjusted + 22'sd128;
        if(adjusted < 0)
            apply_contrast = 8'd0;
        else if(adjusted > 22'sd255)
            apply_contrast = 8'd255;
        else
            apply_contrast = adjusted[7:0];
    end
endfunction

audio_fft1024 u_audio_fft1024 (
    .clk(video_clk), .rst(rst_all),
    .sample_valid(audio_valid), .sample(audio_left_data),
    .bar_addr(fft_bar_addr), .bar_level(fft_bar_level),
    .spectrum_ready(fft_spectrum_ready)
);

function [4:0] overlay_font_row;
    input [3:0] code;
    input [2:0] row;
    begin
        if(code <= 4'd9)
            overlay_font_row = osd_font_row(code, row);
        else begin
            case(code)
                4'd10: case(row) 0:overlay_font_row=5'b11111;1:overlay_font_row=5'b00100;2:overlay_font_row=5'b00100;3:overlay_font_row=5'b00100;4:overlay_font_row=5'b00100;5:overlay_font_row=5'b00100;default:overlay_font_row=5'b00100; endcase // T
                4'd11: case(row) 0:overlay_font_row=5'b11111;1:overlay_font_row=5'b00100;2:overlay_font_row=5'b00100;3:overlay_font_row=5'b00100;4:overlay_font_row=5'b00100;5:overlay_font_row=5'b00100;default:overlay_font_row=5'b11111; endcase // I
                4'd12: case(row) 0:overlay_font_row=5'b10001;1:overlay_font_row=5'b11011;2:overlay_font_row=5'b10101;3:overlay_font_row=5'b10101;4:overlay_font_row=5'b10001;5:overlay_font_row=5'b10001;default:overlay_font_row=5'b10001; endcase // M
                4'd13: case(row) 0:overlay_font_row=5'b11111;1:overlay_font_row=5'b10000;2:overlay_font_row=5'b10000;3:overlay_font_row=5'b11110;4:overlay_font_row=5'b10000;5:overlay_font_row=5'b10000;default:overlay_font_row=5'b11111; endcase // E
                4'd14: case(row) 2,5:overlay_font_row=5'b00100; default:overlay_font_row=5'b00000; endcase // :
                default: overlay_font_row = 5'b00000;
            endcase
        end
    end
endfunction

// 上电运行时间，格式为 TIME HH:MM:SS。
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        uptime_div  <= 25'd0;
        uptime_sec  <= 6'd0;
        uptime_min  <= 6'd0;
        uptime_hour <= 7'd0;
    end else if(uptime_div == 25'd24999999) begin
        uptime_div <= 25'd0;
        if(uptime_sec == 6'd59) begin
            uptime_sec <= 6'd0;
            if(uptime_min == 6'd59) begin
                uptime_min <= 6'd0;
                uptime_hour <= (uptime_hour == 7'd99) ? 7'd0 : uptime_hour + 1'b1;
            end else
                uptime_min <= uptime_min + 1'b1;
        end else
            uptime_sec <= uptime_sec + 1'b1;
    end else
        uptime_div <= uptime_div + 1'b1;
end

assign time_char_index = (osd_x - 11'd12) / 12;
assign time_font_col   = ((osd_x - 11'd12) % 12) >> 1;
assign time_font_row   = (osd_y - 10'd12) >> 1;
assign time_char_code  = (time_char_index == 4'd0)  ? 4'd10 :
                         (time_char_index == 4'd1)  ? 4'd11 :
                         (time_char_index == 4'd2)  ? 4'd12 :
                         (time_char_index == 4'd3)  ? 4'd13 :
                         (time_char_index == 4'd5)  ? (uptime_hour / 10) :
                         (time_char_index == 4'd6)  ? (uptime_hour % 10) :
                         (time_char_index == 4'd7)  ? 4'd14 :
                         (time_char_index == 4'd8)  ? (uptime_min / 10) :
                         (time_char_index == 4'd9)  ? (uptime_min % 10) :
                         (time_char_index == 4'd10) ? 4'd14 :
                         (time_char_index == 4'd11) ? (uptime_sec / 10) :
                         (time_char_index == 4'd12) ? (uptime_sec % 10) : 4'd15;
assign time_row_bits = overlay_font_row(time_char_code, time_font_row);
// 音乐模式下顶部留给歌词，不再显示上电计时。
assign time_panel_on = de && !music_mode_v1 &&
                       (osd_x >= 11'd8) && (osd_x < 11'd172) &&
                       (osd_y >= 10'd8) && (osd_y < 10'd32);
assign time_text_on  = de && !music_mode_v1 &&
                       (osd_x >= 11'd12) && (osd_x < 11'd168) &&
                       (osd_y >= 10'd12) && (osd_y < 10'd26) &&
                       (time_font_col < 3'd5) && time_row_bits[4-time_font_col];

assign notice_local_x = $signed({1'b0,osd_x}) - notice_scroll_x;
assign notice_row = osd_y - 10'd40;
assign uart_notice_rd_addr = ((notice_local_x >= 0) &&
                              (notice_local_x < $signed({3'b000,notice_width_video})) &&
                              (osd_y >= 10'd40) && (osd_y < 10'd56)) ?
                             ({6'd0,notice_row} << 6) + notice_local_x[9:3] : 10'd0;
assign notice_panel_on = de && notice_flags_video[0] && !notice_receiving_video &&
                         (notice_width_video != 10'd0) &&
                         (osd_y >= 10'd36) && (osd_y < 10'd60);
reg notice_text_gate_d;
reg [2:0] notice_bit_d;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        notice_text_gate_d <= 1'b0;
        notice_bit_d <= 3'd0;
    end else begin
        notice_text_gate_d <= notice_panel_on && (osd_y >= 10'd40) &&
                              (osd_y < 10'd56) && (notice_local_x >= 0) &&
                              (notice_local_x < $signed({3'b000,notice_width_video}));
        notice_bit_d <= 3'd7 - notice_local_x[2:0];
    end
end
assign notice_text_on = notice_text_gate_d && uart_notice_rd_data[notice_bit_d];
// Synchronize the UART setting, then apply it only at a frame boundary.
reg spectrum_v0, spectrum_v1, spectrum_visible;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        spectrum_v0 <= 1'b1;
        spectrum_v1 <= 1'b1;
        spectrum_visible <= 1'b1;
    end else begin
        spectrum_v0 <= uart_spectrum_enabled;
        spectrum_v1 <= spectrum_v0;
        if (vs_pos) spectrum_visible <= spectrum_v1;
    end
end
music_spectrum_visual u_music_spectrum_visual (
    .clk(video_clk), .rst(rst_all), .frame_start(vs_pos),
    .de(de), .x(osd_x), .y(osd_y),
    .background(video_base_data),
    .level(spectrum_visible ? fft_bar_level : 6'd0), .waveform_on(waveform_trace_on),
    .bar_addr(fft_bar_addr), .pixel(music_visual_pixel)
);


// 先围绕128调整对比度，再叠加转场及用户亮度；256表示100%。
assign brightness_product   = brightness * user_brightness;
assign effective_brightness = brightness_product[16:8];
assign r_contrast = apply_contrast(vout_data_raw[23:16], user_contrast);
assign g_contrast = apply_contrast(vout_data_raw[15:8],  user_contrast);
assign b_contrast = apply_contrast(vout_data_raw[7:0],   user_contrast);
assign r_scaled = r_contrast * effective_brightness;
assign g_scaled = g_contrast * effective_brightness;
assign b_scaled = b_contrast * effective_brightness;
assign vout_dim = {r_scaled[15:8], g_scaled[15:8], b_scaled[15:8]};

// ===================== 编辑界面左下角OSD：L0~L9 / S0~S9 =====================
// 5x7字模放大4倍；黑色底框位于640x480有效画面的左下角。
function [4:0] osd_font_row;
    input [3:0] symbol; // 0~9=数字，10=L，11=S
    input [2:0] row;
    begin
        case(symbol)
            4'd0: case(row) 0:osd_font_row=5'b01110;1:osd_font_row=5'b10001;2:osd_font_row=5'b10011;3:osd_font_row=5'b10101;4:osd_font_row=5'b11001;5:osd_font_row=5'b10001;default:osd_font_row=5'b01110; endcase
            4'd1: case(row) 0:osd_font_row=5'b00100;1:osd_font_row=5'b01100;2:osd_font_row=5'b00100;3:osd_font_row=5'b00100;4:osd_font_row=5'b00100;5:osd_font_row=5'b00100;default:osd_font_row=5'b01110; endcase
            4'd2: case(row) 0:osd_font_row=5'b01110;1:osd_font_row=5'b10001;2:osd_font_row=5'b00001;3:osd_font_row=5'b00010;4:osd_font_row=5'b00100;5:osd_font_row=5'b01000;default:osd_font_row=5'b11111; endcase
            4'd3: case(row) 0:osd_font_row=5'b11110;1:osd_font_row=5'b00001;2:osd_font_row=5'b00001;3:osd_font_row=5'b01110;4:osd_font_row=5'b00001;5:osd_font_row=5'b00001;default:osd_font_row=5'b11110; endcase
            4'd4: case(row) 0:osd_font_row=5'b00010;1:osd_font_row=5'b00110;2:osd_font_row=5'b01010;3:osd_font_row=5'b10010;4:osd_font_row=5'b11111;5:osd_font_row=5'b00010;default:osd_font_row=5'b00010; endcase
            4'd5: case(row) 0:osd_font_row=5'b11111;1:osd_font_row=5'b10000;2:osd_font_row=5'b10000;3:osd_font_row=5'b11110;4:osd_font_row=5'b00001;5:osd_font_row=5'b00001;default:osd_font_row=5'b11110; endcase
            4'd6: case(row) 0:osd_font_row=5'b01110;1:osd_font_row=5'b10000;2:osd_font_row=5'b10000;3:osd_font_row=5'b11110;4:osd_font_row=5'b10001;5:osd_font_row=5'b10001;default:osd_font_row=5'b01110; endcase
            4'd7: case(row) 0:osd_font_row=5'b11111;1:osd_font_row=5'b00001;2:osd_font_row=5'b00010;3:osd_font_row=5'b00100;4:osd_font_row=5'b01000;5:osd_font_row=5'b01000;default:osd_font_row=5'b01000; endcase
            4'd8: case(row) 0:osd_font_row=5'b01110;1:osd_font_row=5'b10001;2:osd_font_row=5'b10001;3:osd_font_row=5'b01110;4:osd_font_row=5'b10001;5:osd_font_row=5'b10001;default:osd_font_row=5'b01110; endcase
            4'd9: case(row) 0:osd_font_row=5'b01110;1:osd_font_row=5'b10001;2:osd_font_row=5'b10001;3:osd_font_row=5'b01111;4:osd_font_row=5'b00001;5:osd_font_row=5'b00001;default:osd_font_row=5'b01110; endcase
            4'd10: case(row) 0:osd_font_row=5'b10000;1:osd_font_row=5'b10000;2:osd_font_row=5'b10000;3:osd_font_row=5'b10000;4:osd_font_row=5'b10000;5:osd_font_row=5'b10000;default:osd_font_row=5'b11111; endcase
            default: case(row) 0:osd_font_row=5'b11111;1:osd_font_row=5'b10000;2:osd_font_row=5'b10000;3:osd_font_row=5'b01110;4:osd_font_row=5'b00001;5:osd_font_row=5'b00001;default:osd_font_row=5'b11110; endcase
        endcase
    end
endfunction

always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        osd_de_d      <= 1'b0;
        osd_line_seen <= 1'b0;
        osd_x         <= 11'd0;
        osd_y         <= 10'd0;
    end else begin
        osd_de_d <= de;
        if(vs_pos) begin
            osd_line_seen <= 1'b0;
            osd_x         <= 11'd0;
            osd_y         <= 10'd0;
        end else if(de) begin
            if(!osd_de_d) begin
                osd_x <= 11'd0;
                if(osd_line_seen)
                    osd_y <= osd_y + 1'b1;
                else
                    osd_line_seen <= 1'b1;
            end else begin
                osd_x <= osd_x + 1'b1;
            end
        end else begin
            osd_x <= 11'd0;
        end
    end
end

assign osd_box_on     = 1'b0;
assign osd_row        = (osd_y - 10'd444) >> 2;
assign osd_l_col      = (osd_x - 11'd20) >> 2;
assign osd_level_col  = (osd_x - 11'd44) >> 2;
assign osd_l_row_bits     = osd_font_row(edit_property_v1 ? 4'd11 : 4'd10, osd_row);
assign osd_level_row_bits = osd_font_row(edit_property_v1 ? contrast_level_v1 : brightness_level_v1, osd_row);
assign osd_l_on       = 1'b0;
assign osd_level_on   = 1'b0;
assign osd_text_on    = 1'b0;

// 数码管显示当前图片序号：无图显示 00，有图显示 01~16
// img_index 为 0-based，显示值 = img_index + 1；最大 16 只需判断是否 >= 10
assign disp_img_num = display_valid ? ({1'b0, img_index} + 5'd1) : 5'd0;
assign disp_tens    = (disp_img_num >= 5'd10) ? 4'd1 : 4'd0;
assign disp_units   = (disp_img_num >= 5'd10) ? (disp_img_num[3:0] - 4'd10) : disp_img_num[3:0];

// H3 音乐属性编辑时第 6 位显示播放状态：P=播放，S=暂停。
wire [6:0] seg_play = music_playing ? 7'b000_1100 : 7'b001_0010;

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        (music_edit_active ? {1'b1,7'b000_1001} :   // H
                        (image_geometry_edit ? {1'b1,seg_tens} :
                         (edit_active ? 8'hff : {1'b1,seg_mode_char}))),
    .seg_data_1        (music_edit_active ? {1'b1,7'b001_0010} :   // 5
                        (image_geometry_edit ? {~display_valid,seg_data_0} :
                         (edit_active ? 8'hff : {1'b1,seg_effect_char}))),
    .seg_data_2        (music_edit_active ? {1'b1,7'b011_1111} :
                        (edit_active ? 8'hff : {1'b1,7'b011_1111})),
    .seg_data_3        (music_edit_active ? {1'b1,seg_music_tens} :
                        (volume_edit_active && uart_volume_level == 4'd10 ? {1'b1,7'b111_1001} :
                        (edit_active ? 8'hff : {1'b1,seg_tens}))),
    .seg_data_4        (music_edit_active ? {1'b1,seg_music_units} :
                        (volume_edit_active ? {1'b1,seg_volume} :
                        (edit_active ? ((menu_item == 3'd4 || menu_item == 3'd5) ? 8'hff : {1'b1,seg_level}) :
                                       {~auto_mode,seg_data_0}))),
    .seg_data_5        (music_edit_active ? {1'b1,7'b011_1111} :
                        (edit_active ? 8'hff : {1'b1,7'b011_1111})),
    .seg_data_6        (music_edit_active ? {1'b1,seg_play} :
                        (edit_active ? {1'b1,7'b000_1001} :          // H
                         ((music_track_count != 5'd0) ? {1'b1,seg_music_tens} : 8'hff))),
    .seg_data_7        (music_edit_active ? 8'hff :
                        (edit_active ? {1'b1,(menu_item == 2'd0 ? 7'b111_1001 :
                                              menu_item == 2'd1 ? 7'b010_0100 :
                                              menu_item == 3'd2 ? 7'b011_0000 :
                                              menu_item == 3'd3 ? 7'b001_1001 :
                                              menu_item == 3'd4 ? 7'b001_0010 :
                                              7'b000_0010)} :
                         ((music_track_count != 5'd0) ? {1'b1,seg_music_units} : 8'hff)))
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前用纯色显示TF状态，便于上板直接定位黑屏阶段：
// 红=未找到图片，黄=扫描，紫=等待帧缓存，青=读取图片，蓝=扫描完成但未提交首帧。
assign picture_area_on = 1'b1;
assign video_base_data = (display_valid && picture_area_on) ? vout_dim :
                         (image_scan_done && (image_count == 5'd0)) ? 24'h80_0000 :
                         (image_scan_done) ? 24'h00_0080 :
                         (state_code == 4'd2) ? 24'h80_8000 :
                         (state_code == 4'd3) ? 24'h80_0080 :
                         (state_code == 4'd4) ? 24'h00_8080 : 24'h40_0000;

// 歌词条：顶部 512x16，水平居中 (x 64..575, y 2..17)，整条压暗提升可读性。
wire lyric_bar_on, lyric_text_on, title_bar_on, title_text_on;
wire [23:0] dim_music_pixel;
assign lyric_bar_on  = de && music_mode_v1 && lyric_valid && panel_lyric_v1 && (osd_y < 10'd20);
assign lyric_text_on = lyric_bar_on && (osd_y >= 10'd2) && (osd_y < 10'd18) &&
                       (osd_x >= 11'd64) && (osd_x < 11'd576) && lyric_pixel_on;
// 歌名：右侧竖排 16px 宽，y 112..367，16 个 16x16 字模。
// H3 属性面板出现时让出右侧区域。
assign title_bar_on  = de && music_mode_v1 && title_valid && panel_title_v1 && !panel_enable_v1 &&
                       (osd_x >= 11'd608) && (osd_x < 11'd640) &&
                       (osd_y >= 10'd112) && (osd_y < 10'd368);
assign title_text_on = title_bar_on && (osd_x >= 11'd616) && (osd_x < 11'd632) &&
                       title_pixel_on;

// H3 音乐属性面板：右侧整齐排列所有属性。
property_panel u_property_panel(
    .clk        (video_clk),
    .rst        (rst_all),
    .de         (de),
    .x          (osd_x),
    .y          (osd_y),
    .enable     (panel_enable_v1),
    .image_size_edit(panel_size_edit_v1),
    .image_size_mode(panel_size_v1),
    .image_aspect_edit(panel_aspect_edit_v1),
    .image_aspect_mode(panel_aspect_v1),
    .track_num  (panel_track_v1),
    .track_count(panel_tcount_v1),
    .image_num  (panel_image_v1),
    .image_count(panel_icount_v1),
    .playing    (panel_playing_v1),
    .lyric_enabled(panel_lyric_v1),
    .title_enabled(panel_title_v1),
    .effect     (panel_effect_v1),
    .brightness (brightness_level_v1),
    .contrast   (contrast_level_v1),
    .panel_on   (panel_on),
    .text_on    (panel_text_on)
);

assign dim_music_pixel = {2'b00,music_visual_pixel[23:18],
                          2'b00,music_visual_pixel[15:10],
                          2'b00,music_visual_pixel[7:2]};
assign overlay_base_data = (notice_panel_on || lyric_bar_on || title_bar_on ||
                            panel_on) ?
                           dim_music_pixel : music_visual_pixel;
// A photographed orange tint is ambiguous. Show one, two, or three wide black
// bars for missing HREF, FIFO overflow, or a short frame respectively.
wire [1:0] cam_orange_bar_count = !cam_debug_sync1[4] ? 2'd1 :
                                  cam_debug_sync1[3] ? 2'd2 :
                                  cam_debug_sync1[2] ? 2'd3 : 2'd0;
wire cam_orange_bar_pixel = cam_orange_bar_count != 0 &&
                            osd_y >= 10'd80 && osd_y < 10'd400 &&
                            ((osd_x >= 11'd80 && osd_x < 11'd130) ||
                             (cam_orange_bar_count >= 2 && osd_x >= 11'd190 && osd_x < 11'd240) ||
                             (cam_orange_bar_count >= 3 && osd_x >= 11'd300 && osd_x < 11'd350));
wire [1:0] cam_white_bar_count = !cam_write_req_seen ? 2'd1 :
                                !cam_sdram_ready_sync[1] ? 2'd2 : 2'd3;
wire cam_white_bar_pixel = osd_y >= 10'd80 && osd_y < 10'd400 &&
                           ((osd_x >= 11'd80 && osd_x < 11'd130) ||
                            (cam_white_bar_count >= 2 && osd_x >= 11'd190 && osd_x < 11'd240) ||
                            (cam_white_bar_count >= 3 && osd_x >= 11'd300 && osd_x < 11'd350));
// Cyan loading screen: 1..6 black bars identify the stalled startup stage.
reg [2:0] video_stage_meta, video_stage_sync;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin video_stage_meta<=0; video_stage_sync<=0; end
    else begin video_stage_meta<=video_startup_stage; video_stage_sync<=video_stage_meta; end
end
wire video_stage_bar = osd_y>=10'd100 && osd_y<10'd380 &&
    ((video_stage_sync>=1 && osd_x>=11'd60 && osd_x<11'd100) ||
     (video_stage_sync>=2 && osd_x>=11'd150 && osd_x<11'd190) ||
     (video_stage_sync>=3 && osd_x>=11'd240 && osd_x<11'd280) ||
     (video_stage_sync>=4 && osd_x>=11'd330 && osd_x<11'd370) ||
     (video_stage_sync>=5 && osd_x>=11'd420 && osd_x<11'd460) ||
     (video_stage_sync>=6 && osd_x>=11'd510 && osd_x<11'd550));
assign vout_data = camera_mode ?
                   (cam_cfg_error_sync[1] ? 24'hff_0000 :
                    !cam_cfg_done_sync[1] ? 24'h00_00ff :
                    !cam_pclk_seen ? 24'h00_ffff :
                    !cam_vsync_seen_sync[1] ? 24'hff_ff00 :
                    cam_display_valid_sync[1] ? vout_data_raw :
                    !cam_debug_sync1[5] ? (cam_white_bar_pixel ? 24'h00_0000 : 24'hff_ffff) :
                    cam_orange_bar_pixel ? 24'h00_0000 :
                    !cam_debug_sync1[4] ? 24'hff_8000 :
                    cam_debug_sync1[3] ? 24'hff_4000 :
                    cam_debug_sync1[2] ? 24'hff_a000 :
                    cam_debug_sync1[1] && !cam_debug_sync1[0] ? 24'h00_ff00 :
                    24'hff_00ff) :
                   panel_text_on ? 24'hff_ffff :
                   video_mode ? (panel_on ? 24'h20_2020 : display_valid ? vout_data_raw :
                                 video_status[2] ? 24'h80_0000 :
                                 !video_status[0] ? 24'h80_8000 :
                                 video_stage_bar ? 24'd0 : 24'h00_8080) :
                   lyric_text_on ? 24'hff_ffff :
                   title_text_on ? 24'hff_e080 :
                   osd_text_on  ? 24'hff_ffff :
                   osd_box_on   ? 24'h00_0000 :
                   notice_text_on ? 24'h40_ffff :
                   time_text_on ? 24'hff_e060 :
                   (music_mode_v1 ? overlay_base_data : video_base_data);

frame_read_write #(
    .CAMERA_INPUT     (CAMERA_PREVIEW || CAMERA_AVAILABLE),
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480),
    .OUTPUT_WIDTH     (640),
    .OUTPUT_HEIGHT    (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    // Until the camera has committed one frame, skip reads of uninitialized
    // SDRAM so the write FIFO gets the available memory bandwidth.
    .read_req          (video_read_req && (camera_mode ? cam_display_valid_sync[1] :
                                         video_mode ? display_valid : 1'b1)),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (21'd0),
    .read_addr_3       (21'd0),
    .read_addr_index   (camera_mode ? {1'b0,cam_display_bank_sync[1]} : disp_buf_idx_eff),
    .read_len          (FRAME_PIXELS),
    // Frame-latched slide descriptors; camera always uses a native frame.
    .slide_active      (!camera_mode && !video_mode && slide_active_eff),
    .slide_progress    (slide_progress_eff),
    .slide_old_index   (slide_old_buf_eff),
    .slide_new_index   (slide_new_buf_eff),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .camera_mode       (camera_mode),
    .camera_write_clk  (cam_pclk),
    .camera_write_en   (cam_write_en),
    .camera_write_data (cam_write_data),
    .camera_write_full (cam_write_full),
    .write_req         (camera_mode ? cam_write_req : sd_card_write_req),
    .write_v_flip      (camera_mode ? 1'b0 : frame_write_v_flip),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (21'd0),
    .write_addr_3      (21'd0),
    .write_addr_index  (camera_mode ? {1'b0,cam_write_bank} : write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_fifo_full   (sd_card_write_full)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：TF WAV，未找到时保留原测试音 =====================
pcm_frame_fifo u_pcm_frame_fifo(
    .wr_clk(sd_card_clk), .wr_rst(rst_all | music_fifo_rst_wr_pulse),
    .wr_en(audio_frame_valid), .wr_data(audio_frame_data),
    .wr_full(audio_fifo_full), .wr_count(audio_fifo_count),
    .rd_clk(audio_mclk), .rd_rst(rst_audio_stream | music_fifo_rst_rd_pulse),
    .rd_en(audio_fifo_rd_en), .rd_data(audio_fifo_rd_data),
    .rd_empty(audio_fifo_empty)
);

always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        wav_play_started <= 1'b0;
        music_fifo_rst_sd_seen <= 1'b0;
    end else if (music_fifo_rst_wr_pulse) begin
        wav_play_started <= 1'b0;
        music_fifo_rst_sd_seen <= music_fifo_reset_toggle;
    end
    else if (audio_fifo_count >= 13'd256)
        wav_play_started <= 1'b1;
end
always @(posedge audio_mclk or posedge rst_audio_stream) begin
    if (rst_audio_stream) begin
        wav_play_sync <= 2'b00;
        music_enable_audio <= 2'b00;
        music_fifo_rst_audio_sync <= 3'b000;
        audio_frame_tick_toggle <= 1'b0;
    end else begin
        wav_play_sync <= {wav_play_sync[0],wav_play_started};
        music_enable_audio <= {music_enable_audio[0],((music_mode || video_mode) && music_playing && (!video_mode || display_valid))};
        music_fifo_rst_audio_sync <= {music_fifo_rst_audio_sync[1:0],music_fifo_reset_toggle};
        if(audio_fifo_rd_en && !audio_fifo_empty && music_enable_audio[1])
            audio_frame_tick_toggle <= ~audio_frame_tick_toggle;
    end
end

pcm_i2s_tx u_pcm_i2s_tx(
    .volume_level(uart_volume_level), .volume_muted(uart_volume_muted),
    .mclk(audio_mclk), .rst(rst_audio_stream), .enable(wav_play_sync[1] && music_enable_audio[1] && !video_hold_audio[1]),
    .bclk(pcm_i2s_bclk), .lrck(pcm_i2s_lrck), .dout(pcm_i2s_dout),
    .fifo_rd_en(audio_fifo_rd_en), .fifo_rd_data(audio_fifo_rd_data),
    .fifo_empty(audio_fifo_empty)
);
assign audio_i2s_bclk = pcm_i2s_bclk;
assign audio_i2s_lrck = pcm_i2s_lrck;
assign audio_i2s_dout = (wav_play_sync[1] && music_enable_audio[1]) ? pcm_i2s_dout : 1'b0;

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule

// Build this top for the standalone OV2640 HDMI preview bitstream.
module top_camera_player(
    input clk, rst_n, key2, key3, key4,
    input uart_rx, output uart_tx,
    input voice_rx, output voice_tx,
    input cam_pclk, cam_vsync, cam_href,
    input [7:0] cam_data,
    output cam_scl, inout cam_sda, output cam_reset_n, cam_pwdn,
    output [7:0] seg_sel, seg_data,
    output HDMI_CLK_P, HDMI_D2_P, HDMI_D1_P, HDMI_D0_P,
    output HDMI_DDC_SCL, inout HDMI_DDC_SDA,
    output sd_ncs, sd_dclk, sd_mosi, input sd_miso
);
  top #(.CAMERA_AVAILABLE(1'b1)) u_core(
    .clk(clk), .rst_n(rst_n), .key2(key2), .key3(key3), .key4(key4),
    .uart_rx(uart_rx), .uart_tx(uart_tx),
    .voice_rx(voice_rx), .voice_tx(voice_tx),
    .gesture_rx(1'b1),
    .cam_pclk(cam_pclk), .cam_vsync(cam_vsync), .cam_href(cam_href),
    .cam_data(cam_data), .cam_scl(cam_scl), .cam_sda(cam_sda),
    .cam_reset_n(cam_reset_n), .cam_pwdn(cam_pwdn),
    .seg_sel(seg_sel), .seg_data(seg_data),
    .HDMI_CLK_P(HDMI_CLK_P), .HDMI_D2_P(HDMI_D2_P),
    .HDMI_D1_P(HDMI_D1_P), .HDMI_D0_P(HDMI_D0_P),
    .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA),
    .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi),
    .sd_miso(sd_miso)
  );
endmodule

// Video/image/music build with camera capture and camera FIFO removed.
module top_video_player(
    input clk, rst_n, key2, key3, key4,
    input uart_rx, output uart_tx,
    input voice_rx, output voice_tx,
    input gesture_rx,
    input cam_pclk, cam_vsync, cam_href,
    input [7:0] cam_data,
    output cam_scl, inout cam_sda, output cam_reset_n, cam_pwdn,
    output [7:0] seg_sel, seg_data,
    output HDMI_CLK_P, HDMI_D2_P, HDMI_D1_P, HDMI_D0_P,
    output HDMI_DDC_SCL, inout HDMI_DDC_SDA,
    output sd_ncs, sd_dclk, sd_mosi, input sd_miso
);
  top #(.CAMERA_AVAILABLE(1'b0)) u_core(
    .clk(clk), .rst_n(rst_n), .key2(key2), .key3(key3), .key4(key4),
    .uart_rx(uart_rx), .uart_tx(uart_tx),
    .voice_rx(voice_rx), .voice_tx(voice_tx),
    .gesture_rx(gesture_rx),
    .cam_pclk(cam_pclk), .cam_vsync(cam_vsync), .cam_href(cam_href),
    .cam_data(cam_data), .cam_scl(cam_scl), .cam_sda(cam_sda),
    .cam_reset_n(cam_reset_n), .cam_pwdn(cam_pwdn),
    .seg_sel(seg_sel), .seg_data(seg_data),
    .HDMI_CLK_P(HDMI_CLK_P), .HDMI_D2_P(HDMI_D2_P),
    .HDMI_D1_P(HDMI_D1_P), .HDMI_D0_P(HDMI_D0_P),
    .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA),
    .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi),
    .sd_miso(sd_miso)
  );
endmodule

// Build this top for the standalone OV2640 HDMI preview bitstream.
module top_camera_preview(
    input clk, rst_n, key2, key3, key4,
    input uart_rx, output uart_tx,
    input voice_rx, output voice_tx,
    input cam_pclk, cam_vsync, cam_href,
    input [7:0] cam_data,
    output cam_scl, inout cam_sda, output cam_reset_n, cam_pwdn,
    output [7:0] seg_sel, seg_data,
    output HDMI_CLK_P, HDMI_D2_P, HDMI_D1_P, HDMI_D0_P,
    output HDMI_DDC_SCL, inout HDMI_DDC_SDA,
    output sd_ncs, sd_dclk, sd_mosi, input sd_miso
);
  top #(.CAMERA_PREVIEW(1'b1)) u_core(
    .clk(clk), .rst_n(rst_n), .key2(key2), .key3(key3), .key4(key4),
    .uart_rx(uart_rx), .uart_tx(uart_tx),
    .voice_rx(voice_rx), .voice_tx(voice_tx),
    .gesture_rx(1'b1),
    .cam_pclk(cam_pclk), .cam_vsync(cam_vsync), .cam_href(cam_href),
    .cam_data(cam_data), .cam_scl(cam_scl), .cam_sda(cam_sda),
    .cam_reset_n(cam_reset_n), .cam_pwdn(cam_pwdn),
    .seg_sel(seg_sel), .seg_data(seg_data),
    .HDMI_CLK_P(HDMI_CLK_P), .HDMI_D2_P(HDMI_D2_P),
    .HDMI_D1_P(HDMI_D1_P), .HDMI_D0_P(HDMI_D0_P),
    .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA),
    .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
  );
endmodule

// Diagnostic top: boot straight into H3, play only the first MVI, suppress
// WAV traffic/OSD, and use the conservative 12.5 MHz TF SPI timing.
module top_mv_only_test(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key2,
    input  wire       key3,
    input  wire       key4,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [7:0] seg_sel,
    output wire [7:0] seg_data,
    output wire       HDMI_CLK_P,
    output wire       HDMI_D2_P,
    output wire       HDMI_D1_P,
    output wire       HDMI_D0_P,
    output wire       HDMI_DDC_SCL,
    inout  wire       HDMI_DDC_SDA,
    output wire       sd_ncs,
    output wire       sd_dclk,
    output wire       sd_mosi,
    input  wire       sd_miso
);

top #(.MV_ONLY_TEST(1'b1)) u_mv_only (
    .clk(clk), .rst_n(rst_n),
    .key2(key2), .key3(key3), .key4(key4),
    .uart_rx(uart_rx), .uart_tx(uart_tx), .voice_rx(1'b1), .voice_tx(),
    .seg_sel(seg_sel), .seg_data(seg_data),
    .HDMI_CLK_P(HDMI_CLK_P), .HDMI_D2_P(HDMI_D2_P),
    .HDMI_D1_P(HDMI_D1_P), .HDMI_D0_P(HDMI_D0_P),
    .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA),
    .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
);

endmodule

// 低有效按键：释放前达到LONG_PRESS_MS只产生long_pulse，否则释放时产生short_pulse。
// Active-low press event; held buttons never auto-repeat.
module player_button_debounce #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input wire I_clk, I_rst_n, I_key_in,
    output reg O_key_trig_out,
    output wire O_key_pressed
);
    localparam integer RAW_CYCLES = CLK_FREQ_HZ / 1000 * DEBOUNCE_MS;
    localparam integer FILTER_CYCLES = RAW_CYCLES > 0 ? RAW_CYCLES : 1;
    localparam integer COUNTER_BITS = FILTER_CYCLES > 1 ? $clog2(FILTER_CYCLES) : 1;
    reg sync0, sync1, stable_key;
    reg [COUNTER_BITS-1:0] count;
    assign O_key_pressed = !stable_key;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sync0 <= 1'b1;
            sync1 <= 1'b1;
            stable_key <= 1'b1;
            count <= 0;
            O_key_trig_out <= 1'b0;
        end else begin
            sync0 <= I_key_in;
            sync1 <= sync0;
            O_key_trig_out <= 1'b0;
            if (sync1 == stable_key)
                count <= 0;
            else if (count == FILTER_CYCLES - 1) begin
                stable_key <= sync1;
                count <= 0;
                O_key_trig_out <= !sync1;
            end else
                count <= count + 1'b1;
        end
    end
endmodule

// Exactly one UI state owns each key. KEY4 has priority; KEY2+KEY3 chords
// are ignored. Remote settings may override the same parameter but cannot
// consume a local menu/pause event.
module player_key_control(
    input wire clk, rst_n,
    input wire key2_pulse, key3_pulse, key4_short, key4_long,
    input wire key2_held, key3_held, key4_held,
    input wire remote_brightness, remote_contrast, remote_effect,
    input wire remote_playing, remote_playing_value,
    input wire [3:0] remote_brightness_value, remote_contrast_value,
    input wire [1:0] remote_effect_value,
    output wire edit_active, music_edit_active, volume_edit_active,
    output reg [2:0] menu_item,
    output reg [3:0] brightness_level, contrast_level,
    output reg [1:0] transition_effect,
    output reg music_playing, music_prev_toggle, music_next_toggle,
    output reg next_background_pulse,
    output reg image_size_step,
    output reg image_aspect_step,
    output reg key_volume_up, key_volume_down
);
    localparam [1:0] HOME=2'd0, MENU=2'd1, MUSIC_EDIT=2'd2, VOLUME_EDIT=2'd3;
    reg [1:0] state;
    wire key2_action = key2_pulse && !key3_pulse && !key3_held;
    wire key3_action = key3_pulse && !key2_pulse && !key2_held;
    assign edit_active = (state != HOME);
    assign music_edit_active = (state == MUSIC_EDIT);
    assign volume_edit_active = (state == VOLUME_EDIT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= HOME;
            menu_item <= 3'd0;
            brightness_level <= 4'd9;
            contrast_level <= 4'd5;
            transition_effect <= 2'd0;
            music_playing <= 1'b1;
            music_prev_toggle <= 1'b0;
            music_next_toggle <= 1'b0;
            next_background_pulse <= 1'b0;
            image_size_step <= 1'b0;
            image_aspect_step <= 1'b0;
            key_volume_up <= 1'b0;
            key_volume_down <= 1'b0;
        end else begin
            next_background_pulse <= 1'b0;
            image_size_step <= 1'b0;
            image_aspect_step <= 1'b0;
            key_volume_up <= 1'b0;
            key_volume_down <= 1'b0;
            if (key4_long) begin
                state <= (state == HOME) ? MENU : HOME;
                menu_item <= 3'd0;
            end else if (key4_short) begin
                if (state == MENU)
                    state <= (menu_item == 3'd4) ? MUSIC_EDIT :
                             (menu_item == 3'd5) ? VOLUME_EDIT : HOME;
                else if (state == VOLUME_EDIT)
                    state <= MENU;
                else
                    music_playing <= ~music_playing;
            end else begin
                case (state)
                    HOME: begin
                        if (key2_action)
                            transition_effect <= (transition_effect >= 2'd2) ?
                                                 2'd0 : transition_effect + 1'b1;
                        else if (key3_action)
                            next_background_pulse <= 1'b1;
                    end
                    MENU: begin
                        if (key2_action) begin
                            menu_item <= (menu_item >= 3'd5) ? 3'd0 : menu_item + 1'b1;
                        end else if (key3_action) begin
                            if (menu_item == 2'd0)
                                brightness_level <= (brightness_level >= 4'd9) ? 4'd0 : brightness_level + 1'b1;
                            else if (menu_item == 2'd1)
                                contrast_level <= (contrast_level >= 4'd9) ? 4'd0 : contrast_level + 1'b1;
                            else if (menu_item == 2'd2)
                                image_size_step <= 1'b1;
                            else if (menu_item == 3'd3)
                                image_aspect_step <= 1'b1;
                        end
                    end
                    MUSIC_EDIT: begin
                        if (key2_action)
                            music_prev_toggle <= ~music_prev_toggle;
                        else if (key3_action)
                            music_next_toggle <= ~music_next_toggle;
                    end
                    VOLUME_EDIT: begin
                        if (key2_action) key_volume_down <= 1'b1;
                        else if (key3_action) key_volume_up <= 1'b1;
                    end
                    default: begin
                        state <= HOME;
                        menu_item <= 3'd0;
                    end
                endcase
            end
            if (remote_brightness && remote_brightness_value <= 4'd9)
                brightness_level <= remote_brightness_value;
            if (remote_contrast && remote_contrast_value <= 4'd9)
                contrast_level <= remote_contrast_value;
            if (remote_effect && remote_effect_value <= 2'd2)
                transition_effect <= remote_effect_value;
            if (remote_playing)
                music_playing <= remote_playing_value;
        end
    end
endmodule

module key_short_long #(
    parameter integer CLK_FREQ_HZ   = 50_000_000,
    parameter integer DEBOUNCE_MS   = 20,
    parameter integer LONG_PRESS_MS = 2000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  short_pulse,
    output reg  long_pulse,
    output wire pressed
);

localparam integer RAW_DEBOUNCE = CLK_FREQ_HZ / 1000 * DEBOUNCE_MS;
localparam integer RAW_LONG = CLK_FREQ_HZ / 1000 * LONG_PRESS_MS;
localparam integer DEBOUNCE_COUNT = RAW_DEBOUNCE > 0 ? RAW_DEBOUNCE : 1;
localparam integer LONG_COUNT = RAW_LONG > 0 ? RAW_LONG : 1;
localparam integer DEBOUNCE_BITS = DEBOUNCE_COUNT > 1 ? $clog2(DEBOUNCE_COUNT) : 1;
localparam integer LONG_BITS = LONG_COUNT > 1 ? $clog2(LONG_COUNT) : 1;

reg sync0, sync1;
reg stable_key;
reg [DEBOUNCE_BITS-1:0] debounce_cnt;
reg [LONG_BITS-1:0] hold_cnt;
reg long_sent;
assign pressed = !stable_key;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sync0       <= 1'b1;
        sync1       <= 1'b1;
        stable_key  <= 1'b1;
        debounce_cnt<= 32'd0;
        hold_cnt    <= 32'd0;
        long_sent   <= 1'b0;
        short_pulse <= 1'b0;
        long_pulse  <= 1'b0;
    end else begin
        sync0       <= key_n;
        sync1       <= sync0;
        short_pulse <= 1'b0;
        long_pulse  <= 1'b0;

        if(sync1 != stable_key) begin
            if(debounce_cnt >= DEBOUNCE_COUNT - 1) begin
                stable_key   <= sync1;
                debounce_cnt <= 32'd0;
                if(sync1 == 1'b0) begin
                    hold_cnt  <= 32'd0;
                    long_sent <= 1'b0;
                end else begin
                    if(!long_sent)
                        short_pulse <= 1'b1;
                    hold_cnt <= 32'd0;
                end
            end else begin
                debounce_cnt <= debounce_cnt + 1'b1;
            end
        end else begin
            debounce_cnt <= 32'd0;
            if(stable_key == 1'b0 && !long_sent) begin
                if(hold_cnt >= LONG_COUNT - 1) begin
                    long_pulse <= 1'b1;
                    long_sent  <= 1'b1;
                end else begin
                    hold_cnt <= hold_cnt + 1'b1;
                end
            end
        end
    end
end

endmodule

// Frame prefetch handshake is the only point at which a descriptor changes.
module image_transition_control (
    input wire clk, rst, read_req,
    input wire [1:0] committed_bank,
    input wire display_valid,
    input wire [1:0] effect,
    input wire geometry_edit,
    output reg [1:0] read_bank, old_bank, new_bank, released_bank,
    output wire slide_active,
    output reg [9:0] slide_progress,
    output reg [8:0] brightness
);
    localparam IDLE=2'd0, FADE_OUT=2'd1, FADE_IN=2'd2, SLIDE=2'd3;
    reg [1:0] state;
    reg req_d, valid_meta, valid_sync;
    reg [1:0] effect_meta, effect_sync;
    assign slide_active = (state == SLIDE);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            req_d<=0; valid_meta<=0; valid_sync<=0;
            effect_meta<=0; effect_sync<=0;
            state<=IDLE; read_bank<=0; old_bank<=0; new_bank<=0;
            released_bank<=0; slide_progress<=0; brightness<=256;
        end else begin
            req_d<=read_req;
            valid_meta<=display_valid; valid_sync<=valid_meta;
            effect_meta<=effect; effect_sync<=effect_meta;
            if (read_req && !req_d) begin
                if (geometry_edit) begin
                    state<=IDLE; read_bank<=committed_bank;
                    released_bank<=committed_bank;
                    slide_progress<=0; brightness<=256;
                end else case (state)
                    IDLE: begin
                        brightness<=256;
                        if (valid_sync && committed_bank != released_bank) begin
                            old_bank<=read_bank; new_bank<=committed_bank;
                            case (effect_sync)
                                1: begin state<=FADE_OUT; brightness<=240; end
                                2: begin state<=SLIDE; slide_progress<=32; end
                                default: begin
                                    read_bank<=committed_bank;
                                    released_bank<=committed_bank;
                                end
                            endcase
                        end
                    end
                    FADE_OUT: begin
                        if (brightness<=16) begin
                            brightness<=0; read_bank<=new_bank; state<=FADE_IN;
                        end else brightness<=brightness-9'd16;
                    end
                    FADE_IN: begin
                        if (brightness>=240) begin
                            brightness<=256; state<=IDLE; released_bank<=new_bank;
                        end else brightness<=brightness+9'd16;
                    end
                    SLIDE: begin
                        if (slide_progress>=608) begin
                            slide_progress<=640; read_bank<=new_bank;
                            state<=IDLE; released_bank<=new_bank;
                        end else slide_progress<=slide_progress+10'd32;
                    end
                    default: begin state<=IDLE; brightness<=256; end
                endcase
            end
        end
    end
endmodule
