// exFAT directory based BMP reader. Deleted data in unused sectors is ignored.
module bmp_read(
    input clk,
    input rst,
    output ready,
    input scan_start,
    input [31:0] scan_start_sector,
    input [31:0] scan_max_sector,
    input [4:0] scan_target_count,
    output reg scan_done,
    output reg scan_found_valid,
    output reg [31:0] scan_found_sector,
    output reg [4:0] scan_found_total,
    output reg wav_found,
    output reg [31:0] wav_first_lba,
    output reg [31:0] wav_first_cluster,
    output reg wav_no_fat_chain,
    output reg [31:0] wav_file_bytes,
    output reg wav_item_valid,
    output reg [31:0] wav_item_lba,
    output reg [31:0] wav_item_cluster,
    output reg wav_item_no_fat_chain,
    output reg [31:0] wav_item_file_bytes,
    output reg [4:0]  wav_item_track_id,
    output reg lyr_item_valid,
    output reg [31:0] lyr_item_lba,
    output reg [31:0] lyr_item_cluster,
    output reg lyr_item_no_fat_chain,
    output reg [31:0] lyr_item_file_bytes,
    output reg [7:0]  lyr_item_track_id,
    output reg mvi_item_valid,
    output reg mvi_item_rgb332,
    output reg mvi_item_indexed,
    output reg mvi_item_dynamic,
    output reg [31:0] mvi_item_lba,
    output reg [31:0] mvi_item_cluster,
    output reg mvi_item_no_fat_chain,
    output reg [31:0] mvi_item_file_bytes,
    output [31:0] fs_volume_lba,
    output [31:0] fs_fat_offset,
    output [31:0] fs_heap_offset,
    output [7:0] fs_spc_shift,
    input load_start,
    input [31:0] load_sector,
    input sd_init_done,
    output reg [3:0] state_code,
    input [15:0] bmp_width,
    input [15:0] bmp_height,
    output reg bmp_load_begin,
    output [15:0] bmp_src_width,
    output [15:0] bmp_src_height,
    output scale_go,
    input scale_ready,
    output reg write_req,
    input write_req_ack,
    output reg sd_sec_read,
    output reg [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid,
    input sd_sec_read_end,
    output reg bmp_data_wr_en,
    output reg [23:0] bmp_data
);

localparam ST_IDLE      = 4'd0;
localparam ST_BOOT0     = 4'd1;
localparam ST_VBR       = 4'd2;
localparam ST_DIR       = 4'd3;
localparam ST_VALIDATE  = 4'd4;
localparam ST_LOAD_HDR  = 4'd5;
localparam ST_LOAD_WAIT = 4'd6;
localparam ST_LOAD_DATA = 4'd7;
localparam ST_FAT_READ  = 4'd8;
localparam ST_LOAD_MATCH = 4'd9;
localparam ST_SCALE_WAIT = 4'd10;
localparam ST_DIR_PREP   = 4'd11;
localparam ST_DIR_ADDR   = 4'd12;
localparam ST_VALID_PREP = 4'd13;
localparam ST_VALID_ADDR = 4'd14;
localparam ST_LOAD_CALC  = 4'd15;
localparam ST_LOAD_CLUSTER_PREP = 5'd16;
localparam ST_LOAD_CLUSTER_ADDR = 5'd17;
localparam ST_VALID_META = 5'd18;
localparam ST_LOAD_META  = 5'd19;
localparam ST_VALID_READ = 5'd20;
localparam ST_LOAD_READ  = 5'd21;

reg [4:0] state;
reg [9:0] rd_cnt;

reg        exfat_name_match;
reg [31:0] partition_lba;
reg [31:0] volume_lba;
reg [31:0] cluster_heap_offset;
reg [31:0] fat_offset;
reg [31:0] root_dir_cluster;
reg [7:0]  bytes_per_sector_shift;
reg [7:0]  sectors_per_cluster_shift;

reg [31:0] dir_cluster;
reg [31:0] dir_sector_index;
reg        dir_end_seen;
reg [7:0]  dir_entry_type;
reg        primary_pending;
reg        primary_is_dir;
reg [31:0] stream_first_cluster;
reg [31:0] stream_data_length;
reg        stream_no_fat_chain;
// {from_child,no_fat_chain,length[29:0],first_lba}; media assets are <1 GiB.
// 当前 TF 卡共 43 个文件，48 项容量足够，同时缩小大型可变索引选择器以避免 HX4S20 布线溢出。
// Synchronous block RAM avoids a 48-way 64-bit mux and thousands of flops.
// The table is valid only below candidate_count; resetting RAM is unnecessary.
(* ram_style = "block" *) reg [63:0] candidate_meta [0:47]; /* fehdl force_ram=1, ram_style="bram" */
reg [63:0] candidate_meta_read;
reg [4:0]  candidate_track [0:47];
reg [7:0]  name_char0, name_char1;
reg        candidate_recorded;
reg [6:0]  candidate_count;
reg [6:0]  validate_index;
reg [31:0] child_dir_cluster [0:7];
reg [3:0]  child_dir_count;
reg [3:0]  child_dir_index;
reg        scanning_child_dir;
reg [31:0] next_dir_cluster;
(* keep = "true", syn_preserve = 1 *) reg [63:0] candidate_meta_latched;
(* keep = "true", syn_preserve = 1 *) reg [31:0] candidate_lba_latched;
reg [31:0] candidate_cluster_latched;
(* keep = "true", syn_preserve = 1 *) reg [31:0] load_fs_base;
reg [31:0] load_cluster_target;
reg [31:0] load_cluster_next_lba;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] riff_signature;
reg [31:0] wave_signature;
reg [7:0]  lyr_track_id_raw;   // LYR2 header byte 24: original track number
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [15:0] planes;
reg [31:0] compression;
reg [31:0] load_sector_latched;
reg [31:0] load_current_cluster;
reg [31:0] load_sector_in_cluster;
reg        load_no_fat_chain;
reg [31:0] fat_next_cluster;
reg [8:0]  fat_entry_byte_offset;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;
reg [15:0] bmp_row_byte_count;
reg [10:0] bmp_row_count;
reg wrack_s0, wrack_s1;

