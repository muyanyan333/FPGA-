// MVI1: bottom-up 320x240 RGB565LE, 8 fps; 00.wav supplies 48 kHz pacing.
// Follow exFAT FAT chains as well as contiguous files; never abort a sector.
// The first four file bytes contain "MVI1" for discovery; those two pixels
// are rendered black. Files are generated contiguously on the exFAT card.
module exfat_raw_video_reader(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        restart,
    input  wire        enable,
    input  wire        rgb332_mode,
    input wire indexed_mode, dynamic_mode, audio_finished,
    input  wire [31:0] first_lba, first_cluster,
    input wire [31:0] volume_lba, fat_offset, heap_offset,
    input wire [7:0] spc_shift,
    input wire allow_frame,
    output reg frame_present,
    input  wire [31:0] file_bytes,
    input  wire        no_fat_chain,
    input  wire        pcm_frame_tick,
    input  wire        write_req_ack,
    input  wire        scale_ready,
    input  wire        scale_done,
    // Pulse after the complete scaled frame has reached SDRAM.
    input  wire        frame_committed,
    output reg         frame_start,
    output reg         scale_go,
    output reg         write_req,
    output reg         pixel_valid,
    output reg  [23:0] pixel_data,
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_data,
    input  wire        sd_data_valid,
    input  wire        sd_read_end,
    output reg         active,
    output reg         video_error,
    output wire pacing_wait,
    output wire [2:0]  startup_stage
);
    localparam [3:0] ST_IDLE      = 4'd0;
    localparam [3:0] ST_REQ       = 4'd1;
    localparam [3:0] ST_ACK_LOW   = 4'd2;
    localparam [3:0] ST_SCALE     = 4'd3;
    localparam [3:0] ST_READ      = 4'd4;
    localparam [3:0] ST_READ_GAP  = 4'd5;
    localparam [3:0] ST_DONE      = 4'd6;
    localparam [3:0] ST_FAT_REQ=4'd7, ST_FAT_READ=4'd8, ST_ADVANCE=4'd9, ST_PRESENT_GAP=4'd10;
    // MVI1 stays compatible with the original RGB565/8 fps files.
    // MVI2 halves card traffic, retaining 320x240 at 20 fps in RGB332.
    wire audio_ended = audio_finished === 1'b1;
    wire indexed_video = indexed_mode === 1'b1;
    wire dynamic_video = dynamic_mode === 1'b1;
    wire frame_has_header = dynamic_video || first_indexed_frame;
    reg [15:0] dynamic_ticks;
    reg first_indexed_frame; // Header presence changes once per frame, not per byte count.
    wire compact_video = rgb332_mode === 1'b1;
    wire [31:0] FRAME_BYTES = compact_video ? (frame_has_header ? 32'd77824 : 32'd76800) : 32'd153600;
    wire [31:0] START_FRAME_BYTES = compact_video ? (indexed_video ? 32'd77824 : 32'd76800) : 32'd153600;
    wire [15:0] TICKS_PER_FRAME = dynamic_video ? dynamic_ticks : (compact_video ? 16'd2400 : 16'd6000);
    wire [8:0] LAST_SECTOR = compact_video ? (frame_has_header ? 9'd151 : 9'd149) : 9'd299;

    reg [3:0] state, after_sector_state;
    reg [31:0] current_cluster, sector_in_cluster, next_cluster;
    reg [9:0] fat_index;
    reg [8:0] fat_offset_byte;
    reg track_contiguous;
    function [31:0] cluster_lba;
        input [31:0] cluster;
        begin cluster_lba=volume_lba+heap_offset+((cluster-32'd2)<<spc_shift); end
    endfunction
    reg [15:0] tick_count;
    reg        frame_due;
    assign pacing_wait = active && frame_due && !audio_ended;
    reg [31:0] current_lba;
    reg [31:0] bytes_used;
    reg [8:0]  frame_sector;
    reg [31:0] total_byte_count;
    reg        byte_half;
    reg [7:0]  low_byte;
    // One synchronous palette BRAM; only palette load writes it.
    reg [23:0] palette [0:255];
    reg [7:0] palette_index, palette_r, palette_g;
    reg [1:0] palette_phase;
    reg [23:0] palette_pixel;
    reg indexed_pending;
    wire palette_payload=total_byte_count>=4 && total_byte_count<772;
    always @(posedge clk) begin
        if (state==ST_READ && sd_data_valid && indexed_video) begin
            if (palette_payload && palette_phase==2)
                palette[palette_index]<={palette_r,palette_g,sd_data};
            if (total_byte_count>=1024) palette_pixel<=palette[sd_data];
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin palette_index<=0;palette_phase<=0;palette_r<=0;palette_g<=0;indexed_pending<=0;dynamic_ticks<=2400;end
        else begin
            // Read pacing from the first per-frame header. Invalid values
            // retain the conservative 20 fps fallback; subsequent frames
            // cannot change the soundtrack's time base mid-playback.
            if(start) dynamic_ticks<=2400;
            else if(dynamic_video && bytes_used==0 && state==ST_READ && sd_data_valid && total_byte_count==772)
                case(sd_data)
                    24:dynamic_ticks<=2000;25:dynamic_ticks<=1920;
                    30:dynamic_ticks<=1600;default:dynamic_ticks<=2400;
                endcase
            indexed_pending<=state==ST_READ && sd_data_valid && indexed_video && total_byte_count>=1024;
            if(start || (dynamic_video && frame_start)) begin palette_index<=0;palette_phase<=0;end
            else if(state==ST_READ && sd_data_valid && indexed_video && palette_payload) begin
                case(palette_phase)
                    0:begin palette_r<=sd_data;palette_phase<=1;end
                    1:begin palette_g<=sd_data;palette_phase<=2;end
                    2:begin palette_index<=palette_index+1'b1;palette_phase<=0;end
                endcase
            end
        end
    end
    reg        scale_done_seen;
    reg        frame_commit_seen;
    reg [31:0] track_file_bytes;
    reg        restart_pending;
    reg [31:0] restart_first_lba;
    reg [31:0] restart_file_bytes;
    reg        restart_no_fat_chain;
    // Visible first-frame diagnostics; no timeout bypasses a missing commit.
    assign startup_stage = state==ST_REQ ? 3'd1 :
        (state==ST_ACK_LOW || state==ST_SCALE) ? 3'd2 :
        (state==ST_READ || state==ST_READ_GAP) ? 3'd3 :
        (state==ST_FAT_REQ || state==ST_FAT_READ || state==ST_ADVANCE) ? 3'd4 :
        state==ST_DONE ? ((scale_done_seen || scale_done) ? 3'd6 : 3'd5) : 3'd0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            after_sector_state<=ST_IDLE; current_cluster<=0; sector_in_cluster<=0;
            next_cluster<=0; fat_index<=0; fat_offset_byte<=0; track_contiguous<=0;
            tick_count <= 16'd0;
            frame_due <= 1'b0;
            current_lba <= 32'd0;
            bytes_used <= 32'd0;first_indexed_frame<=1'b0;
            frame_sector <= 9'd0;
            total_byte_count <= 32'd0;
            byte_half <= 1'b0;
            low_byte <= 8'd0;
            scale_done_seen <= 1'b0;
            frame_commit_seen <= 1'b0;
            track_file_bytes <= 32'd0;
            restart_pending <= 1'b0;
            restart_first_lba <= 32'd0;
            restart_file_bytes <= 32'd0;
            restart_no_fat_chain <= 1'b0;
            frame_present <= 1'b0;
            frame_start <= 1'b0;
            scale_go <= 1'b0;
            write_req <= 1'b0;
            pixel_valid <= 1'b0;
            pixel_data <= 24'd0;
            sd_sec_read <= 1'b0;
            sd_sec_read_addr <= 32'd0;
            active <= 1'b0;
            video_error <= 1'b0;
        end else begin
            frame_present <= 1'b0;
            frame_start <= 1'b0;
            scale_go <= 1'b0;
            pixel_valid <= indexed_pending;
            if(indexed_pending) pixel_data<=palette_pixel;

            // The scaler and SDRAM writer finish in different clock domains
            // and either indication may arrive first, so retain both events.
            if ((state != ST_IDLE) && scale_done)
                scale_done_seen <= 1'b1;
            if ((state != ST_IDLE) && frame_committed)
                frame_commit_seen <= 1'b1;

            if (!enable) begin
                state <= ST_IDLE;
                tick_count <= 16'd0;
                frame_due <= 1'b0;
                write_req <= 1'b0;
                sd_sec_read <= 1'b0;
                active <= 1'b0;
                scale_done_seen <= 1'b0;
                frame_commit_seen <= 1'b0;
                track_file_bytes <= 32'd0;
                restart_pending <= 1'b0;
            end else if (start || (restart && (state == ST_IDLE))) begin
                state <= ST_IDLE;
                tick_count <= 16'd0;
                frame_due <= 1'b1;
                current_lba <= first_lba;
                current_cluster<=first_cluster; sector_in_cluster<=0; track_contiguous<=no_fat_chain;
                bytes_used <= 32'd0;first_indexed_frame<=indexed_video;
                total_byte_count <= 32'd0;
                byte_half <= 1'b0;
                scale_done_seen <= 1'b0;
                frame_commit_seen <= 1'b0;
                track_file_bytes <= file_bytes;
                restart_pending <= 1'b0;
                write_req <= 1'b0;
                sd_sec_read <= 1'b0;
                active <= (file_bytes >= START_FRAME_BYTES) && first_cluster>=2;
                video_error <= (file_bytes < START_FRAME_BYTES) || first_cluster<2;
            end else begin
                // A track change must not abort a frame that the SDRAM writer
                // has already accepted. Save the new metadata and apply it
                // only after the current frame is fully committed.
                if (restart) begin
                    restart_pending <= 1'b1;
                    restart_first_lba <= first_lba;
                    restart_file_bytes <= file_bytes;
                    restart_no_fat_chain <= no_fat_chain;
                end
                if (pcm_frame_tick && active) begin
                    if (tick_count == TICKS_PER_FRAME - 1'b1) begin
                        tick_count <= 16'd0;
                        frame_due <= 1'b1;
                    end else
                        tick_count <= tick_count + 1'b1;
                end

                case (state)
                    ST_IDLE: if (active && allow_frame &&
                                 (bytes_used + FRAME_BYTES <= track_file_bytes)) begin
                        frame_start <= 1'b1;
                        write_req <= 1'b1;
                        frame_sector <= 9'd0;
                        if(dynamic_video) total_byte_count<=0;
                        byte_half <= 1'b0;
                        scale_done_seen <= 1'b0;
                        frame_commit_seen <= 1'b0;
                        state <= ST_REQ;
                    end
                    ST_REQ: if (write_req_ack) begin
                        write_req <= 1'b0;
                        state <= ST_ACK_LOW;
                    end
                    ST_ACK_LOW: if (!write_req_ack) begin
                        scale_go <= 1'b1;
                        state <= ST_SCALE;
                    end
                    ST_SCALE: if (scale_ready) begin
                        sd_sec_read_addr <= current_lba;
                        sd_sec_read <= 1'b1;
                        state <= ST_READ;
                    end
                    ST_READ: begin
                        if (sd_data_valid) begin
                            total_byte_count <= total_byte_count + 1'b1;
                            if (indexed_video) begin
                                // Palette/pixel BRAM pipeline runs above.
                            end else if (compact_video) begin
                                pixel_valid <= 1'b1;
                                pixel_data <= total_byte_count < 4 ? 24'd0 :
                                    {sd_data[7:5],sd_data[7:5],sd_data[7:6],
                                     sd_data[4:2],sd_data[4:2],sd_data[4:3],
                                     sd_data[1:0],sd_data[1:0],sd_data[1:0],sd_data[1:0]};
                            end else if (!byte_half) begin
                                low_byte <= sd_data;
                                byte_half <= 1'b1;
                            end else begin
                                byte_half <= 1'b0;
                                pixel_valid <= 1'b1;
                                if (total_byte_count < 32'd4)
                                    pixel_data <= 24'd0;
                                else
                                    pixel_data <= {sd_data[7:3],sd_data[7:5],
                                                   sd_data[3:0],low_byte[7:5],sd_data[2:1],
                                                   low_byte[4:0],low_byte[4:2]};
                            end
                        end
                        if (sd_read_end) begin
                            sd_sec_read <= 1'b0;
                            after_sector_state <= frame_sector==LAST_SECTOR ? ST_DONE : ST_READ_GAP;
                            if (frame_sector==LAST_SECTOR) begin
                                bytes_used<=bytes_used+FRAME_BYTES;first_indexed_frame<=0;
                            end
                            else frame_sector<=frame_sector+1'b1;
                            if (sector_in_cluster+1 < (32'd1<<spc_shift)) begin
                                sector_in_cluster<=sector_in_cluster+1'b1;
                                current_lba<=current_lba+1'b1;
                                state<=frame_sector==LAST_SECTOR ? ST_DONE : ST_READ_GAP;
                            end else if (track_contiguous) begin
                                current_cluster<=current_cluster+1'b1;
                                sector_in_cluster<=0; current_lba<=current_lba+1'b1;
                                state<=frame_sector==LAST_SECTOR ? ST_DONE : ST_READ_GAP;
                            end else if (frame_sector==LAST_SECTOR && bytes_used+FRAME_BYTES>=track_file_bytes) begin
                                state<=ST_DONE;
                            end else begin
                                state<=ST_FAT_REQ;
                            end
                        end
                    end
                    ST_READ_GAP: begin
                        sd_sec_read_addr<=current_lba;
                        sd_sec_read <= 1'b1;
                        state <= ST_READ;
                    end
                    ST_FAT_REQ: begin
                        sd_sec_read_addr<=volume_lba+fat_offset+(current_cluster>>7);
                        fat_offset_byte<={current_cluster[6:0],2'b00};
                        fat_index<=0; next_cluster<=0; sd_sec_read<=1; state<=ST_FAT_READ;
                    end
                    ST_FAT_READ: begin
                        if (sd_data_valid) begin
                            fat_index<=fat_index+1'b1;
                            if (fat_index=={1'b0,fat_offset_byte}) next_cluster[7:0]<=sd_data;
                            if (fat_index=={1'b0,fat_offset_byte}+1) next_cluster[15:8]<=sd_data;
                            if (fat_index=={1'b0,fat_offset_byte}+2) next_cluster[23:16]<=sd_data;
                            if (fat_index=={1'b0,fat_offset_byte}+3) next_cluster[31:24]<=sd_data;
                        end
                        if (sd_read_end) begin sd_sec_read<=0; state<=ST_ADVANCE; end
                    end
                    ST_ADVANCE: begin
                        if (next_cluster<2 || next_cluster>=32'hfffffff8) begin
                            active<=0; video_error<=1; state<=ST_IDLE;
                        end else begin
                            current_cluster<=next_cluster; sector_in_cluster<=0;
                            current_lba<=cluster_lba(next_cluster); state<=after_sector_state;
                        end
                    end
                    ST_DONE: if ((frame_due || audio_ended) && (scale_done_seen || scale_done) &&
                                (frame_commit_seen || frame_committed)) begin
                        frame_present<=1'b1; frame_due<=1'b0;
                        scale_done_seen <= 1'b0;
                        frame_commit_seen <= 1'b0;
                        if (restart_pending || restart) begin
                            current_lba <= restart ? first_lba : restart_first_lba;
                            track_file_bytes <= restart ? file_bytes : restart_file_bytes;
                            bytes_used <= 32'd0;first_indexed_frame<=indexed_video;
                            total_byte_count <= 32'd0;
                            tick_count <= 16'd0;
                            frame_due <= 1'b1;
                            active <= restart ?
                                ((file_bytes >= START_FRAME_BYTES) && first_cluster>=2) :
                                ((restart_file_bytes >= START_FRAME_BYTES) && restart_no_fat_chain);
                            video_error <= restart ?
                                ((file_bytes < START_FRAME_BYTES) || first_cluster<2) :
                                ((restart_file_bytes < START_FRAME_BYTES) || !restart_no_fat_chain);
                            restart_pending <= 1'b0;
                        end else if (bytes_used >= track_file_bytes) begin
                            active <= 1'b0;
                        end
                        state <= ST_PRESENT_GAP;
                    end
                    ST_PRESENT_GAP: state<=ST_IDLE;
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
