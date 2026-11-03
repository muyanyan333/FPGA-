// Bluetooth UART remote control for the HDMI image player.
// Command frame (phone -> FPGA): A5 CMD ARG CHECK, CHECK=A5^CMD^ARG
//   01=query, 02=play(ARG=1..16), 03=auto, 04=next, 05=previous,
//   06=manual, 07=effect(0=C/1=F/2=S), 08=brightness(0..9), 09=contrast(0..9)
// State frame (FPGA -> phone): 5A 81 COUNT CURRENT FLAGS MAP_L MAP_H CHECK
//   CURRENT is 1-based (0 means unavailable); FLAGS[0]=auto, FLAGS[1]=scan_done.
module uart_image_control #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 9600
)(
    input             clk,
    input             rst,
    input             uart_rx,
    input             voice_rx,
    input             gesture_rx,
    input             key_volume_up,
    input             key_volume_down,
    input             key_volume_set,
    input      [3:0]  key_volume_value,
    output            uart_tx,
    output            voice_tx,
    input      [4:0]  image_count,
    input      [3:0]  current_index,
    input             auto_mode,
    input             scan_done,
    input      [1:0]  transition_effect,
    input      [3:0]  brightness_level,
    input      [3:0]  contrast_level,
    input      [1:0]  image_size,
    input      [1:0]  image_aspect,
    input      [4:0]  music_track_number,
    input      [4:0]  music_track_count,
    input      [15:0] music_track_map,
    input             music_playing,
    input             lyric_valid,
    input             title_valid,
    input [1:0]       camera_mode,
    input [2:0]       video_status,
    output reg        camera_mode_request,
    output reg [1:0]  camera_mode_value,
    output reg        select_valid,
    output reg [3:0]  select_index,
    output reg        auto_pulse,
    output reg        manual_pulse,
    output reg        next_pulse,
    output reg        prev_pulse,
    output reg        music_prev_pulse,
    output reg        music_next_pulse,
    output reg        effect_toggle,
    output reg [1:0]  effect_value,
    output reg        brightness_toggle,
    output reg [3:0]  brightness_value,
    output reg        contrast_toggle,
    output reg [3:0]  contrast_value,
    output reg        size_toggle,
    output reg [1:0]  size_value,
    output reg        aspect_toggle,
    output reg [1:0]  aspect_value,
    output reg        music_select_toggle,
    output reg [3:0]  music_select_index,
    output reg        playing_toggle,
    output reg        playing_value,
    output reg        lyric_enabled,
    output reg        title_enabled,
    output reg        spectrum_enabled,
    output reg [3:0]  volume_level,
    output reg        volume_muted,
    output reg        notice_toggle,
    output reg [7:0]  notice_flags,
    output reg [9:0]  notice_width,
    output reg        notice_receiving,
    input             notice_rd_clk,
    input      [9:0]  notice_rd_addr,
    output reg [7:0]  notice_rd_data
);


// 512x16 one-bit bitmap, packed as 64 bytes per row. The browser renders
// Unicode text into this bitmap before transmission, so FPGA needs no CJK ROM.
reg [7:0] notice_mem [0:1023];
// A registered video-clock read port lets the 1 KiB bitmap use block RAM.
always @(posedge notice_rd_clk)
    notice_rd_data <= notice_mem[notice_rd_addr];

