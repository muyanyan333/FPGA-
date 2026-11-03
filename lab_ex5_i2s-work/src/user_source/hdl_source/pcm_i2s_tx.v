// Uses the same 64-BCLK-per-channel framing as hdmi_audio_tone_i2s_64fs.
// PCM frame: signed 16-bit left in [31:16], right in [15:0].
module pcm_i2s_tx(
    input wire mclk, input wire rst, input wire enable,
    input wire [3:0] volume_level, input wire volume_muted,
    output reg bclk, output reg lrck, output reg dout,
    output reg fifo_rd_en, input wire [31:0] fifo_rd_data,
    input wire fifo_empty
);
    // The UART setting changes slowly. Require a stable synchronized bus
    // before applying it; scale both channels together when fetching a frame.
    reg [4:0] volume_sync0, volume_sync1, volume_previous, volume_stable;
    always @(posedge mclk or posedge rst) begin
        if (rst) begin
            volume_sync0 <= 5'd10; volume_sync1 <= 5'd10;
            volume_previous <= 5'd10; volume_stable <= 5'd10;
        end else begin
            volume_sync0 <= {volume_muted, volume_level};
            volume_sync1 <= volume_sync0;
            volume_previous <= volume_sync1;
            if (volume_sync1 == volume_previous) volume_stable <= volume_sync1;
        end
    end
    reg [8:0] gain;
    always @* begin
        if (volume_stable[4]) gain = 0;
        else case (volume_stable[3:0])
            0: gain=0; 1: gain=26; 2: gain=51; 3: gain=77;
            4: gain=102; 5: gain=128; 6: gain=154; 7: gain=179;
            8: gain=205; 9: gain=230; default: gain=256;
        endcase
    end
    wire signed [25:0] left_product = $signed(fifo_rd_data[31:16]) * $signed({1'b0,gain});
    wire signed [25:0] right_product = $signed(fifo_rd_data[15:0]) * $signed({1'b0,gain});
    wire [31:0] scaled_word = {left_product[23:8],right_product[23:8]};
    reg [5:0] bit_cnt;
    reg [63:0] shift_reg;
    reg [31:0] frame_word;
    reg [31:0] next_word;
    reg [1:0] fetch_delay;

    always @(posedge mclk or posedge rst) begin
        if (rst) begin
            bclk <= 1'b0; lrck <= 1'b0; dout <= 1'b0;
            bit_cnt <= 6'd0; shift_reg <= 64'd0;
            frame_word <= 32'd0; next_word <= 32'd0;
            fifo_rd_en <= 1'b0; fetch_delay <= 2'd0;
        end else begin
            bclk <= ~bclk;
            fifo_rd_en <= 1'b0;
            if (fetch_delay != 2'd0) begin
                fetch_delay <= fetch_delay - 1'b1;
                if (fetch_delay == 2'd1)
                    next_word <= scaled_word;
            end
            if (bclk) begin
                dout <= shift_reg[63];
                shift_reg <= {shift_reg[62:0], 1'b0};
                if (bit_cnt == 6'd63) begin
                    bit_cnt <= 6'd0;
                    if (!lrck) begin
                        lrck <= 1'b1;
                        shift_reg <= {{frame_word[15:0],8'd0},40'd0};
                        if (enable && !fifo_empty) begin
                            fifo_rd_en <= 1'b1;
                            fetch_delay <= 2'd2;
                        end else begin
                            next_word <= 32'd0;
                        end
                    end else begin
                        lrck <= 1'b0;
                        frame_word <= next_word;
                        shift_reg <= {{next_word[31:16],8'd0},40'd0};
                    end
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
        end
    end
endmodule
