// Streams one canonical 44-byte-header PCM WAV from an exFAT file.
// Accepted: 48 kHz, 16-bit, one or two channels. EOF returns to the scheduler.
// One SD sector is requested only when the 4096-frame output FIFO has room.
module exfat_pcm_wav_reader #(
    parameter USE_CLUSTER_START = 0
)(
    input wire clk, input wire rst, input wire start, input wire restart,
    input wire [31:0] first_lba, first_cluster, file_bytes,
    input wire no_fat_chain,
    input wire [31:0] volume_lba, fat_offset, heap_offset,
    input wire [7:0] spc_shift,
    input wire [12:0] fifo_count, input wire fifo_full,
    output reg fifo_wr_en, output reg [31:0] fifo_wr_data,
    output reg wav_valid, output reg wav_error, output reg eof,
    output reg sd_sec_read, output reg [31:0] sd_sec_read_addr,
    input wire [7:0] sd_data, input wire sd_data_valid, input wire sd_read_end
);
    localparam S_IDLE=3'd0, S_WAIT=3'd1, S_DATA=3'd2,
               S_FAT=3'd3, S_ERROR=3'd4,
               S_CLUSTER_PREP=3'd5, S_CLUSTER_ADDR=3'd6;
    reg [2:0] state;
    reg [9:0] byte_index;
    reg header_sector;
    reg track_no_fat_chain;
    reg cluster_header_pending;
    reg [31:0] current_cluster, sector_in_cluster, fat_next;
    reg [31:0] cluster_target, cluster_base, cluster_next_lba;
    reg [9:0] fat_byte_offset;
    reg [31:0] pcm_remaining;
    reg [31:0] riff_tag, wave_tag, fmt_tag, data_tag, sample_rate;
    reg [15:0] format_code, channels, bits_per_sample;
    reg [23:0] data_size_low;
    reg [1:0] byte_phase;
    reg [7:0] low_byte, right_low;
    reg [15:0] left_sample;
    reg sector_room;
    // Break the Gray decode -> FIFO subtraction -> threshold -> FSM path.
    // A sector holds at most 256 mono samples (128 stereo); 296 spare
    // entries at this threshold cover that payload and the one-cycle delay.
    always @(posedge clk or posedge rst) begin
        if (rst) sector_room <= 1'b0;
        else sector_room <= fifo_count <= 13'd3800 && !fifo_full;
    end

    function [31:0] cluster_lba;
        input [31:0] base, heap, cluster;
        input [7:0] shift;
        begin cluster_lba = base + heap + ((cluster - 32'd2) << shift); end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE; sd_sec_read <= 1'b0; sd_sec_read_addr <= 32'd0;
            fifo_wr_en <= 1'b0; fifo_wr_data <= 32'd0;
            wav_valid <= 1'b0; wav_error <= 1'b0;
            eof <= 1'b0;
            byte_index <= 10'd0; header_sector <= 1'b1;
            track_no_fat_chain <= 1'b0;
            cluster_header_pending <= 1'b0;
            current_cluster <= 32'd0; sector_in_cluster <= 32'd0;
            fat_next <= 32'd0; fat_byte_offset <= 10'd0;
            cluster_target <= 32'd0; cluster_base <= 32'd0;
            cluster_next_lba <= 32'd0;
            pcm_remaining <= 32'd0;
            riff_tag <= 32'd0; wave_tag <= 32'd0;
            fmt_tag <= 32'd0; data_tag <= 32'd0;
            sample_rate <= 32'd0; format_code <= 16'd0;
            channels <= 16'd0; bits_per_sample <= 16'd0;
            data_size_low <= 24'd0; byte_phase <= 2'd0;
            low_byte <= 8'd0; right_low <= 8'd0; left_sample <= 16'd0;
        end else begin
            fifo_wr_en <= 1'b0;
            eof <= 1'b0;
            if (restart) begin
                sd_sec_read <= 1'b0;
                wav_valid <= 1'b0;
                wav_error <= 1'b0;
                pcm_remaining <= 32'd0;
                byte_phase <= 2'd0;
                state <= S_IDLE;
            end else case (state)
                S_IDLE: if (start && file_bytes >= 32'd44 && first_cluster >= 32'd2) begin
                    current_cluster <= first_cluster;
                    track_no_fat_chain <= no_fat_chain;
                    sector_in_cluster <= 32'd0;
                    header_sector <= 1'b1;
                    byte_phase <= 2'd0;
                    if (USE_CLUSTER_START) begin
                        cluster_target <= first_cluster;
                        cluster_base <= volume_lba + heap_offset;
                        cluster_header_pending <= 1'b1;
                        state <= S_CLUSTER_PREP;
                    end else begin
                        sd_sec_read_addr <= first_lba;
                        cluster_header_pending <= 1'b0;
                        state <= S_WAIT;
                    end
                end
                S_WAIT: if (sector_room && !fifo_full) begin
                    byte_index <= 10'd0;
                    sd_sec_read <= 1'b1;
                    state <= S_DATA;
                end
                S_DATA: begin
                    sd_sec_read <= 1'b1;
                    if (sd_data_valid) begin
                        byte_index <= byte_index + 1'b1;
                        if (header_sector) begin
                            case (byte_index)
                                0: riff_tag[7:0] <= sd_data;
                                1: riff_tag[15:8] <= sd_data;
                                2: riff_tag[23:16] <= sd_data;
                                3: riff_tag[31:24] <= sd_data;
                                8: wave_tag[7:0] <= sd_data;
                                9: wave_tag[15:8] <= sd_data;
                                10: wave_tag[23:16] <= sd_data;
                                11: wave_tag[31:24] <= sd_data;
                                12: fmt_tag[7:0] <= sd_data;
                                13: fmt_tag[15:8] <= sd_data;
                                14: fmt_tag[23:16] <= sd_data;
                                15: fmt_tag[31:24] <= sd_data;
                                20: format_code[7:0] <= sd_data;
                                21: format_code[15:8] <= sd_data;
                                22: channels[7:0] <= sd_data;
                                23: channels[15:8] <= sd_data;
                                24: sample_rate[7:0] <= sd_data;
                                25: sample_rate[15:8] <= sd_data;
                                26: sample_rate[23:16] <= sd_data;
                                27: sample_rate[31:24] <= sd_data;
                                34: bits_per_sample[7:0] <= sd_data;
                                35: bits_per_sample[15:8] <= sd_data;
                                36: data_tag[7:0] <= sd_data;
                                37: data_tag[15:8] <= sd_data;
                                38: data_tag[23:16] <= sd_data;
                                39: data_tag[31:24] <= sd_data;
                                40: data_size_low[7:0] <= sd_data;
                                41: data_size_low[15:8] <= sd_data;
                                42: data_size_low[23:16] <= sd_data;
                                43: begin
                                    if (riff_tag == 32'h46464952 && wave_tag == 32'h45564157 &&
                                        fmt_tag == 32'h20746d66 && data_tag == 32'h61746164 &&
                                        format_code == 16'd1 &&
                                        (channels == 16'd1 || channels == 16'd2) &&
                                        sample_rate == 32'd48000 && bits_per_sample == 16'd16 &&
                                        ({sd_data,data_size_low} <= file_bytes - 32'd44)) begin
                                        pcm_remaining <= {sd_data,data_size_low};
                                        wav_valid <= 1'b1;
                                    end else begin
                                        wav_error <= 1'b1;
                                        wav_valid <= 1'b0;
                                    end
                                end
                                default: ;
                            endcase
                        end
                        if ((!header_sector || byte_index >= 10'd44) &&
                            wav_valid && pcm_remaining != 32'd0) begin
                            pcm_remaining <= pcm_remaining - 1'b1;
                            case (byte_phase)
                                2'd0: begin low_byte <= sd_data; byte_phase <= 2'd1; end
                                2'd1: begin
                                    if (channels == 16'd1) begin
                                        fifo_wr_data <= {{sd_data,low_byte},{sd_data,low_byte}};
                                        fifo_wr_en <= 1'b1;
                                        byte_phase <= 2'd0;
                                    end else begin
                                        left_sample <= {sd_data,low_byte};
                                        byte_phase <= 2'd2;
                                    end
                                end
                                2'd2: begin right_low <= sd_data; byte_phase <= 2'd3; end
                                2'd3: begin
                                    fifo_wr_data <= {left_sample,sd_data,right_low};
                                    fifo_wr_en <= 1'b1;
                                    byte_phase <= 2'd0;
                                end
                            endcase
                        end
                    end
                    if (sd_read_end) begin
                        sd_sec_read <= 1'b0;
                        if (wav_error) begin
                            state <= S_ERROR;
                        end else if (wav_valid && pcm_remaining == 32'd0) begin
                            eof <= 1'b1;
                            wav_valid <= 1'b0;
                            state <= S_IDLE;
                        end else if (sector_in_cluster + 32'd1 < (32'd1 << spc_shift)) begin
                            sector_in_cluster <= sector_in_cluster + 32'd1;
                            sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                            header_sector <= 1'b0;
                            state <= S_WAIT;
                        end else if (track_no_fat_chain) begin
                            current_cluster <= current_cluster + 32'd1;
                            sector_in_cluster <= 32'd0;
                            // NoFatChain data is physically contiguous, including
                            // at an exFAT cluster boundary.
                            sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                            header_sector <= 1'b0;
                            state <= S_WAIT;
                        end else begin
                            fat_byte_offset <= (current_cluster << 2) & 10'h1ff;
                            fat_next <= 32'd0;
                            byte_index <= 10'd0;
                            sd_sec_read_addr <= volume_lba + fat_offset + ((current_cluster << 2) >> 9);
                            state <= S_FAT;
                        end
                    end
                end
                S_FAT: begin
                    sd_sec_read <= 1'b1;
                    if (sd_data_valid) begin
                        byte_index <= byte_index + 1'b1;
                        if (byte_index == fat_byte_offset) fat_next[7:0] <= sd_data;
                        else if (byte_index == fat_byte_offset + 10'd1) fat_next[15:8] <= sd_data;
                        else if (byte_index == fat_byte_offset + 10'd2) fat_next[23:16] <= sd_data;
                        else if (byte_index == fat_byte_offset + 10'd3) fat_next[31:24] <= sd_data;
                    end
                    if (sd_read_end) begin
                        sd_sec_read <= 1'b0;
                        if (fat_next >= 32'd2 && fat_next < 32'hfffffff8) begin
                            current_cluster <= fat_next;
                            sector_in_cluster <= 32'd0;
                            cluster_target <= fat_next;
                            cluster_base <= volume_lba + heap_offset;
                            state <= S_CLUSTER_PREP;
                        end else begin
                            wav_error <= 1'b1;
                            state <= S_ERROR;
                        end
                    end
                end
                S_CLUSTER_PREP: begin
                    cluster_next_lba <= cluster_base +
                        ((cluster_target - 32'd2) << spc_shift);
                    state <= S_CLUSTER_ADDR;
                end
                S_CLUSTER_ADDR: begin
                    sd_sec_read_addr <= cluster_next_lba;
                    header_sector <= cluster_header_pending;
                    cluster_header_pending <= 1'b0;
                    state <= S_WAIT;
                end
                default: begin sd_sec_read <= 1'b0; state <= S_ERROR; end
            endcase
        end
    end
endmodule
