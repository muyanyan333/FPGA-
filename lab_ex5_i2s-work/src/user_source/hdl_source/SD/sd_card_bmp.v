
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [4:0]   SCAN_TARGET_COUNT = 5'd12,
    parameter         FAST_DIV0         = 1,
    parameter         USE_KEY_NEXT_EVENT = 0,
    parameter         WAIT_DISPLAY_RELEASE = 0,
    parameter integer VIDEO_EOF_STALL_CYCLES = CLK_FREQ_HZ
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_next_event, // pre-debounced, same clk domain
    input [1:0]                 display_released_bank,
    input                       image_size_step,
    input                       image_size_edit,
    output [1:0]                current_image_size,
    input                       image_aspect_step,
    input                       remote_size_set,
    input [1:0]                 remote_size_value,
    input                       remote_aspect_set,
    input [1:0]                 remote_aspect_value,
    output [1:0]                current_image_aspect,
    input                       key_mode,        // 兼容旧测试平台的低有效原始按键
    input                       key_mode_toggle, // KEY4短按事件toggle，来自50MHz域
    input                       edit_active,     // 属性编辑时屏蔽KEY3切图
    input                       remote_select_valid,
    input  [3:0]               remote_select_index, // 0-based
    input                       remote_auto,
    input                       remote_manual,
    input                       remote_next,
    input                       remote_prev,
    input                       music_mode,
    input                       video_mode,
    output [2:0]                video_status,
    output [2:0]                video_startup_stage,
    output                      video_playback_done,
    output                      video_audio_hold,
    input                       music_prev_toggle,
    input                       music_next_toggle,
    input                       remote_music_prev,
    input                       remote_music_next,
    input                       remote_music_select,
    input [3:0]                 remote_music_index,
    input                       audio_frame_tick_toggle,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output                      display_valid,

    input                       write_finish_toggle,
    output [1:0]                write_buf_idx,
    output [1:0]                disp_buf_idx,
    output [3:0]                img_index,      // 当前正在显示的图片序号(0-based,与 img_idx 一致)
    output                      auto_mode,      // 1=自动轮播模式, 0=手动模式
    output [4:0]                image_count,
    output                      scan_complete,
    input  [12:0]               audio_fifo_count,
    input                       audio_fifo_full,
    output                      audio_frame_valid,
    output [31:0]               audio_frame_data,
    output                      wav_stream_valid,
    output [3:0]                music_track_index,
    output [4:0]                music_track_count,
    output [4:0]                music_track_number,
    output [15:0]               music_track_map,
    output reg                  music_fifo_reset_toggle,

    // Lyric strip / title column pixel lookup (video_clk domain).
    input                       video_clk,
    input  [10:0]               pixel_x,
    input  [9:0]                pixel_y,
    output                      lyric_pixel_on,
    output                      title_pixel_on,
    output                      lyric_valid,
    output                      title_valid,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      frame_write_v_flip,
    input                       write_full,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);



wire key_next_press;
wire background_next = USE_KEY_NEXT_EVENT ? key_next_event : key_next_press;
wire key_mode_press;
wire key_mode_raw_press;
wire key_mode_toggle_press;
reg [2:0] key_mode_tgl_sync;
reg [1:0] edit_active_sync;
reg [1:0] music_mode_sync;
wire      music_mode_sd = music_mode_sync[1];
reg [1:0] write_ack_sync;
wire      write_req_ack_sd = write_ack_sync[1];

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_sd_read;
wire [31:0]      bmp_sd_addr;
wire             wav_sd_read;
wire [31:0]      wav_sd_addr;
wire             wav_found;
wire [31:0]      wav_lba, wav_cluster, wav_file_bytes;
wire             wav_no_fat_chain;
wire [31:0]      fs_volume_lba, fs_fat_offset, fs_heap_offset;
wire [7:0]       fs_spc_shift;
wire             wav_error;
wire             wav_item_valid, wav_item_no_fat_chain, wav_eof;
wire [31:0]      wav_item_lba, wav_item_cluster, wav_item_file_bytes;
wire [4:0]       wav_item_track_id;
wire             lyr_item_valid, lyr_item_no_fat_chain;
wire [31:0]      lyr_item_lba, lyr_item_cluster, lyr_item_file_bytes;
wire [7:0]       lyr_item_track_id;
// Per-track metadata, indexed by the numeric filename prefix (02 -> index 1).
// Both WAV and LYR tables use the same index, so pairing is exact and no
// longer depends on the exFAT discovery order.
// One simple dual-port block RAM stores WAV and lyric metadata together.
// One port writes during discovery; the other alternates the two lookups.
// Playback starts only after discovery and the registered reads settle.
(* ram_style = "block" *) reg [64:0] music_meta_ram [0:31]; /* fehdl force_ram=1, ram_style="bram" */
reg [64:0] music_wav_meta, music_lyr_meta;
reg              wav_track_valid [0:15];
reg              lyr_track_valid [0:15];
reg [3:0]        wav_index;
wire [64:0]      selected_wav_meta = video_mode ? video_audio_meta : music_wav_meta;
wire [64:0]      selected_lyr_meta = music_lyr_meta;
wire [31:0]      selected_wav_cluster = selected_wav_meta[31:0];
reg [4:0]        wav_count;
reg [4:0]        lyr_count;
reg              tracks_initialized;
reg              scan_done_d;
reg [3:0]        first_valid_index;
reg              wav_start_pulse, wav_restart, wav_restart_pending;
reg              wav_start_pending, wav_started;
reg              wav_eof_pending;
reg [13:0]       eof_drain_guard;
localparam [13:0] EOF_DRAIN_CYCLES = CLK_FREQ_HZ / 12000;
reg              lyr_start_pulse, lyr_restart;
reg              lyr_start_pending, lyr_started;
reg [2:0]        music_prev_sync, music_next_sync;
reg [2:0]        audio_tick_sync;
wire             audio_frame_tick = audio_tick_sync[2] ^ audio_tick_sync[1];
wire             music_prev_press = music_prev_sync[2] ^ music_prev_sync[1];
wire             music_next_press = music_next_sync[2] ^ music_next_sync[1];
wire             lyr_sd_read;
wire [31:0]      lyr_sd_addr;
wire             lyr_pixel_on_w, lyr_title_pixel_on_w;
wire             lyr_frame_valid_w, lyr_title_valid_w;
wire             lyr_error_unused;
wire             bmp_write_req;
wire             lyric_catalog_ok = wav_track_valid[wav_index] &&
                                   lyr_track_valid[wav_index];