wire [7:0] rx_data;
wire       rx_valid;
wire [7:0] voice_cmd, voice_arg;
wire       voice_valid;
wire       gesture_next, gesture_prev;
wire       bt_command_valid = rx_valid && (notice_rx_state == 3'd0) &&
                              (rx_frame_pos == 2'd3) &&
                              (rx_data == (8'hA5 ^ rx_cmd ^ rx_arg));
reg        voice_pending;
reg [7:0]  voice_pending_cmd, voice_pending_arg;
wire       command_valid = bt_command_valid || voice_pending || voice_valid;
wire [7:0] command_cmd = bt_command_valid ? rx_cmd :
                         voice_pending ? voice_pending_cmd : voice_cmd;
wire [7:0] command_arg = bt_command_valid ? rx_arg :
                         voice_pending ? voice_pending_arg : voice_arg;
reg  [1:0] rx_frame_pos;
reg  [7:0] rx_cmd;
reg  [7:0] rx_arg;
reg        query_pulse;
reg  [2:0] notice_rx_state;
reg [10:0] notice_rx_count;
reg  [7:0] notice_rx_checksum;
reg  [7:0] notice_rx_flags;
reg  [9:0] notice_rx_width;
reg [26:0] notice_rx_timeout;
reg [31:0] notice_second_count;
reg  [5:0] notice_elapsed_seconds;
wire [5:0] notice_duration_seconds = (notice_flags[5:4] == 2'd1) ? 6'd10 :
                                     (notice_flags[5:4] == 2'd2) ? 6'd30 :
                                     (notice_flags[5:4] == 2'd3) ? 6'd60 : 6'd0;

reg  [4:0] last_count;
reg  [3:0] last_current;
reg        last_auto;
reg        last_scan_done;
reg [1:0]  last_effect;
reg [3:0]  last_brightness;
reg [3:0]  last_contrast;
reg [1:0]  last_size, last_aspect;
reg [4:0]  last_music_track, last_music_count;
reg        last_playing, last_lyric_enabled, last_title_enabled;
reg last_spectrum_enabled;
reg [3:0] last_volume;
reg last_muted;
reg [3:0] frame_volume;
reg frame_muted;
reg [2:0] frame_video_status, last_video_status;
reg [1:0] frame_camera_mode;
reg [1:0]  last_camera_mode;
reg        last_lyric_valid, last_title_valid;
reg        status_pending;
reg [31:0] heartbeat_count;

reg  [7:0] frame_count;
reg  [7:0] frame_current;
reg  [7:0] frame_flags;
reg [15:0] frame_map;
reg  [3:0] frame_brightness;
reg  [3:0] frame_contrast;
reg  [1:0] frame_effect;
reg  [1:0] frame_size, frame_aspect;
reg  [7:0] frame_music_track, frame_music_count, frame_music_flags;
reg  [15:0] frame_music_map;
reg  [2:0] frame_type;
reg  [7:0] frame_notice_flags;
reg  [9:0] frame_notice_width;
reg        frame_active;
reg  [2:0] frame_index;
reg        tx_wait_busy;
reg        tx_start;
reg  [7:0] tx_data;
wire       tx_busy;
reg        voice_reply_pending;
reg        voice_reply_active;
// Reuse the W02 status transmitter; expose just the first status frame
// after an ASRPRO command, so the voice chip receives one clean reply.
assign voice_tx = voice_reply_active ? uart_tx : 1'b1;

uart_rx_byte #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) u_rx (
    .clk       (clk),
    .rst       (rst),
    .uart_rx   (uart_rx),
    .data      (rx_data),
    .data_valid(rx_valid)
);

voice_uart_command #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_voice_rx (
    .clk(clk), .rst(rst), .uart_rx(voice_rx),
    .command_valid(voice_valid), .command(voice_cmd), .argument(voice_arg)
);

gesture_uart_command #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_gesture_rx (
    .clk(clk), .rst(rst), .uart_rx(gesture_rx),
    .next_valid(gesture_next), .prev_valid(gesture_prev)
);

uart_tx_byte #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) u_tx (
    .clk       (clk),
    .rst       (rst),
    .start     (tx_start),
    .data      (tx_data),
    .uart_tx   (uart_tx),
    .busy      (tx_busy)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_frame_pos <= 2'd0;
        rx_cmd       <= 8'd0;
        rx_arg       <= 8'd0;
        query_pulse  <= 1'b0;
        select_valid <= 1'b0;
        select_index <= 4'd0;
        auto_pulse   <= 1'b0;
        manual_pulse <= 1'b0;
        next_pulse   <= 1'b0;
        prev_pulse   <= 1'b0;
        music_prev_pulse <= 1'b0;
        music_next_pulse <= 1'b0;
        voice_pending <= 1'b0;
        voice_pending_cmd <= 8'd0;
        voice_pending_arg <= 8'd0;
        effect_toggle     <= 1'b0;
        effect_value      <= 2'd0;
        brightness_toggle <= 1'b0;
        brightness_value  <= 4'd9;
        contrast_toggle   <= 1'b0;
        contrast_value    <= 4'd5;
        size_toggle       <= 1'b0;
        size_value        <= 2'd0;
        aspect_toggle     <= 1'b0;
        aspect_value      <= 2'd0;
        music_select_toggle <= 1'b0;
        music_select_index <= 4'd0;
        playing_toggle <= 1'b0;
        playing_value <= 1'b1;
        lyric_enabled <= 1'b1;
        title_enabled <= 1'b1;
        spectrum_enabled <= 1'b1;
        volume_level <= 4'd10;
        volume_muted <= 1'b0;
        camera_mode_request <= 1'b0;
        camera_mode_value <= 1'b0;
        notice_toggle     <= 1'b0;
        notice_flags      <= 8'd0;
        notice_width      <= 10'd0;
        notice_receiving  <= 1'b0;
        notice_rx_state   <= 3'd0;
        notice_rx_count   <= 11'd0;
        notice_rx_checksum<= 8'd0;
        notice_rx_flags   <= 8'd0;
        notice_rx_width   <= 10'd0;
        notice_rx_timeout <= 27'd0;
        notice_second_count <= 32'd0;
        notice_elapsed_seconds <= 6'd0;
    end else begin
        query_pulse  <= 1'b0;
        select_valid <= 1'b0;
        auto_pulse   <= 1'b0;
        manual_pulse <= 1'b0;
        next_pulse   <= 1'b0;
        prev_pulse   <= 1'b0;
        camera_mode_request <= 1'b0;
        music_prev_pulse <= 1'b0;
        music_next_pulse <= 1'b0;
        if (voice_valid && (bt_command_valid || voice_pending)) begin
            voice_pending <= 1'b1;
            voice_pending_cmd <= voice_cmd;
            voice_pending_arg <= voice_arg;
        end else if (!bt_command_valid && voice_pending)
            voice_pending <= 1'b0;

        // Optional FPGA-side expiry keeps a notice from remaining forever even
        // when the phone disconnects after sending it.
        if (notice_flags[0] && (notice_duration_seconds != 6'd0) && !notice_receiving) begin
            if (notice_second_count >= (CLK_FREQ_HZ - 1)) begin
                notice_second_count <= 32'd0;
                if ((notice_elapsed_seconds + 1'b1) >= notice_duration_seconds) begin
                    notice_flags <= 8'd0;
                    notice_width <= 10'd0;
                    notice_toggle <= ~notice_toggle;
                    notice_elapsed_seconds <= 6'd0;
                    query_pulse <= 1'b1;
                end else begin
                    notice_elapsed_seconds <= notice_elapsed_seconds + 1'b1;
                end
            end else begin
                notice_second_count <= notice_second_count + 1'b1;
            end
        end else begin
            notice_second_count <= 32'd0;
            notice_elapsed_seconds <= 6'd0;
        end

        if (notice_receiving) begin
            if (notice_rx_timeout >= CLK_FREQ_HZ) begin
                notice_receiving <= 1'b0;
                notice_rx_state  <= 3'd0;
                notice_rx_timeout<= 27'd0;
            end else begin
                notice_rx_timeout <= notice_rx_timeout + 1'b1;
            end
        end else begin
            notice_rx_timeout <= 27'd0;
        end

        if (rx_valid) begin
            notice_rx_timeout <= 27'd0;
            if (notice_rx_state != 3'd0) begin
                case (notice_rx_state)
                    3'd1: begin
                        notice_rx_flags    <= rx_data;
                        notice_rx_checksum <= notice_rx_checksum ^ rx_data;
                        notice_rx_state    <= 3'd2;
                    end
                    3'd2: begin
                        notice_rx_width[7:0] <= rx_data;
                        notice_rx_checksum   <= notice_rx_checksum ^ rx_data;
                        notice_rx_state      <= 3'd3;
                    end
                    3'd3: begin
                        notice_rx_width[9:8] <= rx_data[1:0];
                        notice_rx_checksum   <= notice_rx_checksum ^ rx_data;
                        notice_rx_count      <= 11'd0;
                        notice_rx_state      <= 3'd4;
                    end
                    3'd4: begin
                        notice_mem[notice_rx_count[9:0]] <= rx_data;
                        notice_rx_checksum <= notice_rx_checksum ^ rx_data;
                        if (notice_rx_count == 11'd1023)
                            notice_rx_state <= 3'd5;
                        else
                            notice_rx_count <= notice_rx_count + 1'b1;
                    end
                    default: begin
                        notice_receiving <= 1'b0;
                        notice_rx_state  <= 3'd0;
                        if (rx_data == notice_rx_checksum) begin
                            notice_flags  <= notice_rx_flags;
                            notice_width  <= (notice_rx_width > 10'd512) ? 10'd512 : notice_rx_width;
                            notice_toggle <= ~notice_toggle;
                            notice_second_count <= 32'd0;
                            notice_elapsed_seconds <= 6'd0;
                            query_pulse   <= 1'b1;
                        end
                    end
                endcase
            end else begin
                case (rx_frame_pos)
                    2'd0: begin
                        if (rx_data == 8'hA5)
                            rx_frame_pos <= 2'd1;
                        else if (rx_data == 8'hA6) begin
                            notice_receiving  <= 1'b1;
                            notice_rx_state   <= 3'd1;
                            notice_rx_checksum<= 8'hA6;
                            notice_rx_count   <= 11'd0;
                        end
                    end
                    2'd1: begin
                        rx_cmd       <= rx_data;
                        rx_frame_pos <= 2'd2;
                    end
                    2'd2: begin
                        rx_arg       <= rx_data;
                        rx_frame_pos <= 2'd3;
                    end
                    default: begin
                        rx_frame_pos <= 2'd0;
                    end
                endcase
            end
        end
        if (command_valid) begin
            query_pulse <= 1'b1;
            case (command_cmd)
                8'h02: if (command_arg >= 8'd1 && command_arg <= 8'd16) begin
                    select_index <= command_arg[3:0] - 1'b1;
                    select_valid <= 1'b1;
                end
                8'h03: auto_pulse <= 1'b1;
                8'h04: next_pulse <= 1'b1;
                8'h05: prev_pulse <= 1'b1;
                8'h06: manual_pulse <= 1'b1;
                8'h07: if (command_arg <= 8'd2) begin
                    effect_value <= command_arg[1:0];
                    effect_toggle <= ~effect_toggle;
                end
                8'h08: if (command_arg <= 8'd9) begin
                    brightness_value <= command_arg[3:0];
                    brightness_toggle <= ~brightness_toggle;
                end
                8'h09: if (command_arg <= 8'd9) begin
                    contrast_value <= command_arg[3:0];
                    contrast_toggle <= ~contrast_toggle;
                end
                8'h0A: begin
                    notice_flags <= 8'd0;
                    notice_width <= 10'd0;
                    notice_toggle <= ~notice_toggle;
                    notice_second_count <= 32'd0;
                    notice_elapsed_seconds <= 6'd0;
                end
                8'h0B: if (command_arg <= 8'd2) begin
                    size_value <= command_arg[1:0];
                    size_toggle <= ~size_toggle;
                end
                8'h0C: if (command_arg <= 8'd3) begin
                    aspect_value <= command_arg[1:0];
                    aspect_toggle <= ~aspect_toggle;
                end
                8'h0D: if (command_arg >= 8'd1 && command_arg <= 8'd16) begin
                    music_select_index <= command_arg[3:0] - 1'b1;
                    music_select_toggle <= ~music_select_toggle;
                end
                8'h0E: if (command_arg <= 8'd1) begin
                    playing_value <= command_arg[0];
                    playing_toggle <= ~playing_toggle;
                end
                8'h0F: if (command_arg <= 8'd1) lyric_enabled <= command_arg[0];
                8'h10: if (command_arg <= 8'd1) title_enabled <= command_arg[0];
                8'h11: music_prev_pulse <= 1'b1;
                8'h12: music_next_pulse <= 1'b1;
                8'h13: begin
                    effect_value <= (transition_effect >= 2'd2) ? 2'd0 : transition_effect + 1'b1;
                    effect_toggle <= ~effect_toggle;
                end
                8'h14: begin
                    brightness_value <= (brightness_level >= 4'd9) ? 4'd9 : brightness_level + 1'b1;
                    brightness_toggle <= ~brightness_toggle;
                end
                8'h15: begin
                    brightness_value <= (brightness_level == 4'd0) ? 4'd0 : brightness_level - 1'b1;
                    brightness_toggle <= ~brightness_toggle;
                end
                8'h16: begin
                    contrast_value <= (contrast_level >= 4'd9) ? 4'd9 : contrast_level + 1'b1;
                    contrast_toggle <= ~contrast_toggle;
                end
                8'h17: begin
                    contrast_value <= (contrast_level == 4'd0) ? 4'd0 : contrast_level - 1'b1;
                    contrast_toggle <= ~contrast_toggle;
                end
                8'h18: begin
                    size_value <= (image_size >= 2'd2) ? 2'd0 : image_size + 1'b1;
                    size_toggle <= ~size_toggle;
                end
                8'h19: begin
                    aspect_value <= image_aspect + 1'b1;
                    aspect_toggle <= ~aspect_toggle;
                end
                8'h1A: lyric_enabled <= ~lyric_enabled;
                8'h1B: title_enabled <= ~title_enabled;
                8'h1C: begin
                    playing_value <= ~music_playing;
                    playing_toggle <= ~playing_toggle;
                end
                8'h20: if (command_arg <= 8'd10) begin
                    volume_level <= command_arg[3:0]; volume_muted <= 1'b0;
                end
                8'h21: if (command_arg == 0) begin
                    if (volume_level < 10) volume_level <= volume_level + 1'b1;
                    volume_muted <= 1'b0;
                end
                8'h22: if (command_arg == 0) begin
                    if (volume_level > 0) volume_level <= volume_level - 1'b1;
                    volume_muted <= 1'b0;
                end
                8'h23: if (command_arg <= 1) volume_muted <= command_arg[0];
                8'h24: if (command_arg == 0) volume_muted <= ~volume_muted;
                8'h1E: if (command_arg <= 8'd1) spectrum_enabled <= command_arg[0];
                8'h1F: if (command_arg == 8'd0) spectrum_enabled <= ~spectrum_enabled;
                8'h1D: if (command_arg <= 8'd2) begin
                    camera_mode_value <= command_arg[1:0];
                    camera_mode_request <= 1'b1;
                end
                default: ; // 01=query
            endcase
        end
        if (gesture_next) next_pulse <= 1'b1;
        if (gesture_prev) prev_pulse <= 1'b1;
        if (key_volume_set && key_volume_value <= 4'd10) begin
            volume_level <= key_volume_value;
            volume_muted <= 1'b0;
        end else if (key_volume_up && volume_level < 4'd10) begin
            volume_level <= volume_level + 1'b1;
            volume_muted <= 1'b0;
        end else if (key_volume_down && volume_level > 4'd0) begin
            volume_level <= volume_level - 1'b1;
            volume_muted <= 1'b0;
        end
    end
end

function [7:0] state_frame_byte;
    input [2:0] index;
    begin
        case (index)
            3'd0: state_frame_byte = 8'h5A;
            3'd1: state_frame_byte = 8'h81 + {5'd0,frame_type};
            3'd2: state_frame_byte = (frame_type == 3'd6) ? {4'd0,frame_volume} :
                                           (frame_type == 3'd5) ? {6'd0,frame_camera_mode} :
                                           (frame_type == 2'd0) ? frame_count :
                                           (frame_type == 2'd1) ? {4'd0,frame_brightness} :
                                           (frame_type == 3'd2) ? frame_notice_flags :
                                           (frame_type == 3'd3) ? {6'd0,frame_size} : frame_music_track;
            3'd3: state_frame_byte = (frame_type == 3'd6) ? {7'd0,frame_muted} :
                                           (frame_type == 3'd5) ? {5'd0,frame_video_status} :
                                           (frame_type == 2'd0) ? frame_current :
                                           (frame_type == 2'd1) ? {4'd0,frame_contrast} :
                                           (frame_type == 3'd2) ? frame_notice_width[7:0] :
                                           (frame_type == 3'd3) ? {6'd0,frame_aspect} : frame_music_count;
            3'd4: state_frame_byte = (frame_type == 2'd0) ? frame_flags :
                                           (frame_type == 2'd1) ? {6'd0,frame_effect} :
                                           (frame_type == 3'd2) ? {6'd0,frame_notice_width[9:8]} :
                                           (frame_type == 3'd4) ? frame_music_flags : 8'd0;
            3'd5: state_frame_byte = (frame_type == 3'd0) ? frame_map[7:0] :
                                      (frame_type == 3'd4) ? frame_music_map[7:0] : 8'd0;
            3'd6: state_frame_byte = (frame_type == 3'd0) ? frame_map[15:8] :
                                      (frame_type == 3'd4) ? frame_music_map[15:8] : 8'd0;
            default: begin
                case(frame_type)
                    2'd0: state_frame_byte = 8'h5A ^ 8'h81 ^ frame_count ^ frame_current ^
                                             frame_flags ^ frame_map[7:0] ^ frame_map[15:8];
                    2'd1: state_frame_byte = 8'h5A ^ 8'h82 ^ {4'd0,frame_brightness} ^
                                             {4'd0,frame_contrast} ^ {6'd0,frame_effect};
                    3'd2: state_frame_byte = 8'h5A ^ 8'h83 ^ frame_notice_flags ^
                                              frame_notice_width[7:0] ^ {6'd0,frame_notice_width[9:8]};
                    3'd3: state_frame_byte = 8'h5A ^ 8'h84 ^ {6'd0,frame_size} ^
                                                {6'd0,frame_aspect};
                    3'd4: state_frame_byte = 8'h5A ^ 8'h85 ^ frame_music_track ^
                                                frame_music_count ^ frame_music_flags ^
                                                frame_music_map[7:0] ^ frame_music_map[15:8];
                    3'd5: state_frame_byte = 8'h5A ^ 8'h86 ^ {6'd0,frame_camera_mode} ^ {5'd0,frame_video_status};
                    default: state_frame_byte = 8'h5A ^ 8'h87 ^ {4'd0,frame_volume} ^ {7'd0,frame_muted};
                endcase
            end
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        last_count     <= 5'h1f;
        last_current   <= 4'hf;
        last_auto      <= 1'b1;
        last_scan_done <= 1'b1;
        last_effect     <= 2'b11;
        last_brightness <= 4'hf;
        last_contrast   <= 4'hf;
        last_size       <= 2'b11;
        last_aspect     <= 2'b11;
        last_music_track <= 5'h1f;
        last_music_count <= 5'h1f;
        last_playing <= 1'b0;
        last_lyric_enabled <= 1'b0;
        last_title_enabled <= 1'b0;
        last_spectrum_enabled <= 1'b0;
        last_volume <= 4'd10; last_muted <= 1'b0;
        frame_volume <= 4'd10; frame_muted <= 1'b0;
        frame_camera_mode <= 2'd0;
        frame_video_status<=0; last_video_status<=0;
        last_lyric_valid <= 1'b1;
        last_title_valid <= 1'b1;
        last_camera_mode <= 1'b1;
        status_pending <= 1'b1;
        heartbeat_count<= 32'd0;
        frame_count    <= 8'd0;
        frame_current  <= 8'd0;
        frame_flags    <= 8'd0;
        frame_map      <= 16'd0;
        frame_brightness <= 4'd9;
        frame_contrast   <= 4'd5;
        frame_effect     <= 2'd0;
        frame_size       <= 2'd0;
        frame_aspect     <= 2'd0;
        frame_music_track <= 8'd0;
        frame_music_count <= 8'd0;
        frame_music_flags <= 8'd0;
        frame_music_map <= 16'd0;
        frame_type       <= 3'd0;
        frame_notice_flags <= 8'd0;
        frame_notice_width <= 10'd0;
        frame_active   <= 1'b0;
        frame_index    <= 3'd0;
        tx_wait_busy   <= 1'b0;
        tx_start       <= 1'b0;
        tx_data        <= 8'hff;
        voice_reply_pending <= 1'b0;
        voice_reply_active  <= 1'b0;
    end else begin
        tx_start <= 1'b0;
        if (voice_valid)
            voice_reply_pending <= 1'b1;

        // Periodic report makes the link self-recovering after Bluetooth reconnects.
        if (heartbeat_count >= (CLK_FREQ_HZ - 1)) begin
            heartbeat_count <= 32'd0;
            status_pending  <= 1'b1;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;
        end

        if (tx_wait_busy && tx_busy)
            tx_wait_busy <= 1'b0;

        // Consume a pending report only when the byte transmitter is idle.
        if (status_pending && !frame_active && !tx_busy && !tx_wait_busy) begin
            frame_count   <= {3'd0, image_count};
            frame_current <= (scan_done && (image_count != 5'd0)) ?
                             ({4'd0, current_index} + 1'b1) : 8'd0;
            frame_flags   <= {6'd0, scan_done, auto_mode};
            frame_map     <= (image_count == 5'd0)  ? 16'h0000 :
                             (image_count >= 5'd16) ? 16'hffff :
                             ((16'h0001 << image_count) - 1'b1);
            frame_brightness <= brightness_level;
            frame_contrast   <= contrast_level;
            frame_effect     <= transition_effect;
            frame_size       <= image_size;
            frame_aspect     <= image_aspect;
            frame_music_track <= {3'd0,music_track_number};
            frame_music_count <= {3'd0,music_track_count};
            frame_music_flags <= {1'b0,1'b1,spectrum_enabled,title_valid,lyric_valid,title_enabled,lyric_enabled,music_playing};
            frame_music_map <= music_track_map;
            frame_volume <= volume_level; frame_muted <= volume_muted;
            // The payload and checksum must use the same snapshot even if
            // a button/Bluetooth request changes modes while bytes are sent.
            frame_camera_mode <= camera_mode;
            frame_video_status <= camera_mode==2 ? video_status : 3'd0;
            frame_notice_flags <= notice_flags;
            frame_notice_width <= notice_width;
            frame_type     <= 3'd0;
            frame_active  <= 1'b1;
            frame_index   <= 3'd0;
            status_pending<= 1'b0;
            if (voice_reply_pending) begin
                voice_reply_active  <= 1'b1;
                voice_reply_pending <= 1'b0;
            end
        end else if (frame_active && !tx_busy && !tx_wait_busy) begin
            if (frame_type == 3'd1 && frame_index == 3'd0)
                voice_reply_active <= 1'b0;
            tx_data      <= state_frame_byte(frame_index);
            tx_start     <= 1'b1;
            tx_wait_busy <= 1'b1;
            if (frame_index == 3'd7) begin
                if (frame_type < 3'd6) begin
                    frame_type  <= frame_type + 1'b1;
                    frame_index <= 3'd0;
                end else begin
                    frame_active <= 1'b0;
                end
            end else
                frame_index <= frame_index + 1'b1;
        end

        // Keep only the latest state; if changes occur while sending, send again afterwards.
        if ((image_count != last_count) || (current_index != last_current) ||
            (auto_mode != last_auto) || (scan_done != last_scan_done) ||
            (transition_effect != last_effect) || (brightness_level != last_brightness) ||
            (contrast_level != last_contrast) || (image_size != last_size) ||
            (image_aspect != last_aspect) ||
            (music_track_number != last_music_track) ||
            (music_track_count != last_music_count) ||
            (music_playing != last_playing) ||
            (lyric_enabled != last_lyric_enabled) ||
            (title_enabled != last_title_enabled) ||
            (spectrum_enabled != last_spectrum_enabled) ||
            (volume_level != last_volume) || (volume_muted != last_muted) ||
            (lyric_valid != last_lyric_valid) || (title_valid != last_title_valid) ||
            (camera_mode != last_camera_mode) ||
            (camera_mode==2 && video_status!=last_video_status)) begin
            last_count     <= image_count;
            last_current   <= current_index;
            last_auto      <= auto_mode;
            last_scan_done <= scan_done;
            last_effect     <= transition_effect;
            last_brightness <= brightness_level;
            last_contrast   <= contrast_level;
            last_size       <= image_size;
            last_aspect     <= image_aspect;
            last_music_track <= music_track_number;
            last_music_count <= music_track_count;
            last_playing <= music_playing;
            last_lyric_enabled <= lyric_enabled;
            last_title_enabled <= title_enabled;
            last_spectrum_enabled <= spectrum_enabled;
            last_volume <= volume_level; last_muted <= volume_muted;
            last_lyric_valid <= lyric_valid;
            last_title_valid <= title_valid;
            last_camera_mode <= camera_mode;
            last_video_status <= video_status;
            status_pending <= 1'b1;
        end
        if (query_pulse)
            status_pending <= 1'b1;
    end
end

endmodule

// Gesture board frame: A5 CODE ~CODE 5A. Left=03, right=04.
module gesture_uart_command #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE = 9600
)(
    input clk, rst, uart_rx,
    output reg next_valid, prev_valid
);
    wire [7:0] rx_data;
    wire rx_valid;
    reg [1:0] frame_pos;
    reg [7:0] frame_code;
    reg complement_ok;

    uart_rx_byte #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst(rst), .uart_rx(uart_rx),
        .data(rx_data), .data_valid(rx_valid)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_pos <= 2'd0;
            frame_code <= 8'd0;
            complement_ok <= 1'b0;
            next_valid <= 1'b0;
            prev_valid <= 1'b0;
        end else begin
            next_valid <= 1'b0;
            prev_valid <= 1'b0;
            if (rx_valid) begin
                case (frame_pos)
                    2'd0: if (rx_data == 8'hA5) frame_pos <= 2'd1;
                    2'd1: begin frame_code <= rx_data; frame_pos <= 2'd2; end
                    2'd2: begin
                        complement_ok <= (rx_data == ~frame_code);
                        frame_pos <= 2'd3;
                    end
                    default: begin
                        frame_pos <= (rx_data == 8'hA5) ? 2'd1 : 2'd0;
                        if (rx_data == 8'h5A && complement_ok && frame_code <= 8'h04) begin
                            next_valid <= (frame_code == 8'h04);
                            prev_valid <= (frame_code == 8'h03);
                        end
                    end
                endcase
            end
        end
    end
endmodule

// ASRPRO sends the same four-byte command frame as W02. Its UART is
// independent, so speech and Bluetooth can remain connected at once.
module voice_uart_command #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE = 9600
)(
    input clk,
    input rst,
    input uart_rx,
    output reg command_valid,
    output reg [7:0] command,
    output reg [7:0] argument
);
    wire [7:0] rx_data;
    wire rx_valid;
    reg [1:0] frame_pos;
    reg [7:0] frame_cmd, frame_arg;

    uart_rx_byte #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst(rst), .uart_rx(uart_rx),
        .data(rx_data), .data_valid(rx_valid)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_pos <= 2'd0;
            frame_cmd <= 8'd0;
            frame_arg <= 8'd0;
            command_valid <= 1'b0;
            command <= 8'd0;
            argument <= 8'd0;
        end else begin
            command_valid <= 1'b0;
            if (rx_valid) begin
                case (frame_pos)
                    2'd0: if (rx_data == 8'hA5) frame_pos <= 2'd1;
                    2'd1: if (rx_data == 8'hA5) frame_pos <= 2'd1;
                          else begin frame_cmd <= rx_data; frame_pos <= 2'd2; end
                    2'd2: if (rx_data == 8'hA5) frame_pos <= 2'd1;
                          else begin frame_arg <= rx_data; frame_pos <= 2'd3; end
                    default: begin
                        frame_pos <= (rx_data == 8'hA5 &&
                                      rx_data != (8'hA5 ^ frame_cmd ^ frame_arg)) ?
                                      2'd1 : 2'd0;
                        if (rx_data == (8'hA5 ^ frame_cmd ^ frame_arg)) begin
                            command <= frame_cmd;
                            argument <= frame_arg;
                            command_valid <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end
endmodule

module uart_rx_byte #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 9600
)(
    input            clk,
    input            rst,
    input            uart_rx,
    output reg [7:0] data,
    output reg       data_valid
);
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
localparam [1:0] RX_IDLE=2'd0, RX_START=2'd1, RX_DATA=2'd2, RX_STOP=2'd3;
reg rx_meta, rx_sync;
reg [1:0] state;
reg [15:0] clk_count;
reg [2:0] bit_index;
reg [7:0] shift_data;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;
    end else begin
        rx_meta <= uart_rx;
        rx_sync <= rx_meta;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state      <= RX_IDLE;
        clk_count  <= 16'd0;
        bit_index  <= 3'd0;
        shift_data <= 8'd0;
        data       <= 8'd0;
        data_valid <= 1'b0;
    end else begin
        data_valid <= 1'b0;
        case (state)
            RX_IDLE: begin
                clk_count <= 16'd0;
                if (!rx_sync)
                    state <= RX_START;
            end
            RX_START: begin
                if (clk_count == (CLKS_PER_BIT/2 - 1)) begin
                    clk_count <= 16'd0;
                    if (!rx_sync) begin
                        bit_index <= 3'd0;
                        state <= RX_DATA;
                    end else
                        state <= RX_IDLE;
                end else
                    clk_count <= clk_count + 1'b1;
            end
            RX_DATA: begin
                if (clk_count == (CLKS_PER_BIT - 1)) begin
                    clk_count <= 16'd0;
                    shift_data[bit_index] <= rx_sync;
                    if (bit_index == 3'd7)
                        state <= RX_STOP;
                    else
                        bit_index <= bit_index + 1'b1;
                end else
                    clk_count <= clk_count + 1'b1;
            end
            default: begin
                if (clk_count == (CLKS_PER_BIT - 1)) begin
                    clk_count <= 16'd0;
                    state <= RX_IDLE;
                    if (rx_sync) begin
                        data <= shift_data;
                        data_valid <= 1'b1;
                    end
                end else
                    clk_count <= clk_count + 1'b1;
            end
        endcase
    end
end
endmodule

module uart_tx_byte #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 9600
)(
    input            clk,
    input            rst,
    input            start,
    input      [7:0] data,
    output reg       uart_tx,
    output reg       busy
);
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
reg [15:0] clk_count;
reg [3:0] bit_index;
reg [7:0] shift_data;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        uart_tx   <= 1'b1;
        busy      <= 1'b0;
        clk_count <= 16'd0;
        bit_index <= 4'd0;
        shift_data<= 8'd0;
    end else if (!busy) begin
        uart_tx   <= 1'b1;
        clk_count <= 16'd0;
        bit_index <= 4'd0;
        if (start) begin
            shift_data <= data;
            uart_tx    <= 1'b0;
            busy       <= 1'b1;
        end
    end else if (clk_count == (CLKS_PER_BIT - 1)) begin
        clk_count <= 16'd0;
        if (bit_index < 4'd8) begin
            uart_tx   <= shift_data[bit_index];
            bit_index <= bit_index + 1'b1;
        end else if (bit_index == 4'd8) begin
            uart_tx   <= 1'b1;
            bit_index <= 4'd9;
        end else begin
            busy    <= 1'b0;
            uart_tx <= 1'b1;
        end
    end else begin
        clk_count <= clk_count + 1'b1;
    end
end
endmodule