wire header_match;
wire bmp_data_valid;
wire bmp_pixel_byte_valid;
wire [15:0] bmp_row_bytes;
wire [15:0] bmp_row_stride;
reg [31:0] cluster_last_sector;
wire unused_scan_limits;

assign ready = (state == ST_IDLE);
assign header_match = (header_0 == "B") && (header_1 == "M") &&
                      (width[31:16] == 16'd0) &&
                      (height[31:16] == 16'd0) &&
                      (width >= 32'd320) && (width <= 32'd1920) &&
                      (height >= 32'd240) && (height <= 32'd1080) &&
                      (planes == 16'd1) && (bit_count == 16'd24) &&
                      (compression == 32'd0) && (pixel_offset >= 32'd54) &&
                      (pixel_offset < file_len);
assign bmp_data_valid = sd_sec_read_data_valid &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt < file_len);
assign bmp_row_bytes = (width[15:0] << 1) + width[15:0];
assign bmp_row_stride = (bmp_row_bytes + 16'd3) & 16'hfffc;
assign bmp_pixel_byte_valid = bmp_data_valid &&
                              (bmp_row_count < height[10:0]) &&
                              (bmp_row_byte_count < bmp_row_bytes);
assign bmp_src_width = width[15:0];
assign bmp_src_height = height[15:0];
assign scale_go = (state == ST_SCALE_WAIT) && !wrack_s1;
wire unused_output_size = &{1'b0,bmp_width,bmp_height};
// exFAT cluster geometry is stable long before directory/pixel reads.
// Register its terminal sector, rather than decoding a variable shift in
// the same cycle as the SD address increment and state transition.
always @(posedge clk or posedge rst) begin
    if(rst) cluster_last_sector <= 0;
    else cluster_last_sector <= (32'd1 << sectors_per_cluster_shift)-32'd1;
end
assign unused_scan_limits = &{1'b0, scan_start_sector, scan_max_sector};
assign fs_volume_lba = volume_lba;
assign fs_fat_offset = fat_offset;
assign fs_heap_offset = cluster_heap_offset;
assign fs_spc_shift = sectors_per_cluster_shift;

function [31:0] cluster_lba;
    input [31:0] base_lba;
    input [31:0] heap_offset;
    input [31:0] cluster;
    input [7:0] spc_shift;
    begin
        cluster_lba = base_lba + heap_offset + ((cluster - 32'd2) << spc_shift);
    end
endfunction

always @(posedge clk) begin
    candidate_meta_read <= candidate_meta[validate_index[5:0]];
    if (!rst && state == ST_DIR && sd_sec_read_data_valid &&
        rd_cnt[4:0] == 5'd31 && dir_entry_type == 8'hC0 &&
        primary_pending && !primary_is_dir && stream_first_cluster >= 32'd2 &&
        candidate_count < 7'd48)
        candidate_meta[candidate_count[5:0]] <= {
            scanning_child_dir, stream_no_fat_chain, stream_data_length[29:0],
            cluster_lba(volume_lba, cluster_heap_offset,
                        stream_first_cluster, sectors_per_cluster_shift)};
end

function [31:0] lba_cluster;
    input [31:0] base_lba;
    input [31:0] heap_offset;
    input [31:0] lba;
    input [7:0] spc_shift;
    begin
        lba_cluster = ((lba - base_lba - heap_offset) >> spc_shift) + 32'd2;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst)
        {wrack_s1, wrack_s0} <= 2'b00;
    else
        {wrack_s1, wrack_s0} <= {wrack_s0, write_req_ack};
end

always @(posedge clk or posedge rst) begin
    if (rst)
        rd_cnt <= 10'd0;
    else if ((state == ST_BOOT0) || (state == ST_VBR) || (state == ST_DIR) ||
             (state == ST_VALIDATE) || (state == ST_LOAD_HDR) ||
             (state == ST_FAT_READ)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else
        rd_cnt <= 10'd0;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0 <= 8'd0;
        header_1 <= 8'd0;
        riff_signature <= 32'd0;
        wave_signature <= 32'd0;
        lyr_track_id_raw <= 8'd0;
        file_len <= 32'd0;
        pixel_offset <= 32'd54;
        width <= 32'd0;
        height <= 32'd0;
        bit_count <= 16'd0;
        planes <= 16'd0;
        compression <= 32'd0;
    end else if (((state == ST_VALIDATE) || (state == ST_LOAD_HDR)) &&
                 sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : begin header_0 <= sd_sec_read_data; riff_signature[7:0] <= sd_sec_read_data; end
            10'd1 : begin header_1 <= sd_sec_read_data; riff_signature[15:8] <= sd_sec_read_data; end
            10'd2 : begin file_len[7:0] <= sd_sec_read_data; riff_signature[23:16] <= sd_sec_read_data; end
            10'd3 : begin file_len[15:8] <= sd_sec_read_data; riff_signature[31:24] <= sd_sec_read_data; end
            10'd8 : wave_signature[7:0] <= sd_sec_read_data;
            10'd9 : wave_signature[15:8] <= sd_sec_read_data;
            10'd10: begin pixel_offset[7:0] <= sd_sec_read_data; wave_signature[23:16] <= sd_sec_read_data; end
            10'd11: begin pixel_offset[15:8] <= sd_sec_read_data; wave_signature[31:24] <= sd_sec_read_data; end
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;
            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;
            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: begin
                height[23:16] <= sd_sec_read_data;
                lyr_track_id_raw <= sd_sec_read_data; // LYR2 track number
            end
            10'd25: height[31:24] <= sd_sec_read_data;
            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;
            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;
            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)
        bmp_len_cnt <= 32'd0;
    else if ((state == ST_LOAD_DATA) && sd_sec_read_data_valid)
        bmp_len_cnt <= bmp_len_cnt + 32'd1;
    else if ((state != ST_LOAD_DATA) && (state != ST_FAT_READ))
        bmp_len_cnt <= 32'd0;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        bmp_byte_idx <= 2'd0;
    else if ((state == ST_LOAD_DATA) && bmp_pixel_byte_valid)
        bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : bmp_byte_idx + 2'd1;
    else if ((state != ST_LOAD_DATA) && (state != ST_FAT_READ))
        bmp_byte_idx <= 2'd0;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_row_byte_count <= 16'd0;
        bmp_row_count <= 11'd0;
    end else if ((state == ST_LOAD_DATA) && bmp_data_valid &&
                 (bmp_row_count < height[10:0])) begin
        if (bmp_row_byte_count + 16'd1 == bmp_row_stride) begin
            bmp_row_byte_count <= 16'd0;
            bmp_row_count <= bmp_row_count + 11'd1;
        end else bmp_row_byte_count <= bmp_row_byte_count + 16'd1;
    end else if ((state != ST_LOAD_DATA) && (state != ST_FAT_READ)) begin
        bmp_row_byte_count <= 16'd0;
        bmp_row_count <= 11'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data <= 24'd0;
    end else if ((state == ST_LOAD_DATA) && bmp_pixel_byte_valid) begin
        case (bmp_byte_idx)
            2'd0: begin bmp_data_wr_en <= 1'b0; bmp_data[7:0] <= sd_sec_read_data; end
            2'd1: begin bmp_data_wr_en <= 1'b0; bmp_data[15:8] <= sd_sec_read_data; end
            2'd2: begin bmp_data_wr_en <= 1'b1; bmp_data[23:16] <= sd_sec_read_data; end
            default: bmp_data_wr_en <= 1'b0;
        endcase
    end else
        bmp_data_wr_en <= 1'b0;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        bmp_load_begin <= 1'b0;
        state_code <= 4'd0;
        sd_sec_read <= 1'b0;
        sd_sec_read_addr <= 32'd0;
        write_req <= 1'b0;
        scan_done <= 1'b0;
        scan_found_valid <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total <= 5'd0;
        wav_found <= 1'b0;
        wav_first_lba <= 32'd0;
        wav_first_cluster <= 32'd0;
        wav_no_fat_chain <= 1'b0;
        wav_file_bytes <= 32'd0;
        wav_item_valid <= 1'b0;
        wav_item_lba <= 32'd0;
        wav_item_cluster <= 32'd0;
        wav_item_no_fat_chain <= 1'b0;
        wav_item_file_bytes <= 32'd0;
        wav_item_track_id <= 5'd0;
        lyr_item_valid <= 1'b0;
        lyr_item_lba <= 32'd0;
        lyr_item_cluster <= 32'd0;
        lyr_item_no_fat_chain <= 1'b0;
        lyr_item_file_bytes <= 32'd0;
        lyr_item_track_id <= 8'd0;
        mvi_item_valid <= 1'b0;
        mvi_item_rgb332 <= 1'b0;
        mvi_item_indexed <= 1'b0;mvi_item_dynamic<=0;
        mvi_item_lba <= 32'd0;
        mvi_item_cluster <= 32'd0;
        mvi_item_no_fat_chain <= 1'b0;
        mvi_item_file_bytes <= 32'd0;
        exfat_name_match <= 1'b1;
        partition_lba <= 32'd0;
        volume_lba <= 32'd0;
        cluster_heap_offset <= 32'd0;
        fat_offset <= 32'd0;
        root_dir_cluster <= 32'd0;
        bytes_per_sector_shift <= 8'd0;
        sectors_per_cluster_shift <= 8'd0;
        dir_cluster <= 32'd0;
        dir_sector_index <= 32'd0;
        dir_end_seen <= 1'b0;
        dir_entry_type <= 8'd0;
        primary_pending <= 1'b0;
        primary_is_dir <= 1'b0;
        stream_first_cluster <= 32'd0;
        stream_data_length <= 32'd0;
        stream_no_fat_chain <= 1'b0;
        candidate_count <= 7'd0;
        candidate_recorded <= 1'b0;
        name_char0 <= 8'd0;
        name_char1 <= 8'd0;
        validate_index <= 7'd0;
        child_dir_count <= 4'd0;
        child_dir_index <= 4'd0;
        scanning_child_dir <= 1'b0;
        next_dir_cluster <= 32'd0;
        candidate_meta_latched <= 64'd0;
        candidate_lba_latched <= 32'd0;
        candidate_cluster_latched <= 32'd0;
        load_fs_base <= 32'd0;
        load_cluster_target <= 32'd0;
        load_cluster_next_lba <= 32'd0;
        load_sector_latched <= 32'd0;
        load_current_cluster <= 32'd0;
        load_sector_in_cluster <= 32'd0;
        load_no_fat_chain <= 1'b1;
        fat_next_cluster <= 32'd0;
        fat_entry_byte_offset <= 9'd0;
    end else if (!sd_init_done) begin
        bmp_load_begin <= 1'b0;
        state <= ST_IDLE;
        state_code <= 4'd0;
        sd_sec_read <= 1'b0;
        write_req <= 1'b0;
        scan_done <= 1'b0;
        scan_found_valid <= 1'b0;
        scan_found_total <= 5'd0;
        wav_found <= 1'b0;
        wav_item_valid <= 1'b0;
        lyr_item_valid <= 1'b0;
        mvi_item_valid <= 1'b0;
    end else begin
        bmp_load_begin <= 1'b0;
        scan_found_valid <= 1'b0;
        wav_item_valid <= 1'b0;
        lyr_item_valid <= 1'b0;
        mvi_item_valid <= 1'b0;
        case (state)
            ST_IDLE: begin
                state_code <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req <= 1'b0;
                if (scan_start) begin
                    scan_done <= 1'b0;
                    scan_found_total <= 5'd0;
                    wav_found <= 1'b0;
                    candidate_count <= 7'd0;
                    candidate_recorded <= 1'b0;
                    name_char0 <= 8'd0;
                    name_char1 <= 8'd0;
                    validate_index <= 7'd0;
                    child_dir_count <= 4'd0;
                    child_dir_index <= 4'd0;
                    scanning_child_dir <= 1'b0;
                    partition_lba <= 32'd0;
                    exfat_name_match <= 1'b1;
                    cluster_heap_offset <= 32'd0;
                    fat_offset <= 32'd0;
                    root_dir_cluster <= 32'd0;
                    bytes_per_sector_shift <= 8'd0;
                    sectors_per_cluster_shift <= 8'd0;
                    sd_sec_read_addr <= 32'd0;
                    state <= ST_BOOT0;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr <= load_sector;
                    load_current_cluster <= 32'd0;
                    load_sector_in_cluster <= 32'd0;
                    load_no_fat_chain <= 1'b1;
                    validate_index <= 7'd0;
                    state <= ST_LOAD_MATCH;
                end
            end

            ST_LOAD_MATCH: begin
                state_code <= 4'd2;
                if (validate_index >= candidate_count) begin
                    state <= ST_LOAD_HDR;
                end else state <= ST_LOAD_READ;
            end

            ST_LOAD_READ: begin
                if (candidate_meta_read[31:0] == load_sector_latched) begin
                    candidate_meta_latched <= candidate_meta_read;
                    load_fs_base <= volume_lba + cluster_heap_offset;
                    state <= ST_LOAD_META;
                end else begin
                    validate_index <= validate_index + 7'd1;
                    state <= ST_LOAD_MATCH;
                end
            end

            ST_LOAD_META: begin
                state_code <= 4'd2;
                candidate_lba_latched <= candidate_meta_latched[31:0];
                load_no_fat_chain <= candidate_meta_latched[62];
                state <= ST_LOAD_CALC;
            end

            // Keep the filesystem-base addition out of the same cycle as the
            // LBA-to-cluster subtraction/shift used before loading a BMP.
            ST_LOAD_CALC: begin
                state_code <= 4'd2;
                load_current_cluster <=
                    ((candidate_lba_latched - load_fs_base) >>
                     sectors_per_cluster_shift) + 32'd2;
                state <= ST_LOAD_HDR;
            end

            ST_BOOT0: begin
                state_code <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_data_valid) begin
                    if ((rd_cnt >= 10'd3) && (rd_cnt <= 10'd10)) begin
                        case (rd_cnt)
                            10'd3: if (sd_sec_read_data != "E") exfat_name_match <= 1'b0;
                            10'd4: if (sd_sec_read_data != "X") exfat_name_match <= 1'b0;
                            10'd5: if (sd_sec_read_data != "F") exfat_name_match <= 1'b0;
                            10'd6: if (sd_sec_read_data != "A") exfat_name_match <= 1'b0;
                            10'd7: if (sd_sec_read_data != "T") exfat_name_match <= 1'b0;
                            default: if (sd_sec_read_data != 8'h20) exfat_name_match <= 1'b0;
                        endcase
                    end
                    case (rd_cnt)
                        10'd80: fat_offset[7:0] <= sd_sec_read_data;
                        10'd81: fat_offset[15:8] <= sd_sec_read_data;
                        10'd82: fat_offset[23:16] <= sd_sec_read_data;
                        10'd83: fat_offset[31:24] <= sd_sec_read_data;
                        10'd88: cluster_heap_offset[7:0] <= sd_sec_read_data;
                        10'd89: cluster_heap_offset[15:8] <= sd_sec_read_data;
                        10'd90: cluster_heap_offset[23:16] <= sd_sec_read_data;
                        10'd91: cluster_heap_offset[31:24] <= sd_sec_read_data;
                        10'd96: root_dir_cluster[7:0] <= sd_sec_read_data;
                        10'd97: root_dir_cluster[15:8] <= sd_sec_read_data;
                        10'd98: root_dir_cluster[23:16] <= sd_sec_read_data;
                        10'd99: root_dir_cluster[31:24] <= sd_sec_read_data;
                        10'd108: bytes_per_sector_shift <= sd_sec_read_data;
                        10'd109: sectors_per_cluster_shift <= sd_sec_read_data;
                        10'd454: partition_lba[7:0] <= sd_sec_read_data;
                        10'd455: partition_lba[15:8] <= sd_sec_read_data;
                        10'd456: partition_lba[23:16] <= sd_sec_read_data;
                        10'd457: partition_lba[31:24] <= sd_sec_read_data;
                        default: ;
                    endcase
                end
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (exfat_name_match && (bytes_per_sector_shift == 8'd9)) begin
                        volume_lba <= 32'd0;
                        dir_cluster <= root_dir_cluster;
                        dir_sector_index <= 32'd0;
                        dir_end_seen <= 1'b0;
                        primary_pending <= 1'b0;
                        scanning_child_dir <= 1'b0;
                        next_dir_cluster <= root_dir_cluster;
                        state <= ST_DIR_ADDR;
                    end else if (partition_lba != 32'd0) begin
                        volume_lba <= partition_lba;
                        exfat_name_match <= 1'b1;
                        fat_offset <= 32'd0;
                        cluster_heap_offset <= 32'd0;
                        root_dir_cluster <= 32'd0;
                        bytes_per_sector_shift <= 8'd0;
                        sectors_per_cluster_shift <= 8'd0;
                        sd_sec_read_addr <= partition_lba;
                        state <= ST_VBR;
                    end else begin
                        scan_done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            ST_VBR: begin
                state_code <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_data_valid) begin
                    if ((rd_cnt >= 10'd3) && (rd_cnt <= 10'd10)) begin
                        case (rd_cnt)
                            10'd3: if (sd_sec_read_data != "E") exfat_name_match <= 1'b0;
                            10'd4: if (sd_sec_read_data != "X") exfat_name_match <= 1'b0;
                            10'd5: if (sd_sec_read_data != "F") exfat_name_match <= 1'b0;
                            10'd6: if (sd_sec_read_data != "A") exfat_name_match <= 1'b0;
                            10'd7: if (sd_sec_read_data != "T") exfat_name_match <= 1'b0;
                            default: if (sd_sec_read_data != 8'h20) exfat_name_match <= 1'b0;
                        endcase
                    end
                    case (rd_cnt)
                        10'd80: fat_offset[7:0] <= sd_sec_read_data;
                        10'd81: fat_offset[15:8] <= sd_sec_read_data;
                        10'd82: fat_offset[23:16] <= sd_sec_read_data;
                        10'd83: fat_offset[31:24] <= sd_sec_read_data;
                        10'd88: cluster_heap_offset[7:0] <= sd_sec_read_data;
                        10'd89: cluster_heap_offset[15:8] <= sd_sec_read_data;
                        10'd90: cluster_heap_offset[23:16] <= sd_sec_read_data;
                        10'd91: cluster_heap_offset[31:24] <= sd_sec_read_data;
                        10'd96: root_dir_cluster[7:0] <= sd_sec_read_data;
                        10'd97: root_dir_cluster[15:8] <= sd_sec_read_data;
                        10'd98: root_dir_cluster[23:16] <= sd_sec_read_data;
                        10'd99: root_dir_cluster[31:24] <= sd_sec_read_data;
                        10'd108: bytes_per_sector_shift <= sd_sec_read_data;
                        10'd109: sectors_per_cluster_shift <= sd_sec_read_data;
                        default: ;
                    endcase
                end
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (exfat_name_match && (bytes_per_sector_shift == 8'd9)) begin
                        dir_cluster <= root_dir_cluster;
                        dir_sector_index <= 32'd0;
                        dir_end_seen <= 1'b0;
                        primary_pending <= 1'b0;
                        scanning_child_dir <= 1'b0;
                        next_dir_cluster <= root_dir_cluster;
                        state <= ST_DIR_ADDR;
                    end else begin
                        scan_done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            ST_DIR: begin
                state_code <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_data_valid) begin
                    if (rd_cnt[4:0] == 5'd0) begin
                        dir_entry_type <= sd_sec_read_data;
                        if (sd_sec_read_data == 8'h85) begin
                            primary_pending <= 1'b1;
                            primary_is_dir <= 1'b0;
                            candidate_recorded <= 1'b0;
                            name_char0 <= 8'd0;
                            name_char1 <= 8'd0;
                        end else if (sd_sec_read_data == 8'hC0) begin
                            stream_first_cluster <= 32'd0;
                            stream_data_length <= 32'd0;
                            stream_no_fat_chain <= 1'b0;
                        end else if (sd_sec_read_data == 8'h00)
                            dir_end_seen <= 1'b1;
                    end
                    if ((dir_entry_type == 8'h85) && (rd_cnt[4:0] == 5'd4))
                        primary_is_dir <= sd_sec_read_data[4];
                    if (dir_entry_type == 8'hC0) begin
                        case (rd_cnt[4:0])
                            5'd1: stream_no_fat_chain <= sd_sec_read_data[1];
                            5'd20: stream_first_cluster[7:0] <= sd_sec_read_data;
                            5'd21: stream_first_cluster[15:8] <= sd_sec_read_data;
                            5'd22: stream_first_cluster[23:16] <= sd_sec_read_data;
                            5'd23: stream_first_cluster[31:24] <= sd_sec_read_data;
                            5'd24: stream_data_length[7:0] <= sd_sec_read_data;
                            5'd25: stream_data_length[15:8] <= sd_sec_read_data;
                            5'd26: stream_data_length[23:16] <= sd_sec_read_data;
                            5'd27: stream_data_length[31:24] <= sd_sec_read_data;
                            default: ;
                        endcase
                    end
                    // File name entry: bytes 2/4 are the first two UTF-16
                    // characters. Capture the two leading digits (02.wav -> 2).
                    if (dir_entry_type == 8'hC1) begin
                        case (rd_cnt[4:0])
                            5'd2: name_char0 <= sd_sec_read_data;
                            5'd4: name_char1 <= sd_sec_read_data;
                            5'd31: begin
                                if (candidate_recorded &&
                                    (candidate_count != 7'd0) &&
                                    (name_char0 >= 8'h30) &&
                                    (name_char0 <= 8'h39) &&
                                    (name_char1 >= 8'h30) &&
                                    (name_char1 <= 8'h39)) begin
                                    candidate_track[candidate_count[5:0] - 1'b1] <=
                                        (name_char0 == 8'h30 && name_char1 == 8'h30) ? 5'd17 :
                                        ({1'b0,(name_char0 - 8'h30)} * 5'd10) + (name_char1 - 8'h30);
                                end else if (candidate_recorded &&
                                             (candidate_count != 7'd0)) begin
                                    candidate_track[candidate_count[5:0] - 1'b1] <= 5'd0;
                                end
                            end
                            default: ;
                        endcase
                    end
                    if ((rd_cnt[4:0] == 5'd31) && (dir_entry_type == 8'hC0) &&
                        primary_pending) begin
                        if (primary_is_dir && !scanning_child_dir &&
                            (stream_first_cluster >= 32'd2) && (child_dir_count < 4'd8)) begin
                            child_dir_cluster[child_dir_count[2:0]] <= stream_first_cluster;
                            child_dir_count <= child_dir_count + 4'd1;
                        end else if (!primary_is_dir && (stream_first_cluster >= 32'd2) &&
                            (candidate_count < 7'd48)) begin
                            candidate_count <= candidate_count + 7'd1;
                            candidate_recorded <= 1'b1;
                        end
                        primary_pending <= 1'b0;
                    end
                end
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (dir_end_seen || (candidate_count >= 7'd48)) begin
                        if ((!scanning_child_dir && (child_dir_count != 4'd0)) ||
                            (scanning_child_dir && (child_dir_index + 4'd1 < child_dir_count))) begin
                            scanning_child_dir <= 1'b1;
                            if (!scanning_child_dir)
                                child_dir_index <= 4'd0;
                            else
                                child_dir_index <= child_dir_index + 4'd1;
                            dir_sector_index <= 32'd0;
                            dir_end_seen <= 1'b0;
                            primary_pending <= 1'b0;
                            state <= ST_DIR_PREP;
                        end else begin
                        validate_index <= 7'd0;
                        if (candidate_count != 5'd0) begin
                            state <= ST_VALID_PREP;
                        end else begin
                            scan_done <= 1'b1;
                            state <= ST_IDLE;
                        end
                        end
                    end else if (dir_sector_index != cluster_last_sector) begin
                        dir_sector_index <= dir_sector_index + 32'd1;
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end else begin
                        next_dir_cluster <= dir_cluster + 32'd1;
                        dir_sector_index <= 32'd0;
                        state <= ST_DIR_ADDR;
                    end
                end
            end

            // Split the indexed child-directory mux from the cluster-to-LBA
            // arithmetic.  Directory changes happen only between sectors, so
            // these two preparation cycles do not reduce SD transfer rate.
            ST_DIR_PREP: begin
                state_code <= 4'd2;
                next_dir_cluster <= child_dir_cluster[child_dir_index[2:0]];
                state <= ST_DIR_ADDR;
            end

            ST_DIR_ADDR: begin
                state_code <= 4'd2;
                dir_cluster <= next_dir_cluster;
                sd_sec_read_addr <= cluster_lba(volume_lba, cluster_heap_offset,
                                                next_dir_cluster,
                                                sectors_per_cluster_shift);
                state <= ST_DIR;
            end

            // Register the selected metadata before using it for the header
            // read and type handling.  This removes the 48-way array mux from
            // the same cycle as the LBA/cluster arithmetic.
            ST_VALID_PREP: begin
                state_code <= 4'd2;
                state <= ST_VALID_READ;
            end

            ST_VALID_READ: begin
                candidate_meta_latched <= candidate_meta_read;
                load_fs_base <= volume_lba + cluster_heap_offset;
                state <= ST_VALID_META;
            end

            ST_VALID_META: begin
                state_code <= 4'd2;
                candidate_lba_latched <= candidate_meta_latched[31:0];
                state <= ST_VALID_ADDR;
            end

            ST_VALID_ADDR: begin
                state_code <= 4'd2;
                sd_sec_read_addr <= candidate_lba_latched;
                candidate_cluster_latched <=
                    ((candidate_lba_latched - load_fs_base) >>
                     sectors_per_cluster_shift) + 32'd2;
                state <= ST_VALIDATE;
            end

            ST_VALIDATE: begin
                state_code <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match && (scan_found_total < scan_target_count)) begin
                        scan_found_valid <= 1'b1;
                        scan_found_sector <= candidate_lba_latched;
                        scan_found_total <= scan_found_total + 5'd1;
                    end
                    if (!wav_found && (riff_signature == 32'h46464952) &&
                        (wave_signature == 32'h45564157)) begin
                        wav_found <= 1'b1;
                        wav_first_lba <= candidate_lba_latched;
                        wav_first_cluster <= candidate_cluster_latched;
                        wav_no_fat_chain <= candidate_meta_latched[62];
                        wav_file_bytes <= {2'b00,candidate_meta_latched[61:32]};
                    end
                    if (candidate_meta_latched[63] &&
                        (riff_signature == 32'h46464952) &&
                        (wave_signature == 32'h45564157)) begin
                        wav_item_valid <= 1'b1;
                        wav_item_lba <= candidate_lba_latched;
                        wav_item_cluster <= candidate_cluster_latched;
                        wav_item_no_fat_chain <= candidate_meta_latched[62];
                        wav_item_file_bytes <= {2'b00,candidate_meta_latched[61:32]};
                        wav_item_track_id <= candidate_track[validate_index[5:0]];
                    end
                    if (candidate_meta_latched[63] &&
                        (riff_signature == 32'h3152594c)) begin
                        lyr_item_valid <= 1'b1;
                        lyr_item_lba <= candidate_lba_latched;
                        lyr_item_cluster <= candidate_cluster_latched;
                        lyr_item_no_fat_chain <= candidate_meta_latched[62];
                        lyr_item_file_bytes <= {2'b00,candidate_meta_latched[61:32]};
                        lyr_item_track_id <= (candidate_track[validate_index[5:0]] != 5'd0) ?
                                             candidate_track[validate_index[5:0]] :
                                             lyr_track_id_raw[4:0];
                    end
                    if (candidate_meta_latched[63] &&
                        ((riff_signature == 32'h3149564d) || (riff_signature == 32'h3249564d) || (riff_signature == 32'h3349564d) || (riff_signature == 32'h3449564d))) begin
                        mvi_item_valid <= 1'b1;
                        mvi_item_rgb332 <= riff_signature != 32'h3149564d;
                        mvi_item_indexed <= (riff_signature == 32'h3349564d) || (riff_signature == 32'h3449564d);
                        mvi_item_dynamic <= riff_signature == 32'h3449564d;
                        mvi_item_lba <= candidate_lba_latched;
                        mvi_item_cluster <= candidate_cluster_latched;
                        mvi_item_no_fat_chain <= candidate_meta_latched[62];
                        mvi_item_file_bytes <= {2'b00,candidate_meta_latched[61:32]};
                    end
                    if (validate_index + 7'd1 >= candidate_count) begin
                        scan_done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        validate_index <= validate_index + 7'd1;
                        state <= ST_VALID_PREP;
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req <= 1'b1;
                        bmp_load_begin <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state <= ST_LOAD_WAIT;
                    end else
                        state <= ST_IDLE;
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (wrack_s1) begin
                    write_req <= 1'b0;
                    state <= ST_SCALE_WAIT;
                end
            end

            ST_SCALE_WAIT: begin
                state_code <= 4'd3;
                if (!wrack_s1 && scale_ready)
                    state <= ST_LOAD_DATA;
            end

            ST_LOAD_DATA: begin
                state_code <= 4'd4;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (bmp_len_cnt >= file_len)
                        state <= ST_IDLE;
                    else if (load_sector_in_cluster != cluster_last_sector) begin
                        load_sector_in_cluster <= load_sector_in_cluster + 32'd1;
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end else if (load_no_fat_chain) begin
                        load_current_cluster <= load_current_cluster + 32'd1;
                        load_sector_in_cluster <= 32'd0;
                        // A NoFatChain exFAT stream remains contiguous across
                        // cluster boundaries, so no cluster-to-LBA math is needed.
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end else begin
                        // Fragmented exFAT file: follow its FAT cluster chain.
                        fat_entry_byte_offset <= (load_current_cluster << 2) & 9'h1ff;
                        fat_next_cluster <= 32'd0;
                        sd_sec_read_addr <= volume_lba + fat_offset +
                                            ((load_current_cluster << 2) >> 9);
                        state <= ST_FAT_READ;
                    end
                end
            end

            ST_FAT_READ: begin
                state_code <= 4'd2;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_data_valid) begin
                    if (rd_cnt == fat_entry_byte_offset)
                        fat_next_cluster[7:0] <= sd_sec_read_data;
                    else if (rd_cnt == fat_entry_byte_offset + 10'd1)
                        fat_next_cluster[15:8] <= sd_sec_read_data;
                    else if (rd_cnt == fat_entry_byte_offset + 10'd2)
                        fat_next_cluster[23:16] <= sd_sec_read_data;
                    else if (rd_cnt == fat_entry_byte_offset + 10'd3)
                        fat_next_cluster[31:24] <= sd_sec_read_data;
                end
                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if ((fat_next_cluster >= 32'd2) &&
                        (fat_next_cluster < 32'hfffffff8)) begin
                        load_current_cluster <= fat_next_cluster;
                        load_sector_in_cluster <= 32'd0;
                        load_cluster_target <= fat_next_cluster;
                        load_fs_base <= volume_lba + cluster_heap_offset;
                        state <= ST_LOAD_CLUSTER_PREP;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_CLUSTER_PREP: begin
                state_code <= 4'd2;
                load_cluster_next_lba <= load_fs_base +
                    ((load_cluster_target - 32'd2) << sectors_per_cluster_shift);
                state <= ST_LOAD_CLUSTER_ADDR;
            end

            ST_LOAD_CLUSTER_ADDR: begin
                state_code <= 4'd4;
                sd_sec_read_addr <= load_cluster_next_lba;
                state <= ST_LOAD_DATA;
            end

            default: begin
                state <= ST_IDLE;
                state_code <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req <= 1'b0;
            end
        endcase
    end
end

endmodule