// EOF marks the last SD read, not the last audible sample.  Drain buffered
// PCM first, then allow four more samples for the I2S prefetch pipeline.
wire             advance_after_eof = wav_eof_pending &&
                                    (audio_fifo_count == 13'd0) &&
                                    (eof_drain_guard == EOF_DRAIN_CYCLES);
reg [2:0]       sd_owner;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             bmp_load_begin, scale_go, scale_ready;
wire [15:0]      bmp_src_width, bmp_src_height;
wire             scale_write_en, scale_done, scale_overflow;
wire [23:0]      scale_write_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [4:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_mode_r;
reg [31:0]       auto_cnt;
reg [4:0]        img_found_count;
reg [3:0]        img_idx;              // 当前真正显示中的图片编号
reg [3:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector [0:15];
reg [1:0]        image_size_table [0:15];
reg [1:0]        image_aspect_table [0:15];
reg [1:0]        load_image_size;
reg [1:0]        load_image_aspect;
wire size_change = image_display_valid && scan_done &&
                   ((image_size_edit && image_size_step) ||
                    (remote_size_set && remote_size_value <= 2'd2 && remote_size_value != current_image_size));
wire aspect_change = image_display_valid && scan_done &&
                     ((image_size_edit && image_aspect_step) ||
                      (remote_aspect_set && remote_aspect_value != current_image_aspect));
wire geometry_change = size_change || aspect_change;
reg              target_req_pending;
reg target_req_auto, load_is_auto;
reg [3:0]        target_req_idx;
reg              load_busy;
reg              music_mode_d;

// bmp_ready 先表示"源文件读取/送 FIFO 完成"；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [31:0] auto_limit = music_mode_sd ? (CLK_FREQ_HZ * 10 - 1)
                                       : (CLK_FREQ_HZ - 1);
wire [3:0] next_from_current;

integer i;
integer ti;

wire metadata_wav_write = wav_item_valid && wav_item_track_id>=1 && wav_item_track_id<=16;
wire metadata_lyr_write = lyr_item_valid && lyr_item_track_id>=1 && lyr_item_track_id<=16;
wire metadata_write = !rst && (metadata_wav_write || metadata_lyr_write);
wire [3:0] metadata_wav_index = wav_item_track_id[3:0]-4'd1;
wire [3:0] metadata_lyr_index = lyr_item_track_id[3:0]-4'd1;
wire [4:0] metadata_write_address = metadata_wav_write ? {1'b0,metadata_wav_index} : {1'b1,metadata_lyr_index};
// A single synchronous read port alternates WAV/lyric lookups. This maps
// to four 18-bit simple-dual-port BRAMs instead of eight true-dual-port BRAMs.
reg metadata_phase, metadata_phase_d;
reg [64:0] metadata_read_data;
reg [3:0] metadata_index_seen;
reg [2:0] metadata_settle;
wire metadata_ready = metadata_settle>=3'd6;
always @(posedge clk) begin
    if (metadata_write)
        music_meta_ram[metadata_write_address] <= metadata_wav_write ?
            {wav_item_no_fat_chain,wav_item_file_bytes,wav_item_cluster} :
            {lyr_item_no_fat_chain,lyr_item_file_bytes,lyr_item_lba};
    metadata_read_data <= music_meta_ram[{metadata_phase,wav_index}];
end
always @(posedge clk or posedge rst) begin
    if (rst) begin
        metadata_phase<=0; metadata_phase_d<=0;
        music_wav_meta<=0; music_lyr_meta<=0;
        metadata_settle<=0; metadata_index_seen<=0;
    end else begin
        metadata_phase<=~metadata_phase; metadata_phase_d<=metadata_phase;
        if (metadata_phase_d) music_lyr_meta<=metadata_read_data;
        else music_wav_meta<=metadata_read_data;
        if (!scan_done || metadata_index_seen!=wav_index) begin
            metadata_index_seen<=wav_index; metadata_settle<=0;
        end else if (metadata_settle!=7) metadata_settle<=metadata_settle+1'b1;
    end
end

assign video_status = video_mode ? {video_error || video_tail_stalled || (scan_done && (!video_found || !video_audio_found)) || (video_started && wav_error), video_active, video_found && video_audio_found} : 3'd0;
reg image_display_valid;
reg [1:0] image_write_buf_idx, image_disp_buf_idx;
reg video_found, video_audio_found, video_started, video_start;
reg [31:0] video_lba, video_cluster, video_bytes;
reg video_contiguous;
reg video_rgb332, video_indexed, video_dynamic;
reg [64:0] video_audio_meta;
wire mvi_item_valid, mvi_item_no_fat_chain;
wire mvi_item_rgb332, mvi_item_indexed, mvi_item_dynamic;
wire [31:0] mvi_item_lba, mvi_item_cluster, mvi_item_file_bytes;
wire video_frame_present;
// Fill/commit the first video frame before prefetching its soundtrack.
// Audio consumption is gated by display_valid at the top level; keeping
// startup sequential also avoids filling that paused FIFO on the shared SD bus.
wire video_audio_start = video_frame_present && !video_display_valid;
wire video_frame_start, video_scale_go, video_write_req, video_pixel_valid;
wire [23:0] video_pixel_data;
wire video_sd_read, video_active, video_error;
wire video_pacing_wait;
assign video_audio_hold=video_mode && video_display_valid && video_pacing_wait;
wire [31:0] video_sd_addr;
reg [1:0] video_write_bank, video_display_bank;
reg video_display_valid;
assign display_valid = video_mode ? video_display_valid : image_display_valid;
assign write_buf_idx = video_mode ? video_write_bank : image_write_buf_idx;
assign disp_buf_idx = video_mode ? video_display_bank : image_disp_buf_idx;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        video_found<=0; video_audio_found<=0; video_started<=0; video_start<=0;
        video_lba<=0; video_cluster<=0; video_bytes<=0; video_contiguous<=0; video_rgb332<=0; video_indexed<=0;video_dynamic<=0;
        video_audio_meta<=0;
        video_write_bank<=0; video_display_bank<=0; video_display_valid<=0;
    end else begin
        video_start<=0;
        if (mvi_item_valid && !video_found) begin
            video_found<=1; video_lba<=mvi_item_lba;
            video_cluster<=mvi_item_cluster; video_bytes<=mvi_item_file_bytes;
            video_contiguous<=mvi_item_no_fat_chain;
            video_rgb332<=mvi_item_rgb332;
            video_indexed<=mvi_item_indexed;video_dynamic<=mvi_item_dynamic;
        end
        // Reserved 00.wav is exclusively the video's soundtrack, not a song.
        if (wav_item_valid && wav_item_track_id==5'd17 && !video_audio_found) begin
            video_audio_found<=1;
            video_audio_meta<={wav_item_no_fat_chain,wav_item_file_bytes,wav_item_cluster};
        end
        if (video_mode && scan_done && video_found && video_audio_found && !video_started) begin
            video_start<=1; video_started<=1;
        end
        if (video_frame_start)
            video_write_bank<=video_display_valid ? (video_display_bank ^ 2'd1) : 2'd0;
        if (video_mode && video_frame_present) begin
            video_display_bank<=video_write_bank; video_display_valid<=1;
        end
    end
end
exfat_raw_video_reader video_reader (
    .clk(clk), .rst(rst), .start(video_start), .restart(1'b0), .enable(video_mode),
    .rgb332_mode(video_rgb332),.indexed_mode(video_indexed),.dynamic_mode(video_dynamic),.audio_finished(video_audio_finished),
    .first_lba(video_lba), .first_cluster(video_cluster), .file_bytes(video_bytes),
    .no_fat_chain(video_contiguous), .volume_lba(fs_volume_lba),
    .fat_offset(fs_fat_offset), .heap_offset(fs_heap_offset), .spc_shift(fs_spc_shift),
    .pcm_frame_tick(audio_frame_tick), .write_req_ack(write_req_ack_sd),
    .allow_frame(!WAIT_DISPLAY_RELEASE || !video_display_valid || display_released_bank==video_display_bank),
    .scale_ready(scale_ready), .scale_done(scale_done), .frame_committed(write_finish_pulse),
    .frame_present(video_frame_present), .frame_start(video_frame_start), .scale_go(video_scale_go), .write_req(video_write_req),
    .pixel_valid(video_pixel_valid), .pixel_data(video_pixel_data),
    .sd_sec_read(video_sd_read), .sd_sec_read_addr(video_sd_addr),
    .sd_data(sd_sec_read_data), .sd_data_valid(sd_sec_read_data_valid && sd_owner==3'd4),
    .sd_read_end(sd_sec_read_end && sd_owner==3'd4), .active(video_active), .video_error(video_error), .pacing_wait(video_pacing_wait),
    .startup_stage(video_startup_stage)
);
// Video owns its EOF latch; music track scheduling cannot clear it.
reg video_audio_eof_seen;
reg [13:0] video_drain_guard;
always @(posedge clk or posedge rst) begin
    if(rst) begin video_audio_eof_seen<=0;video_drain_guard<=0;end
    else begin
        if(video_audio_start) video_audio_eof_seen<=0;
        else if(video_mode && wav_eof) video_audio_eof_seen<=1;
        if(video_mode && video_display_valid && video_audio_eof_seen && audio_fifo_count==0) begin
            if(video_drain_guard<EOF_DRAIN_CYCLES) video_drain_guard<=video_drain_guard+1'b1;
        end else video_drain_guard<=0;
    end
end
wire video_audio_finished=video_audio_eof_seen && video_drain_guard==EOF_DRAIN_CYCLES;
// A missing final SDRAM commit can hold PCM before its FIFO drains. Only
// after WAV EOF, bound that circular wait; real transfer/render progress
// restarts the timer. A stalled tail exits through the normal mode reset
// and never publishes an incomplete frame. A user pause alone is not hold.
localparam integer VIDEO_EOF_STALL_WIDTH = VIDEO_EOF_STALL_CYCLES > 1 ?
    $clog2(VIDEO_EOF_STALL_CYCLES) : 1;
reg [VIDEO_EOF_STALL_WIDTH-1:0] video_tail_idle_count;
reg video_tail_stalled;
wire video_tail_progress = video_frame_present || write_finish_pulse ||
    scale_write_en || (sd_sec_read_data_valid && sd_owner==3'd4);
always @(posedge clk or posedge rst) begin
    if(rst) begin video_tail_idle_count<=0;video_tail_stalled<=0;end
    else if(!video_mode || video_audio_start) begin
        video_tail_idle_count<=0;video_tail_stalled<=0;
    end else if(!video_audio_eof_seen || !video_audio_hold || video_tail_progress)
        video_tail_idle_count<=0;
    else if(!video_tail_stalled) begin
        if(video_tail_idle_count==VIDEO_EOF_STALL_CYCLES-1)
            video_tail_stalled<=1;
        else video_tail_idle_count<=video_tail_idle_count+1'b1;
    end
end
// The soundtrack is padded/cropped to the movie's exact duration. Once
// its last sample drains, return even if a final video commit is stuck.
// The mode controller resets both pipelines, so no new sector is reused.
assign video_playback_done=video_mode && (video_audio_finished || video_tail_stalled);

assign write_en   = scale_write_en;
assign write_data = {scale_write_data, 8'b0};
assign write_req = video_mode ? video_write_req : bmp_write_req;
assign frame_write_v_flip = 1'b1;
assign auto_tick  = (auto_cnt == auto_limit);
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign img_index = img_idx;
assign current_image_size = image_display_valid ? image_size_table[img_idx] : 2'd0;
assign current_image_aspect = image_display_valid ? image_aspect_table[img_idx] : 2'd0;
assign auto_mode = auto_mode_r;
assign image_count = img_found_count;
assign scan_complete = scan_done;
assign music_track_index = wav_index;
assign music_track_count = wav_count;
// Track number is the numeric filename prefix (02.wav -> 2), so the 7-seg,
// the H3 panel and the LYR2 header all agree.
assign music_track_number = (wav_count != 5'd0) ?
                            ({1'b0, wav_index} + 5'd1) : 5'd0;
genvar track_bit;
generate for (track_bit = 0; track_bit < 16; track_bit = track_bit + 1) begin: g_track_map
    assign music_track_map[track_bit] = wav_track_valid[track_bit];
end endgenerate
assign lyric_pixel_on = lyr_pixel_on_w;
assign title_pixel_on = lyr_title_pixel_on_w;
assign lyric_valid = lyr_frame_valid_w;
assign title_valid = lyr_title_valid_w;
assign key_mode_toggle_press = key_mode_tgl_sync[2] ^ key_mode_tgl_sync[1];
assign key_mode_press = key_mode_raw_press | key_mode_toggle_press;
assign sd_sec_read = (sd_owner == 2'd1) ? bmp_sd_read :
                     (sd_owner == 2'd2) ? wav_sd_read :
                     (sd_owner == 2'd3) ? lyr_sd_read :
                     (sd_owner == 3'd4) ? video_sd_read : 1'b0;
assign sd_sec_read_addr = (sd_owner == 2'd1) ? bmp_sd_addr :
                          (sd_owner == 2'd2) ? wav_sd_addr :
                          (sd_owner == 3'd4) ? video_sd_addr : lyr_sd_addr;

// Sector ownership changes only after the current 512-byte read completes.
// Audio has priority at sector boundaries, so an image load cannot starve it.
always @(posedge clk or posedge rst) begin
    if (rst)
        sd_owner <= 2'd0;
    else if (sd_owner == 2'd0) begin
        if (wav_sd_read && !wav_restart) sd_owner <= 2'd2;
        else if (lyr_sd_read && !lyr_restart && lyr_started) sd_owner <= 2'd3;
        else if (bmp_sd_read) sd_owner <= 2'd1;
        else if (video_sd_read) sd_owner <= 3'd4;
    end else if (sd_sec_read_end)
        sd_owner <= 2'd0;
end

// 多曲目表及播放器控制。切歌先复位读流/FIFO，下一拍再从新曲首扇区启动。
always @(posedge clk or posedge rst) begin
    if (rst) begin
        wav_count <= 5'd0;
        lyr_count <= 5'd0;
        wav_index <= 4'd0;
        tracks_initialized <= 1'b0;
        for (ti = 0; ti < 16; ti = ti + 1) begin
            wav_track_valid[ti] <= 1'b0;
            lyr_track_valid[ti] <= 1'b0;
        end
        wav_start_pulse <= 1'b0;
        wav_restart <= 1'b0;
        wav_restart_pending <= 1'b0;
        wav_start_pending <= 1'b0;
        wav_started <= 1'b0;
        wav_eof_pending <= 1'b0;
        eof_drain_guard <= 14'd0;
        lyr_start_pulse <= 1'b0;
        lyr_restart <= 1'b0;
        lyr_start_pending <= 1'b0;
        lyr_started <= 1'b0;
        music_prev_sync <= 3'b000;
        music_next_sync <= 3'b000;
        audio_tick_sync <= 3'b000;
        music_fifo_reset_toggle <= 1'b0;
        scan_done_d <= 1'b0;
    end else begin
        music_prev_sync <= {music_prev_sync[1:0], music_prev_toggle};
        music_next_sync <= {music_next_sync[1:0], music_next_toggle};
        audio_tick_sync <= {audio_tick_sync[1:0], audio_frame_tick_toggle};
        scan_done_d <= scan_done;
        wav_start_pulse <= 1'b0;
        wav_restart <= 1'b0;
        lyr_start_pulse <= 1'b0;
        lyr_restart <= 1'b0;
        if (!sd_init_done) begin
            wav_count <= 5'd0;
            lyr_count <= 5'd0;
            wav_index <= 4'd0;
            tracks_initialized <= 1'b0;
            for (ti = 0; ti < 16; ti = ti + 1) begin
                wav_track_valid[ti] <= 1'b0;
                lyr_track_valid[ti] <= 1'b0;
            end
            wav_restart_pending <= 1'b0;
            wav_start_pending <= 1'b0;
            wav_started <= 1'b0;
            wav_eof_pending <= 1'b0;
            eof_drain_guard <= 14'd0;
            lyr_start_pending <= 1'b0;
            lyr_started <= 1'b0;
        end else begin
            if (wav_item_valid && (wav_item_track_id >= 5'd1) &&
                (wav_item_track_id <= 5'd16)) begin
                if (!wav_track_valid[wav_item_track_id - 5'd1])
                    wav_count <= wav_count + 5'd1;
                wav_track_valid[wav_item_track_id - 5'd1] <= 1'b1;
            end
            if (lyr_item_valid && (lyr_item_track_id >= 8'd1) &&
                (lyr_item_track_id <= 8'd16)) begin
                if (!lyr_track_valid[lyr_item_track_id[4:0] - 5'd1])
                    lyr_count <= lyr_count + 5'd1;
                lyr_track_valid[lyr_item_track_id[4:0] - 5'd1] <= 1'b1;
            end
            // Pick the lowest valid track once the scan is complete.
            if (scan_done_d && !tracks_initialized && (wav_count != 5'd0)) begin
                wav_index <= first_valid_index;
                tracks_initialized <= 1'b1;
            end
            // Each track independently uses its matching lyric file.
            if (scan_done && metadata_ready && tracks_initialized && music_mode_sd && !wav_started &&
                (wav_count != 5'd0) && !load_busy && bmp_ready) begin
                wav_started <= 1'b1;
                wav_start_pulse <= 1'b1;
            end
            // The last lyr_item_valid arrives one cycle after scan_done, so the
            // lyric start is retried here until its catalogue entry is ready.
            if (wav_started && metadata_ready && music_mode_sd && lyric_catalog_ok && !lyr_started) begin
                lyr_started <= 1'b1;
                lyr_start_pending <= 1'b1;
            end
            // Never abort a physical CMD17 in the middle of its 512-byte
            // payload.  Restart both streams only at a clean owner boundary.
            if (wav_restart_pending && (sd_owner == 2'd0) &&
                !wav_sd_read && !lyr_sd_read && !bmp_sd_read) begin
                wav_restart_pending <= 1'b0;
                wav_restart <= 1'b1;
                music_fifo_reset_toggle <= ~music_fifo_reset_toggle;
                wav_start_pending <= music_mode_sd;
                lyr_restart <= 1'b1;
                lyr_start_pending <= music_mode_sd && lyric_catalog_ok;
            end else begin
                if (wav_start_pending && metadata_ready) begin
                    wav_start_pending <= 1'b0;
                    wav_start_pulse <= 1'b1;
                end
                if (lyr_start_pending && metadata_ready) begin
                    lyr_start_pending <= 1'b0;
                    lyr_start_pulse <= 1'b1;
                end
            end
            if (wav_eof)
                wav_eof_pending <= 1'b1;
            if (wav_eof_pending && (audio_fifo_count == 13'd0)) begin
                if (!advance_after_eof)
                    eof_drain_guard <= eof_drain_guard + 1'b1;
            end else
                eof_drain_guard <= 14'd0;
            if ((wav_count != 5'd0) && tracks_initialized && music_mode_sd &&
                ((remote_music_select && wav_track_valid[remote_music_index]) ||
                 music_prev_press || music_next_press || remote_music_prev ||
                 remote_music_next || advance_after_eof)) begin
                if (remote_music_select && wav_track_valid[remote_music_index])
                    wav_index <= remote_music_index;
                else if (music_prev_press || remote_music_prev)
                    wav_index <= prev_track;
                else
                    wav_index <= next_track;
                wav_restart_pending <= 1'b1;
                wav_eof_pending <= 1'b0;
                eof_drain_guard <= 14'd0;
            end
            // Leaving music mode aborts the current sector stream and clears
            // queued PCM.  Re-entering starts WAV and lyrics from the head.
            if (music_mode_d && !music_mode_sd) begin
                wav_started <= 1'b0;
                lyr_started <= 1'b0;
                wav_restart_pending <= 1'b1;
                wav_start_pending <= 1'b0;
                lyr_start_pending <= 1'b0;
                wav_eof_pending <= 1'b0;
            end
        end
    end
end

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_mode_legacy (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_mode),
    .press_pulse(key_mode_raw_press)
);

always @(posedge clk or posedge rst) begin
    if(rst) begin
        key_mode_tgl_sync <= 3'b000;
        edit_active_sync  <= 2'b00;
        music_mode_sync   <= 2'b00;
        write_ack_sync    <= 2'b00;
    end else begin
        key_mode_tgl_sync <= {key_mode_tgl_sync[1:0], key_mode_toggle};
        edit_active_sync  <= {edit_active_sync[0], edit_active};
        music_mode_sync   <= {music_mode_sync[0], music_mode};
        write_ack_sync    <= {write_ack_sync[0], write_req_ack};
    end
end

function [3:0] next_index_limited;
    input [3:0] cur;
    input [4:0] count;
    reg   [4:0] nxt;
    begin
        // 在 5bit 域内比较，避免 count==16 时被截断成 0 导致永远跳回首张
        nxt = {1'b0, cur} + 5'd1;
        if (count == 5'd0)
            next_index_limited = 4'd0;
        else if (nxt >= count)
            next_index_limited = 4'd0;
        else
            next_index_limited = nxt[3:0];
    end
endfunction

function [31:0] sector_lut;
    input [3:0] idx;
    begin
        sector_lut = img_sector[idx];
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

function [3:0] prev_index_limited;
    input [3:0] cur;
    input [4:0] count;
    begin
        if (count == 5'd0)
            prev_index_limited = 4'd0;
        else if (cur == 4'd0)
            prev_index_limited = count[3:0] - 1'b1;
        else
            prev_index_limited = cur - 1'b1;
    end
endfunction

// Lowest valid track index (used once after the scan completes).
integer vi;
always @(*) begin
    first_valid_index = 4'd0;
    for (vi = 15; vi >= 0; vi = vi - 1)
        if (wav_track_valid[vi])
            first_valid_index = vi[3:0];
end

// Parallel masks and balanced encoders avoid fifteen serial priority muxes.
wire [3:0] next_track, prev_track;
music_track_neighbors u_track_neighbors (
    .valid(music_track_map), .current(wav_index),
    .next_index(next_track), .prev_index(prev_track)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_mode_r           <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 5'd0;
        img_idx               <= 4'd0;
        load_idx              <= 4'd0;
        pending_buf_idx       <= 2'd0;
        image_write_buf_idx         <= 2'd0;
        image_disp_buf_idx          <= 2'd0;
        for (i = 0; i < 16; i = i + 1) begin
            img_sector[i] <= 32'd0;
            image_size_table[i] <= 2'd0;
            image_aspect_table[i] <= 2'd0;
        end
        load_image_size <= 2'd0;
        load_image_aspect <= 2'd0;
        target_req_pending    <= 1'b0;
        target_req_auto <= 1'b0;
        target_req_idx        <= 4'd0;
        load_busy             <= 1'b0;
        load_is_auto <= 1'b0;
        source_done_seen      <= 1'b0;
        image_display_valid         <= 1'b0;
        music_mode_d          <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_mode_r           <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 5'd0;
            img_idx               <= 4'd0;
            load_idx              <= 4'd0;
            pending_buf_idx       <= 2'd0;
            image_write_buf_idx         <= 2'd0;
            image_disp_buf_idx          <= 2'd0;
            for (i = 0; i < 16; i = i + 1) begin
                img_sector[i] <= 32'd0;
                image_size_table[i] <= 2'd0;
                image_aspect_table[i] <= 2'd0;
            end
            load_image_size <= 2'd0;
            load_image_aspect <= 2'd0;
            target_req_pending    <= 1'b0;
            target_req_auto <= 1'b0;
            target_req_idx        <= 4'd0;
            load_busy             <= 1'b0;
            load_is_auto <= 1'b0;
            source_done_seen      <= 1'b0;
            image_display_valid         <= 1'b0;
            music_mode_d          <= 1'b0;
        end else begin
            music_mode_d <= music_mode_sd;
            // 扫描阶段缓存所有图的起始扇区
            if (scan_found_valid) begin
                if (img_found_count < 5'd16) begin
                    img_sector[img_found_count[3:0]] <= scan_found_sector;
                    img_found_count <= img_found_count + 5'd1;
                end
            end

            // bmp_read 读完 SD 后 ready=1，记住这个状态
            if (load_busy && bmp_ready)
                source_done_seen <= 1'b1;

            // SDRAM 写完一帧 → commit，切显示缓冲
            if (load_busy && source_done_seen && write_finish_pulse) begin
                load_busy             <= 1'b0;
                load_is_auto <= 1'b0;
                source_done_seen      <= 1'b0;
                // If an old automatic request finishes after H3 was entered,
                // discard that different image instead of moving the editor
                // to a different per-image setting underneath the user.
                if (!(image_size_edit && image_display_valid && (load_idx != img_idx)) &&
                    !(load_is_auto && (!auto_mode_r || remote_manual ||
                      remote_select_valid || remote_next || remote_prev ||
                      (key_mode_press && auto_mode_r)))) begin
                    image_disp_buf_idx <= pending_buf_idx;
                    img_idx <= load_idx;
                end
                image_display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
            end

            // 上电自动发起扫描
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_mode_r           <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 5'd0;
                img_idx               <= 4'd0;
                load_idx              <= 4'd0;
                pending_buf_idx       <= 2'd0;
                image_write_buf_idx         <= 2'd0;
                image_disp_buf_idx          <= 2'd0;
                target_req_pending    <= 1'b0;
                target_req_auto <= 1'b0;
                target_req_idx        <= 4'd0;
                image_display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                load_is_auto <= 1'b0;
                source_done_seen      <= 1'b0;
            end else begin
                // Cancel an automatic request that has not started when leaving auto mode.
                if (target_req_auto && (!auto_mode_r || remote_manual ||
                    (key_mode_press && auto_mode_r))) begin
                    target_req_pending <= 1'b0;
                    target_req_auto <= 1'b0;
                end
                // KEY3：不在属性编辑时切下一张（自动轮播开启时也允许手动切图）
                if (background_next && !edit_active_sync[1] && scan_done &&
                    (img_found_count > 5'd0)) begin
                    target_req_idx     <= next_from_current;
                    target_req_pending <= 1'b1;
                    target_req_auto <= 1'b0;
                    auto_cnt           <= 32'd0;
                end

                // KEY4：切手动/自动模式
                if (key_mode_press && scan_done && (img_found_count > 5'd1)) begin
                    auto_mode_r <= ~auto_mode_r;
                    auto_cnt    <= 32'd0;
                end

                // UART remote control. Explicit selection/next/previous enters manual mode.
                if (remote_select_valid && scan_done && ({1'b0, remote_select_index} < img_found_count)) begin
                    auto_mode_r <= 1'b0;
                    auto_cnt    <= 32'd0;
                    if (!image_display_valid || (remote_select_index != img_idx)) begin
                        target_req_idx     <= remote_select_index;
                        target_req_pending <= 1'b1;
                        target_req_auto <= 1'b0;
                    end
                end else if (remote_next && scan_done && (img_found_count > 5'd0)) begin
                    auto_mode_r       <= 1'b0;
                    auto_cnt          <= 32'd0;
                    target_req_idx     <= next_from_current;
                    target_req_pending <= 1'b1;
                    target_req_auto <= 1'b0;
                end else if (remote_prev && scan_done && (img_found_count > 5'd0)) begin
                    auto_mode_r       <= 1'b0;
                    auto_cnt          <= 32'd0;
                    target_req_idx     <= prev_index_limited(img_idx, img_found_count);
                    target_req_pending <= 1'b1;
                    target_req_auto <= 1'b0;
                end else if (remote_manual && scan_done && (img_found_count > 5'd0)) begin
                    auto_mode_r <= 1'b0;
                    auto_cnt    <= 32'd0;
                end else if (remote_auto && scan_done && (img_found_count > 5'd0)) begin
                    auto_mode_r <= (img_found_count > 5'd1);
                    auto_cnt    <= 32'd0;
                end

                // 只有自动模式才轮播：图片模式 1 秒，音乐模式 10 秒
                if (scan_done && !image_size_edit && !edit_active_sync[1] && auto_mode_r && image_display_valid && !load_busy &&
                    (img_found_count > 5'd1) &&
                    !(background_next || key_mode_press || remote_select_valid || remote_next || remote_prev || remote_manual || remote_auto)) begin
                    if (auto_tick) begin
                        auto_cnt <= 32'd0;
                        target_req_idx     <= next_from_current;
                        target_req_pending <= 1'b1;
                        target_req_auto <= 1'b1;
                    end else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图：加载第0张（音乐模式下让 WAV 先启动，避免首图加载拖慢音频）
                if (!video_mode && scan_done && !first_image_committed && bmp_ready && !load_busy &&
                    (img_found_count != 5'd0) && (!music_mode_sd || wav_started)) begin
                    load_idx         <= 4'd0;
                    load_image_size  <= image_size_table[0];
                    load_image_aspect <= image_aspect_table[0];
                    load_sector      <= img_sector[4'd0];
                    pending_buf_idx  <= 2'd0;
                    image_write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    target_req_pending <= 1'b0;
                    target_req_auto <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 后续图：按请求加载下一张
                else if (!video_mode && scan_done && bmp_ready && image_display_valid && !load_busy &&
                         (!WAIT_DISPLAY_RELEASE || display_released_bank == image_disp_buf_idx) &&
                         target_req_pending && (img_found_count != 5'd0) &&
                         !(background_next || key_mode_press || remote_select_valid || remote_next || remote_prev || remote_manual || remote_auto) &&
                         (!target_req_auto || auto_mode_r) &&
                         (!image_size_edit || target_req_idx == img_idx) && !geometry_change) begin
                    load_idx         <= target_req_idx;
                    load_is_auto <= target_req_auto;
                    load_image_size  <= image_size_table[target_req_idx];
                    load_image_aspect <= image_aspect_table[target_req_idx];
                    load_sector      <= sector_lut(target_req_idx);
                    pending_buf_idx  <= next_buf_lut(image_disp_buf_idx, image_display_valid);
                    image_write_buf_idx    <= next_buf_lut(image_disp_buf_idx, image_display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    target_req_pending <= 1'b0;
                    target_req_auto <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // Latest size wins while a preview is loading. Never change
                // the scaler's latched size in the middle of a frame.
                if (size_change) begin
                    image_size_table[img_idx] <= remote_size_set ? remote_size_value :
                                                (current_image_size >= 2'd2) ?
                                                2'd0 : current_image_size + 1'b1;
                end
                if (aspect_change)
                    image_aspect_table[img_idx] <= remote_aspect_set ? remote_aspect_value :
                                                   current_image_aspect + 1'b1;
                if (geometry_change) begin
                    target_req_idx <= img_idx;
                    target_req_pending <= 1'b1;
                    target_req_auto <= 1'b0;
                    auto_cnt <= 32'd0;
                end
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),
    .wav_found              (wav_found),
    .wav_first_lba          (wav_lba),
    .wav_first_cluster      (wav_cluster),
    .wav_no_fat_chain       (wav_no_fat_chain),
    .wav_file_bytes         (wav_file_bytes),
    .wav_item_valid         (wav_item_valid),
    .wav_item_lba           (wav_item_lba),
    .wav_item_cluster       (wav_item_cluster),
    .wav_item_no_fat_chain  (wav_item_no_fat_chain),
    .wav_item_file_bytes    (wav_item_file_bytes),
    .wav_item_track_id      (wav_item_track_id),
    .lyr_item_valid         (lyr_item_valid),
    .lyr_item_lba           (lyr_item_lba),
    .lyr_item_cluster       (lyr_item_cluster),
    .lyr_item_no_fat_chain  (lyr_item_no_fat_chain),
    .lyr_item_file_bytes    (lyr_item_file_bytes),
    .lyr_item_track_id      (lyr_item_track_id),
    .mvi_item_valid         (mvi_item_valid),
    .mvi_item_rgb332        (mvi_item_rgb332),
    .mvi_item_indexed       (mvi_item_indexed),
    .mvi_item_dynamic       (mvi_item_dynamic),
    .mvi_item_lba           (mvi_item_lba),
    .mvi_item_cluster       (mvi_item_cluster),
    .mvi_item_no_fat_chain  (mvi_item_no_fat_chain),
    .mvi_item_file_bytes    (mvi_item_file_bytes),
    .fs_volume_lba          (fs_volume_lba),
    .fs_fat_offset          (fs_fat_offset),
    .fs_heap_offset         (fs_heap_offset),
    .fs_spc_shift           (fs_spc_shift),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .bmp_load_begin         (bmp_load_begin),
    .bmp_src_width          (bmp_src_width),
    .bmp_src_height         (bmp_src_height),
    .scale_go               (scale_go),
    .scale_ready            (scale_ready),
    .write_req              (bmp_write_req),
    .write_req_ack          (write_req_ack_sd),
    .sd_sec_read            (bmp_sd_read),
    .sd_sec_read_addr       (bmp_sd_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid && sd_owner == 2'd1),
    .sd_sec_read_end        (sd_sec_read_end && sd_owner == 2'd1),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

bmp_fit_scaler #(.USE_VIEWPORT(1),.USE_ASPECT(1)) bmp_fit_scaler_m0(
    .clk              (clk),
    .rst              (rst),
    .start            (video_mode ? video_frame_start : bmp_load_begin),
    .go               (video_mode ? video_scale_go : scale_go),
    .src_width        (video_mode ? 16'd320 : bmp_src_width),
    .src_height       (video_mode ? 16'd240 : bmp_src_height),
    .viewport_mode    (video_mode ? 2'd0 : load_image_size),
    .aspect_mode      (video_mode ? 2'd0 : load_image_aspect),
    .pixel_valid      (video_mode ? video_pixel_valid : bmp_data_wr_en),
    .pixel_data       (video_mode ? video_pixel_data : bmp_data),
    .write_full       (write_full),
    .ready_for_pixels (scale_ready),
    .write_en         (scale_write_en),
    .write_data       (scale_write_data),
    .done             (scale_done),
    .overflow         (scale_overflow)
);

// Lyrics and the per-track title block are read from the LYR2 file that is
// paired with the selected WAV.  Only two sectors per 500 ms are requested.
exfat_lyric_bitmap_reader lyr_reader_m0(
    .clk             (clk),
    .rst             (rst),
    .start           (lyr_start_pulse),
    .restart         (lyr_restart),
    .first_lba       (selected_lyr_meta[31:0]),
    .file_bytes      (selected_lyr_meta[63:32]),
    .no_fat_chain    (selected_lyr_meta[64]),
    .pcm_frame_tick  (audio_frame_tick),
    .video_clk       (video_clk),
    .pixel_x         (pixel_x),
    .pixel_y         (pixel_y),
    .sd_sec_read     (lyr_sd_read),
    .sd_sec_read_addr(lyr_sd_addr),
    .sd_data         (sd_sec_read_data),
    .sd_data_valid   (sd_sec_read_data_valid && sd_owner == 2'd3),
    .sd_read_end     (sd_sec_read_end && sd_owner == 2'd3),
    .pixel_on        (lyr_pixel_on_w),
    .title_pixel_on  (lyr_title_pixel_on_w),
    .frame_valid     (lyr_frame_valid_w),
    .title_valid     (lyr_title_valid_w),
    .lyric_error     (lyr_error_unused)
);

exfat_pcm_wav_reader #(.USE_CLUSTER_START(1)) wav_reader_m0(
    .clk(clk), .rst(rst), .start(video_mode ? video_audio_start : wav_start_pulse), .restart(wav_restart),
    .first_lba(32'd0), .first_cluster(selected_wav_cluster),
    .file_bytes(selected_wav_meta[63:32]), .no_fat_chain(selected_wav_meta[64]),
    .volume_lba(fs_volume_lba), .fat_offset(fs_fat_offset),
    .heap_offset(fs_heap_offset), .spc_shift(fs_spc_shift),
    .fifo_count(audio_fifo_count), .fifo_full(audio_fifo_full || wav_restart_pending),
    .fifo_wr_en(audio_frame_valid), .fifo_wr_data(audio_frame_data),
    .wav_valid(wav_stream_valid), .wav_error(wav_error), .eof(wav_eof),
    .sd_sec_read(wav_sd_read), .sd_sec_read_addr(wav_sd_addr),
    .sd_data(sd_sec_read_data),
    .sd_data_valid(sd_sec_read_data_valid && sd_owner == 2'd2),
    .sd_read_end(sd_sec_read_end && sd_owner == 2'd2)
);

sd_card_top #(
    .FAST_DIV0(FAST_DIV0)
) sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .video_fast_read        (video_mode),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,
    output reg  press_pulse
);

    localparam integer RAW_COUNT = CLK_FREQ_HZ / 1000 * DEBOUNCE_MS;
    localparam integer CNT_MAX = RAW_COUNT > 0 ? RAW_COUNT : 1;
    localparam integer CNT_BITS = CNT_MAX > 1 ? $clog2(CNT_MAX) : 1;
    reg [CNT_BITS-1:0] cnt;
    reg        sync0, sync1, stable;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            sync0 <= 1'b1;
            sync1 <= 1'b1;
            stable <= 1'b1;
            cnt    <= 32'd0;
            press_pulse <= 1'b0;
        end else begin
            sync0 <= button_in;
            sync1 <= sync0;
            press_pulse <= 1'b0;

            if(sync1 != stable) begin
                if(cnt == CNT_MAX - 1) begin
                    stable <= sync1;
                    cnt <= 32'd0;
                    if(sync1 == 1'b0)
                        press_pulse <= 1'b1;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end else begin
                cnt <= 32'd0;
            end
        end
    end

endmodule

// Nearest valid numeric track, including wraparound and empty/singleton maps.
module music_track_neighbors (
    input wire [15:0] valid,
    input wire [3:0] current,
    output wire [3:0] next_index,
    output wire [3:0] prev_index
);
    wire [15:0] above = valid & (16'hffff << ({1'b0,current} + 5'd1));
    wire [15:0] below = valid & ((16'h0001 << current) - 16'd1);
    wire [15:0] forward_map = (|above) ? above : valid;
    wire [15:0] backward_map = (|below) ? below : valid;
    wire [15:0] backward_reversed;
    genvar b;
    generate for (b=0; b<16; b=b+1) begin : g_reverse
        assign backward_reversed[b] = backward_map[15-b];
    end endgenerate
    function [3:0] first_set;
        input [15:0] bits;
        reg [7:0] half_bits;
        reg [3:0] quarter_bits;
        reg [1:0] pair_bits;
        begin
            first_set[3] = !(|bits[7:0]);
            half_bits = first_set[3] ? bits[15:8] : bits[7:0];
            first_set[2] = !(|half_bits[3:0]);
            quarter_bits = first_set[2] ? half_bits[7:4] : half_bits[3:0];
            first_set[1] = !(|quarter_bits[1:0]);
            pair_bits = first_set[1] ? quarter_bits[3:2] : quarter_bits[1:0];
            first_set[0] = !pair_bits[0];
        end
    endfunction
    assign next_index = (|valid) ? first_set(forward_map) : current;
    assign prev_index = (|valid) ? (4'd15 - first_set(backward_reversed)) : current;
endmodule
