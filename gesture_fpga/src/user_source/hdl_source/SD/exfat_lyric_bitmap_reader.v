// Timed LYR2 reader for the files produced by tools/prepare_card.py.
//
// Layout (file size is always a multiple of 512):
//   offset 0    32-byte header (LYR1, version 2, 512x16, 500 ms, frames,
//               duration, data_offset = 1024)
//   offset 32..511   reserved
//   offset 512  512-byte vertical title bitmap (16 px x 256 rows, MSB first)
//   offset 1024 lyric frame 0, then one 1024-byte frame every 500 ms
//
// Lyrics advance on PCM frame ticks (48 kHz), so they stop when audio pauses
// and restart together with the WAV stream.  Each new lyric frame is written
// into the inactive bank and shown only after the whole frame has arrived.
module exfat_lyric_bitmap_reader(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        restart,
    input  wire [31:0] first_lba,
    input  wire [31:0] file_bytes,
    input  wire        no_fat_chain,
    input  wire        pcm_frame_tick,
    input  wire        video_clk,
    input  wire [10:0] pixel_x,
    input  wire [9:0]  pixel_y,
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_data,
    input  wire        sd_data_valid,
    input  wire        sd_read_end,
    output wire        pixel_on,
    output wire        title_pixel_on,
    output wire        frame_valid,       // synchronized to video_clk
    output wire        title_valid,       // synchronized to video_clk
    output reg         lyric_error
);
    localparam S_IDLE  = 2'd0;
    localparam S_HDR   = 2'd1;
    localparam S_TITLE = 2'd2;
    localparam S_READ  = 2'd3;

    localparam [31:0] FRAME_OFFSET = 32'd1024;
    localparam [31:0] FRAME_BYTES  = 32'd1024;
    localparam [31:0] TITLE_OFFSET = 32'd512;
    localparam [14:0] PCM_TICKS_PER_FRAME = 15'd24000;

    reg [1:0]  state;
    reg [31:0] frame_index;
    reg [31:0] frame_count;
    reg [31:0] track_lba;
    reg [14:0] tick_count;
    reg        load_pending;

    // Header capture.
    reg [31:0] hdr_magic;
    reg [31:0] hdr_frames;
    reg [31:0] hdr_data_offset;
    reg [7:0]  hdr_version;
    reg [15:0] hdr_width, hdr_height, hdr_interval;
    reg [8:0]  hdr_index;

    // Frame read bookkeeping.
    reg [31:0] target_offset;
    reg [31:0] sector_offset;
    reg [9:0]  sector_byte_index;
    reg [10:0] bitmap_bytes_written;

    // Two lyric banks in one 2048x8 array (bank bit selects the half).
    // A single array with an address bit lets the tool infer two BRAM9Ks;
    // muxing two separate arrays makes it fall back to distributed RAM.
    reg [7:0]  bitmap [0:2047];
    reg        write_bank;
    reg        display_bank;
    reg        frame_valid_i;

    // Title bitmap (one sector) and its write index.
    reg [7:0]  title_bitmap [0:511];
    reg [8:0]  title_write_index;
    reg        title_valid_i;

    // Video-domain synchronization.
    reg [1:0]  frame_valid_sync;
    reg [1:0]  title_valid_sync;
    reg [1:0]  bank_sync;
    wire       frame_valid_v = frame_valid_sync[1];
    wire       title_valid_v = title_valid_sync[1];
    wire       display_bank_v = bank_sync[1];

    wire [31:0] absolute_offset = sector_offset + sector_byte_index;
    // Frame offsets are 1 KiB aligned, so the low ten bits of the absolute
    // offset are the bitmap index inside the current frame.
    wire [9:0]  bitmap_write_addr = absolute_offset[9:0];

    // ---- lyric strip lookup: x 64..575, y 2..17 -------------------------
    wire        lyric_in = (pixel_x >= 11'd64) && (pixel_x < 11'd576) &&
                           (pixel_y >= 10'd2) && (pixel_y < 10'd18);
    wire [10:0] lyric_x = pixel_x - 11'd64;
    wire [9:0]  lyric_y = pixel_y - 10'd2;
    wire [9:0]  lyric_addr = lyric_in ?
                             ({lyric_y[3:0], 6'd0} + lyric_x[9:3]) : 10'd0;

    // ---- title column lookup: x 616..631, y 112..367 --------------------
    wire        title_in = (pixel_x >= 11'd616) && (pixel_x < 11'd632) &&
                           (pixel_y >= 10'd112) && (pixel_y < 10'd368);
    wire [10:0] title_x = pixel_x - 11'd616;
    wire [9:0]  title_y = pixel_y - 10'd112;
    wire [8:0]  title_addr = title_in ?
                             ({title_y[7:0], 1'b0} + title_x[3]) : 9'd0;

    reg [7:0] pixel_byte;
    reg [2:0] pixel_bit_q;
    reg       lyric_in_q;
    reg [7:0] title_byte;
    reg [2:0] title_bit_q;
    reg       title_in_q;

    // The registered BRAM read means the data available in cycle t belongs to
    // the address presented in t-1; the valid/bit selectors are delayed with
    // it so text stays crisp (one-pixel offset is not visible).
    always @(posedge video_clk) begin
        pixel_byte  <= bitmap[{display_bank_v, lyric_addr}];
        pixel_bit_q <= lyric_x[2:0];
        lyric_in_q  <= lyric_in;
        title_byte  <= title_bitmap[title_addr];
        title_bit_q <= title_x[2:0];
        title_in_q  <= title_in;
    end

    assign pixel_on       = frame_valid_v && lyric_in_q &&
                            pixel_byte[3'd7 - pixel_bit_q];
    assign title_pixel_on = title_valid_v && title_in_q &&
                            title_byte[3'd7 - title_bit_q];
    assign frame_valid    = frame_valid_v;
    assign title_valid    = title_valid_v;

    task start_frame_read;
        input [31:0] offset;
        begin
            target_offset <= offset;
            sector_offset <= {offset[31:9], 9'd0};
            sd_sec_read_addr <= track_lba + (offset >> 9);
            sector_byte_index <= 10'd0;
            bitmap_bytes_written <= 11'd0;
            load_pending <= 1'b0;
            sd_sec_read <= 1'b1;
            state <= S_READ;
        end
    endtask

    // Synchronize control into the domain that actually reads the bitmaps.
    // RAM payload is published only after the inactive bank is complete.
    always @(posedge video_clk or posedge rst) begin
        if (rst) begin
            frame_valid_sync <= 2'b00;
            title_valid_sync <= 2'b00;
            bank_sync <= 2'b00;
        end else begin
            frame_valid_sync <= {frame_valid_sync[0], frame_valid_i};
            title_valid_sync <= {title_valid_sync[0], title_valid_i};
            bank_sync <= {bank_sync[0], display_bank};
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            frame_index <= 32'd0;
            frame_count <= 32'd0;
            track_lba <= 32'd0;
            tick_count <= 15'd0;
            load_pending <= 1'b0;
            hdr_magic <= 32'd0;
            hdr_frames <= 32'd0;
            hdr_data_offset <= 32'd0;
            hdr_version <= 8'd0;
            hdr_width <= 16'd0;
            hdr_height <= 16'd0;
            hdr_interval <= 16'd0;
            hdr_index <= 9'd0;
            target_offset <= 32'd0;
            sector_offset <= 32'd0;
            sector_byte_index <= 10'd0;
            bitmap_bytes_written <= 11'd0;
            write_bank <= 1'b0;
            display_bank <= 1'b0;
            frame_valid_i <= 1'b0;
            title_write_index <= 9'd0;
            title_valid_i <= 1'b0;
            sd_sec_read <= 1'b0;
            sd_sec_read_addr <= 32'd0;
            lyric_error <= 1'b0;
        end else begin
            if (restart) begin
                state <= S_IDLE;
                sd_sec_read <= 1'b0;
                frame_index <= 32'd0;
                frame_count <= 32'd0;
                tick_count <= 15'd0;
                load_pending <= 1'b0;
                frame_valid_i <= 1'b0;
                title_valid_i <= 1'b0;
                write_bank <= 1'b0;
                display_bank <= 1'b0;
                lyric_error <= 1'b0;
            end else begin
                case (state)
                    S_IDLE: begin
                        sd_sec_read <= 1'b0;
                        if (start) begin
                            track_lba <= first_lba;
                            frame_index <= 32'd0;
                            frame_count <= 32'd0;
                            tick_count <= 15'd0;
                            load_pending <= 1'b0;
                            frame_valid_i <= 1'b0;
                            title_valid_i <= 1'b0;
                            write_bank <= 1'b0;
                            display_bank <= 1'b0;
                            lyric_error <= 1'b0;
                            hdr_magic <= 32'd0;
                            hdr_frames <= 32'd0;
                            hdr_data_offset <= 32'd0;
                            hdr_version <= 8'd0;
                            hdr_width <= 16'd0;
                            hdr_height <= 16'd0;
                            hdr_interval <= 16'd0;
                            hdr_index <= 9'd0;
                            sd_sec_read_addr <= first_lba;
                            sd_sec_read <= 1'b1;
                            state <= S_HDR;
                        end else if (load_pending) begin
                            start_frame_read(FRAME_OFFSET +
                                             (frame_index << 10));
                        end
                    end

                    S_HDR: begin
                        sd_sec_read <= 1'b1;
                        if (sd_data_valid) begin
                            hdr_index <= hdr_index + 1'b1;
                            case (hdr_index)
                                9'd0: hdr_magic[7:0]   <= sd_data;
                                9'd1: hdr_magic[15:8]  <= sd_data;
                                9'd2: hdr_magic[23:16] <= sd_data;
                                9'd3: hdr_magic[31:24] <= sd_data;
                                9'd4: hdr_version <= sd_data;
                                9'd6: hdr_width[7:0] <= sd_data;
                                9'd7: hdr_width[15:8] <= sd_data;
                                9'd8: hdr_height[7:0] <= sd_data;
                                9'd9: hdr_height[15:8] <= sd_data;
                                9'd10: hdr_interval[7:0] <= sd_data;
                                9'd11: hdr_interval[15:8] <= sd_data;
                                9'd12: hdr_frames[7:0]   <= sd_data;
                                9'd13: hdr_frames[15:8]  <= sd_data;
                                9'd14: hdr_frames[23:16] <= sd_data;
                                9'd15: hdr_frames[31:24] <= sd_data;
                                9'd20: hdr_data_offset[7:0]   <= sd_data;
                                9'd21: hdr_data_offset[15:8]  <= sd_data;
                                9'd22: hdr_data_offset[23:16] <= sd_data;
                                9'd23: hdr_data_offset[31:24] <= sd_data;
                                default: ;
                            endcase
                        end
                        if (sd_read_end) begin
                            sd_sec_read <= 1'b0;
                            if (no_fat_chain && (hdr_magic == 32'h3152594c) &&
                                (hdr_version == 8'd2) &&
                                (hdr_width == 16'd512) && (hdr_height == 16'd16) &&
                                (hdr_interval == 16'd500) &&
                                (hdr_data_offset == FRAME_OFFSET) &&
                                (hdr_frames != 32'd0) &&
                                ((file_bytes & 32'h1ff) == 32'd0) &&
                                (file_bytes >= FRAME_OFFSET) &&
                                (hdr_frames <= ((file_bytes - FRAME_OFFSET) >> 10))) begin
                                frame_count <= hdr_frames;
                                title_write_index <= 9'd0;
                                sd_sec_read_addr <= track_lba +
                                                    (TITLE_OFFSET >> 9);
                                sd_sec_read <= 1'b1;
                                state <= S_TITLE;
                            end else begin
                                lyric_error <= 1'b1;
                                state <= S_IDLE;
                            end
                        end
                    end

                    S_TITLE: begin
                        sd_sec_read <= 1'b1;
                        if (sd_data_valid) begin
                            title_bitmap[title_write_index[8:0]] <= sd_data;
                            title_write_index <= title_write_index + 1'b1;
                        end
                        if (sd_read_end) begin
                            sd_sec_read <= 1'b0;
                            title_valid_i <= 1'b1;
                            start_frame_read(FRAME_OFFSET);
                        end
                    end

                    S_READ: begin
                        sd_sec_read <= 1'b1;
                        if (sd_data_valid) begin
                            sector_byte_index <= sector_byte_index + 1'b1;
                            if ((absolute_offset >= target_offset) &&
                                (absolute_offset < target_offset + FRAME_BYTES)) begin
                                bitmap[{write_bank, bitmap_write_addr}] <= sd_data;
                                bitmap_bytes_written <= bitmap_bytes_written + 1'b1;
                            end
                        end
                        if (sd_read_end) begin
                            sd_sec_read <= 1'b0;
                            sector_byte_index <= 10'd0;
                            if (sector_offset + 32'd512 <
                                target_offset + FRAME_BYTES) begin
                                sector_offset <= sector_offset + 32'd512;
                                sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                                sd_sec_read <= 1'b1;
                            end else begin
                                if (bitmap_bytes_written >= 11'd1023) begin
                                    display_bank <= write_bank;
                                    write_bank <= ~write_bank;
                                    frame_valid_i <= 1'b1;
                                end
                                state <= S_IDLE;
                            end
                        end
                    end

                    default: state <= S_IDLE;
                endcase

                // 24 000 PCM frames = 500 ms at 48 kHz.  Count even while the
                // first frame is still being loaded: the WAV may already be
                // playing, and those ticks belong to the song timeline.
                if (pcm_frame_tick && (frame_count != 32'd0)) begin
                    if (tick_count == PCM_TICKS_PER_FRAME - 1'b1) begin
                        tick_count <= 15'd0;
                        if ((frame_index + 32'd1) < frame_count) begin
                            frame_index <= frame_index + 32'd1;
                            load_pending <= 1'b1;
                        end
                    end else begin
                        tick_count <= tick_count + 15'd1;
                    end
                end
            end
        end
    end
endmodule
