// Right-side HDMI properties panel for the unified music player.
// Chinese 16x16 and ASCII 5x7 fonts share 16x16 character cells.
// Music panel uses the rightmost 144 pixels; image geometry editing keeps
// the wider layout needed by the 640 X 480 label.
module property_panel(
    input  wire        clk,
    input  wire        rst,
    input  wire        de,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire        enable,
    input  wire        image_size_edit,
    input  wire [1:0]  image_size_mode,
    input  wire        image_aspect_edit,
    input  wire [1:0]  image_aspect_mode,
    input  wire [4:0]  track_num,
    input  wire [4:0]  track_count,
    input  wire [4:0]  image_num,
    input  wire [4:0]  image_count,
    input  wire        playing,
    input  wire        lyric_enabled,
    input  wire        title_enabled,
    input  wire [1:0]  effect,
    input  wire [3:0]  brightness,
    input  wire [3:0]  contrast,
    output reg         panel_on,
    output reg         text_on
);
    localparam [9:0]  PANEL_Y0 = 10'd64;
    localparam [9:0]  TEXT_Y0  = 10'd72;
    localparam [10:0] TEXT_X1  = 11'd632;   // 408 + 14*16
    localparam [9:0]  TEXT_Y1  = 10'd216;   // 72 + 9*16
    wire geometry_edit = image_size_edit || image_aspect_edit;
    wire [10:0] panel_x0 = geometry_edit ? 11'd400 : 11'd496;
    wire [10:0] text_x0 = geometry_edit ? 11'd408 : 11'd504;

    wire [3:0] track_tens  = (track_num  >= 5'd10) ? 4'd1 : 4'd0;
    wire [3:0] track_units = (track_num  >= 5'd10) ? (track_num[3:0]  - 4'd10) : track_num[3:0];
    wire [3:0] count_tens  = (track_count>= 5'd10) ? 4'd1 : 4'd0;
    wire [3:0] count_units = (track_count>= 5'd10) ? (track_count[3:0]- 4'd10) : track_count[3:0];
    wire [3:0] image_tens  = (image_num  >= 5'd10) ? 4'd1 : 4'd0;
    wire [3:0] image_units = (image_num  >= 5'd10) ? (image_num[3:0]  - 4'd10) : image_num[3:0];
    wire [3:0] icount_tens = (image_count>= 5'd10) ? 4'd1 : 4'd0;
    wire [3:0] icount_units= (image_count>= 5'd10) ? (image_count[3:0]- 4'd10) : image_count[3:0];

    wire        text_in = (x >= text_x0) && (x < TEXT_X1) &&
                          (y >= TEXT_Y0) && (y < TEXT_Y1);
    wire [10:0] rel_x = x - text_x0;
    wire [9:0]  rel_y = y - TEXT_Y0;
    wire [3:0]  row   = rel_y[7:4];
    wire [3:0]  col   = rel_x[7:4];
    wire [2:0]  gx    = rel_x[3:1];
    wire [2:0]  gy    = rel_y[3:1];
    wire [3:0]  han_x = rel_x[3:0];
    wire [3:0]  han_y = rel_y[3:0];

    wire [7:0] ch   = geometry_edit ? size_char(row, col, image_size_mode,
                                                image_aspect_edit, image_aspect_mode,
                                                image_tens, image_units) :
                     panel_char(row, col, track_tens, track_units,
                                 count_tens, count_units, image_tens,
                                 image_units, icount_tens, icount_units,
                                 playing, effect, brightness, contrast,
                                 lyric_enabled, title_enabled);
    wire [4:0] bits = glyph_row(ch, gy);
    wire [15:0] han_bits = han_row(ch, han_y);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            panel_on <= 1'b0;
            text_on  <= 1'b0;
        end else begin
            panel_on <= enable && de &&
                        (x >= panel_x0) && (x < 11'd640) &&
                        (y >= PANEL_Y0) && (y < 10'd224);
            text_on  <= enable && de && text_in &&
                        (ch[7] ? han_bits[15-han_x] :
                         ((gx < 3'd5) && (gy < 3'd7) && bits[4-gx]));
        end
    end

    function [7:0] size_char;
        input [3:0] row, col;
        input [1:0] mode;
        input aspect_edit;
        input [1:0] aspect_mode;
        input [3:0] tens, units;
        reg [111:0] line_text;
        begin
            case (row)
                4'd0: line_text = {8'h80, 8'h81, 8'h84, 8'h85, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd1: line_text = {8'h80, 8'h81, 8'h20, 8'h30, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd2: line_text = {8'h36, 8'h34, 8'h30, 8'h20, 8'h58, 8'h20, 8'h34, 8'h38, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd3: line_text = {8'h88, 8'h89, 8'h33, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd4: line_text = {8'h88, 8'h89, 8'h34, 8'h8E, 8'h8F, 8'h90, 8'h91, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                default: line_text = {14{8'h20}};
            endcase
            if (row == 0 && aspect_edit) line_text = {8'h80, 8'h81, 8'h82, 8'h83, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
            if (row == 2) begin
                if (aspect_edit) begin
                    case (aspect_mode)
                        2'd0: line_text = {8'h86, 8'h87, 8'h82, 8'h83, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                        2'd1: line_text = {8'h34, 8'h3A, 8'h33, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                        2'd2: line_text = {8'h31, 8'h36, 8'h3A, 8'h39, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                        2'd3: line_text = {8'h31, 8'h3A, 8'h31, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                    endcase
                end else case (mode)
                    2'd0: line_text = {8'h36, 8'h34, 8'h30, 8'h20, 8'h58, 8'h20, 8'h34, 8'h38, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                    2'd1: line_text = {8'h35, 8'h31, 8'h32, 8'h20, 8'h58, 8'h20, 8'h33, 8'h38, 8'h34, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                    2'd2: line_text = {8'h33, 8'h32, 8'h30, 8'h20, 8'h58, 8'h20, 8'h32, 8'h34, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                    default: line_text = {8'h36, 8'h34, 8'h30, 8'h20, 8'h58, 8'h20, 8'h34, 8'h38, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                endcase
            end
            size_char = (col < 14) ? (line_text >> ((13-col)*8)) : 8'h20;
            if (row == 1) begin
                if (col == 3) size_char = 8'h30 + tens;
                if (col == 4) size_char = 8'h30 + units;
            end
        end
    endfunction

    // One 16-pixel cell per Chinese character; numbers use the existing ASCII font.
    function [7:0] panel_char;
        input [3:0] row, col;
        input [3:0] track_tens, track_units, count_tens, count_units;
        input [3:0] image_tens, image_units, icount_tens, icount_units;
        input playing;
        input [1:0] effect;
        input [3:0] brightness, contrast;
        input lyric_enabled, title_enabled;
        reg [111:0] line_text;
        begin
            case (row)
                4'd0: line_text = {8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd1: line_text = {8'h97, 8'h98, 8'h20, 8'h30, 8'h30, 8'h2F, 8'h30, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd2: line_text = {8'h99, 8'h9A, 8'h20, 8'h94, 8'h95, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd3: line_text = {8'h9D, 8'h9E, 8'h20, 8'h9F, 8'h8A, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd4: line_text = {8'hA5, 8'hA6, 8'h20, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd5: line_text = {8'hA7, 8'h82, 8'hA6, 8'h20, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd6: line_text = {8'hA8, 8'hA9, 8'h20, 8'hAA, 8'hAB, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd7: line_text = {8'hA8, 8'hAE, 8'h20, 8'hAA, 8'hAB, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                4'd8: line_text = {8'h80, 8'h81, 8'h20, 8'h30, 8'h30, 8'h2F, 8'h30, 8'h30, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                default: line_text = {14{8'h20}};
            endcase
            panel_char = (col < 14) ? (line_text >> ((13-col)*8)) : 8'h20;
            case (row)
                4'd1: case (col)
                    3: panel_char=8'h30 + track_tens;
                    4: panel_char=8'h30 + track_units;
                    6: panel_char=8'h30 + count_tens;
                    7: panel_char=8'h30 + count_units;
                endcase
                4'd2: if (!playing) begin
                    if (col == 3) panel_char=8'h9B;
                    if (col == 4) panel_char=8'h9C;
                end
                4'd3: case (effect)
                    2'd0: line_text = {8'h9D, 8'h9E, 8'h20, 8'h9F, 8'h8A, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                    2'd1: line_text = {8'h9D, 8'h9E, 8'h20, 8'hA0, 8'hA1, 8'hA0, 8'hA2, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                    2'd2: line_text = {8'h9D, 8'h9E, 8'h20, 8'hA3, 8'hA4, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                    default: line_text = {8'h9D, 8'h9E, 8'h20, 8'h9F, 8'h8A, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                endcase
                4'd4: if (col == 3) panel_char=8'h30 + brightness;
                4'd5: if (col == 4) panel_char=8'h30 + contrast;
                4'd6: if (!lyric_enabled) begin
                    if (col == 3) panel_char=8'hAC;
                    if (col == 4) panel_char=8'hAD;
                end
                4'd7: if (!title_enabled) begin
                    if (col == 3) panel_char=8'hAC;
                    if (col == 4) panel_char=8'hAD;
                end

                4'd8: case (col)
                    3: panel_char=8'h30 + image_tens;
                    4: panel_char=8'h30 + image_units;
                    6: panel_char=8'h30 + icount_tens;
                    7: panel_char=8'h30 + icount_units;
                endcase
            endcase
            if (row == 4'd3 && col < 14)
                panel_char = line_text >> ((13-col)*8);
        end
    endfunction

    function [15:0] han_row;
        input [7:0] ch;
        input [3:0] row;
        begin
            han_row = 16'h0000;
            case (ch)
                8'h80: case (row) // 图
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h7FFC;
                    4'd2: han_row=16'h200C;
                    4'd3: han_row=16'h220C;
                    4'd4: han_row=16'h27CC;
                    4'd5: han_row=16'h2E4C;
                    4'd6: han_row=16'h2B8C;
                    4'd7: han_row=16'h23CC;
                    4'd8: han_row=16'h2D3C;
                    4'd9: han_row=16'h218C;
                    4'd10: han_row=16'h220C;
                    4'd11: han_row=16'h218C;
                    4'd12: han_row=16'h200C;
                    4'd13: han_row=16'h7FFC;
                    4'd14: han_row=16'h6000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h81: case (row) // 片
                    4'd0: han_row=16'h1040;
                    4'd1: han_row=16'h1040;
                    4'd2: han_row=16'h1040;
                    4'd3: han_row=16'h1040;
                    4'd4: han_row=16'h1FFC;
                    4'd5: han_row=16'h1000;
                    4'd6: han_row=16'h1000;
                    4'd7: han_row=16'h1FE0;
                    4'd8: han_row=16'h1020;
                    4'd9: han_row=16'h1020;
                    4'd10: han_row=16'h3020;
                    4'd11: han_row=16'h2020;
                    4'd12: han_row=16'h6020;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h82: case (row) // 比
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h2080;
                    4'd2: han_row=16'h2080;
                    4'd3: han_row=16'h2080;
                    4'd4: han_row=16'h209C;
                    4'd5: han_row=16'h20B0;
                    4'd6: han_row=16'h3EC0;
                    4'd7: han_row=16'h2080;
                    4'd8: han_row=16'h2080;
                    4'd9: han_row=16'h2080;
                    4'd10: han_row=16'h2280;
                    4'd11: han_row=16'h2C84;
                    4'd12: han_row=16'h708C;
                    4'd13: han_row=16'h20F8;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h83: case (row) // 例
                    4'd0: han_row=16'h1804;
                    4'd1: han_row=16'h17C4;
                    4'd2: han_row=16'h1224;
                    4'd3: han_row=16'h3224;
                    4'd4: han_row=16'h73A4;
                    4'd5: han_row=16'h52A4;
                    4'd6: han_row=16'h54A4;
                    4'd7: han_row=16'h1EA4;
                    4'd8: han_row=16'h11A4;
                    4'd9: han_row=16'h1124;
                    4'd10: han_row=16'h1104;
                    4'd11: han_row=16'h1204;
                    4'd12: han_row=16'h141C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h84: case (row) // 尺
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h1FF8;
                    4'd2: han_row=16'h1008;
                    4'd3: han_row=16'h1008;
                    4'd4: han_row=16'h1008;
                    4'd5: han_row=16'h1FF8;
                    4'd6: han_row=16'h1FF8;
                    4'd7: han_row=16'h1100;
                    4'd8: han_row=16'h1080;
                    4'd9: han_row=16'h1080;
                    4'd10: han_row=16'h3040;
                    4'd11: han_row=16'h2060;
                    4'd12: han_row=16'h6038;
                    4'd13: han_row=16'h400C;
                    4'd14: han_row=16'h4000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h85: case (row) // 寸
                    4'd0: han_row=16'h0060;
                    4'd1: han_row=16'h0060;
                    4'd2: han_row=16'h0060;
                    4'd3: han_row=16'h7FFC;
                    4'd4: han_row=16'h0060;
                    4'd5: han_row=16'h0060;
                    4'd6: han_row=16'h1060;
                    4'd7: han_row=16'h1860;
                    4'd8: han_row=16'h0C60;
                    4'd9: han_row=16'h0460;
                    4'd10: han_row=16'h0060;
                    4'd11: han_row=16'h0060;
                    4'd12: han_row=16'h01C0;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h86: case (row) // 原
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h0004;
                    4'd2: han_row=16'h3FFC;
                    4'd3: han_row=16'h3080;
                    4'd4: han_row=16'h37F8;
                    4'd5: han_row=16'h3408;
                    4'd6: han_row=16'h37F8;
                    4'd7: han_row=16'h3408;
                    4'd8: han_row=16'h3408;
                    4'd9: han_row=16'h27F8;
                    4'd10: han_row=16'h20C0;
                    4'd11: han_row=16'h26D0;
                    4'd12: han_row=16'h6CC8;
                    4'd13: han_row=16'h4980;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h87: case (row) // 始
                    4'd0: han_row=16'h1040;
                    4'd1: han_row=16'h10C0;
                    4'd2: han_row=16'h3090;
                    4'd3: han_row=16'h7D18;
                    4'd4: han_row=16'h271C;
                    4'd5: han_row=16'h27E4;
                    4'd6: han_row=16'h2800;
                    4'd7: han_row=16'h49F8;
                    4'd8: han_row=16'h6908;
                    4'd9: han_row=16'h1908;
                    4'd10: han_row=16'h1D08;
                    4'd11: han_row=16'h25F8;
                    4'd12: han_row=16'h6108;
                    4'd13: han_row=16'h0108;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h88: case (row) // 按
                    4'd0: han_row=16'h1040;
                    4'd1: han_row=16'h1060;
                    4'd2: han_row=16'h13FC;
                    4'd3: han_row=16'h7A04;
                    4'd4: han_row=16'h1244;
                    4'd5: han_row=16'h10C0;
                    4'd6: han_row=16'h1BFC;
                    4'd7: han_row=16'h3098;
                    4'd8: han_row=16'h5110;
                    4'd9: han_row=16'h13B0;
                    4'd10: han_row=16'h1060;
                    4'd11: han_row=16'h10F8;
                    4'd12: han_row=16'h770C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h89: case (row) // 键
                    4'd0: han_row=16'h3020;
                    4'd1: han_row=16'h27F8;
                    4'd2: han_row=16'h7A28;
                    4'd3: han_row=16'h42FC;
                    4'd4: han_row=16'h0A28;
                    4'd5: han_row=16'h3778;
                    4'd6: han_row=16'h2520;
                    4'd7: han_row=16'h79F8;
                    4'd8: han_row=16'h2520;
                    4'd9: han_row=16'h26FC;
                    4'd10: han_row=16'h2A20;
                    4'd11: han_row=16'h3320;
                    4'd12: han_row=16'h24FC;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h8A: case (row) // 切
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h1000;
                    4'd2: han_row=16'h13FC;
                    4'd3: han_row=16'h1044;
                    4'd4: han_row=16'h1044;
                    4'd5: han_row=16'h3C44;
                    4'd6: han_row=16'h7044;
                    4'd7: han_row=16'h104C;
                    4'd8: han_row=16'h10CC;
                    4'd9: han_row=16'h1488;
                    4'd10: han_row=16'h1C88;
                    4'd11: han_row=16'h3108;
                    4'd12: han_row=16'h0308;
                    4'd13: han_row=16'h0638;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h8B: case (row) // 换
                    4'd0: han_row=16'h1080;
                    4'd1: han_row=16'h1100;
                    4'd2: han_row=16'h11F0;
                    4'd3: han_row=16'h7A20;
                    4'd4: han_row=16'h17F8;
                    4'd5: han_row=16'h1248;
                    4'd6: han_row=16'h1A48;
                    4'd7: han_row=16'h3248;
                    4'd8: han_row=16'h57FC;
                    4'd9: han_row=16'h1060;
                    4'd10: han_row=16'h10A0;
                    4'd11: han_row=16'h1118;
                    4'd12: han_row=16'h760C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h8C: case (row) // 模
                    4'd0: han_row=16'h1090;
                    4'd1: han_row=16'h13FC;
                    4'd2: han_row=16'h1090;
                    4'd3: han_row=16'h7FF8;
                    4'd4: han_row=16'h1308;
                    4'd5: han_row=16'h33F8;
                    4'd6: han_row=16'h3B08;
                    4'd7: han_row=16'h77F8;
                    4'd8: han_row=16'h5040;
                    4'd9: han_row=16'h13FC;
                    4'd10: han_row=16'h1060;
                    4'd11: han_row=16'h1090;
                    4'd12: han_row=16'h170C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h8D: case (row) // 式
                    4'd0: han_row=16'h00A0;
                    4'd1: han_row=16'h0090;
                    4'd2: han_row=16'h0090;
                    4'd3: han_row=16'h7FFC;
                    4'd4: han_row=16'h0080;
                    4'd5: han_row=16'h0080;
                    4'd6: han_row=16'h3EC0;
                    4'd7: han_row=16'h0840;
                    4'd8: han_row=16'h0840;
                    4'd9: han_row=16'h0860;
                    4'd10: han_row=16'h0B24;
                    4'd11: han_row=16'h7C34;
                    4'd12: han_row=16'h601C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h8E: case (row) // 保
                    4'd0: han_row=16'h0BF8;
                    4'd1: han_row=16'h1208;
                    4'd2: han_row=16'h1208;
                    4'd3: han_row=16'h3208;
                    4'd4: han_row=16'h33F8;
                    4'd5: han_row=16'h5040;
                    4'd6: han_row=16'h5040;
                    4'd7: han_row=16'h17FC;
                    4'd8: han_row=16'h1160;
                    4'd9: han_row=16'h1350;
                    4'd10: han_row=16'h1258;
                    4'd11: han_row=16'h1C4C;
                    4'd12: han_row=16'h1040;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h8F: case (row) // 存
                    4'd0: han_row=16'h0300;
                    4'd1: han_row=16'h0200;
                    4'd2: han_row=16'h3FFC;
                    4'd3: han_row=16'h0400;
                    4'd4: han_row=16'h0800;
                    4'd5: han_row=16'h1BF8;
                    4'd6: han_row=16'h1030;
                    4'd7: han_row=16'h7040;
                    4'd8: han_row=16'h57FC;
                    4'd9: han_row=16'h1040;
                    4'd10: han_row=16'h1040;
                    4'd11: han_row=16'h1040;
                    4'd12: han_row=16'h10C0;
                    4'd13: han_row=16'h0080;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h90: case (row) // 设
                    4'd0: han_row=16'h21E0;
                    4'd1: han_row=16'h3120;
                    4'd2: han_row=16'h1320;
                    4'd3: han_row=16'h0220;
                    4'd4: han_row=16'h723C;
                    4'd5: han_row=16'h141C;
                    4'd6: han_row=16'h17F8;
                    4'd7: han_row=16'h1310;
                    4'd8: han_row=16'h1130;
                    4'd9: han_row=16'h19A0;
                    4'd10: han_row=16'h18C0;
                    4'd11: han_row=16'h10E0;
                    4'd12: han_row=16'h071C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h91: case (row) // 置
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h3FF8;
                    4'd2: han_row=16'h2448;
                    4'd3: han_row=16'h3FF8;
                    4'd4: han_row=16'h0100;
                    4'd5: han_row=16'h3FF8;
                    4'd6: han_row=16'h0100;
                    4'd7: han_row=16'h1FF0;
                    4'd8: han_row=16'h1010;
                    4'd9: han_row=16'h1FF0;
                    4'd10: han_row=16'h1FF0;
                    4'd11: han_row=16'h1010;
                    4'd12: han_row=16'h1FF0;
                    4'd13: han_row=16'h7FFC;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h92: case (row) // 音
                    4'd0: han_row=16'h0100;
                    4'd1: han_row=16'h3FF8;
                    4'd2: han_row=16'h0000;
                    4'd3: han_row=16'h0C60;
                    4'd4: han_row=16'h0440;
                    4'd5: han_row=16'h7FFC;
                    4'd6: han_row=16'h0000;
                    4'd7: han_row=16'h1FF0;
                    4'd8: han_row=16'h1010;
                    4'd9: han_row=16'h1FF0;
                    4'd10: han_row=16'h1010;
                    4'd11: han_row=16'h1010;
                    4'd12: han_row=16'h1FF0;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h93: case (row) // 乐
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h0030;
                    4'd2: han_row=16'h1FE0;
                    4'd3: han_row=16'h1180;
                    4'd4: han_row=16'h1180;
                    4'd5: han_row=16'h3180;
                    4'd6: han_row=16'h2180;
                    4'd7: han_row=16'h3FFC;
                    4'd8: han_row=16'h0180;
                    4'd9: han_row=16'h0DA0;
                    4'd10: han_row=16'h1990;
                    4'd11: han_row=16'h3188;
                    4'd12: han_row=16'h618C;
                    4'd13: han_row=16'h0700;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h94: case (row) // 播
                    4'd0: han_row=16'h1038;
                    4'd1: han_row=16'h13C0;
                    4'd2: han_row=16'h1248;
                    4'd3: han_row=16'h7950;
                    4'd4: han_row=16'h17FC;
                    4'd5: han_row=16'h1150;
                    4'd6: han_row=16'h1B58;
                    4'd7: han_row=16'h77FC;
                    4'd8: han_row=16'h1248;
                    4'd9: han_row=16'h13F8;
                    4'd10: han_row=16'h1248;
                    4'd11: han_row=16'h1248;
                    4'd12: han_row=16'h73F8;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h95: case (row) // 放
                    4'd0: han_row=16'h1060;
                    4'd1: han_row=16'h1840;
                    4'd2: han_row=16'h0040;
                    4'd3: han_row=16'h7EFC;
                    4'd4: han_row=16'h1088;
                    4'd5: han_row=16'h1188;
                    4'd6: han_row=16'h1E58;
                    4'd7: han_row=16'h1250;
                    4'd8: han_row=16'h3250;
                    4'd9: han_row=16'h2230;
                    4'd10: han_row=16'h2220;
                    4'd11: han_row=16'h6658;
                    4'd12: han_row=16'h4D8C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h96: case (row) // 器
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h3EF8;
                    4'd2: han_row=16'h2288;
                    4'd3: han_row=16'h2288;
                    4'd4: han_row=16'h3EF8;
                    4'd5: han_row=16'h0120;
                    4'd6: han_row=16'h7FFC;
                    4'd7: han_row=16'h06C0;
                    4'd8: han_row=16'h7C7C;
                    4'd9: han_row=16'h4000;
                    4'd10: han_row=16'h3EF8;
                    4'd11: han_row=16'h2288;
                    4'd12: han_row=16'h3EF8;
                    4'd13: han_row=16'h2288;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h97: case (row) // 曲
                    4'd0: han_row=16'h0440;
                    4'd1: han_row=16'h0440;
                    4'd2: han_row=16'h0440;
                    4'd3: han_row=16'h7FFC;
                    4'd4: han_row=16'h644C;
                    4'd5: han_row=16'h644C;
                    4'd6: han_row=16'h644C;
                    4'd7: han_row=16'h7FFC;
                    4'd8: han_row=16'h644C;
                    4'd9: han_row=16'h644C;
                    4'd10: han_row=16'h644C;
                    4'd11: han_row=16'h7FFC;
                    4'd12: han_row=16'h600C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h98: case (row) // 目
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h3FF8;
                    4'd2: han_row=16'h1018;
                    4'd3: han_row=16'h1018;
                    4'd4: han_row=16'h1FF8;
                    4'd5: han_row=16'h1018;
                    4'd6: han_row=16'h1018;
                    4'd7: han_row=16'h1018;
                    4'd8: han_row=16'h1FF8;
                    4'd9: han_row=16'h1018;
                    4'd10: han_row=16'h1018;
                    4'd11: han_row=16'h1FF8;
                    4'd12: han_row=16'h3018;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h99: case (row) // 状
                    4'd0: han_row=16'h0840;
                    4'd1: han_row=16'h0858;
                    4'd2: han_row=16'h4848;
                    4'd3: han_row=16'h6840;
                    4'd4: han_row=16'h2BFC;
                    4'd5: han_row=16'h0840;
                    4'd6: han_row=16'h1860;
                    4'd7: han_row=16'h1860;
                    4'd8: han_row=16'h28A0;
                    4'd9: han_row=16'h48B0;
                    4'd10: han_row=16'h0990;
                    4'd11: han_row=16'h0908;
                    4'd12: han_row=16'h0E0C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h9A: case (row) // 态
                    4'd0: han_row=16'h0300;
                    4'd1: han_row=16'h0200;
                    4'd2: han_row=16'h7FFC;
                    4'd3: han_row=16'h06C0;
                    4'd4: han_row=16'h0440;
                    4'd5: han_row=16'h0A20;
                    4'd6: han_row=16'h311C;
                    4'd7: han_row=16'h6000;
                    4'd8: han_row=16'h0100;
                    4'd9: han_row=16'h2498;
                    4'd10: han_row=16'h240C;
                    4'd11: han_row=16'h4434;
                    4'd12: han_row=16'h47E0;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h9B: case (row) // 暂
                    4'd0: han_row=16'h0818;
                    4'd1: han_row=16'h7FE0;
                    4'd2: han_row=16'h1080;
                    4'd3: han_row=16'h24FC;
                    4'd4: han_row=16'h3E90;
                    4'd5: han_row=16'h3E90;
                    4'd6: han_row=16'h4590;
                    4'd7: han_row=16'h0000;
                    4'd8: han_row=16'h1FF0;
                    4'd9: han_row=16'h1010;
                    4'd10: han_row=16'h1FF0;
                    4'd11: han_row=16'h1010;
                    4'd12: han_row=16'h1FF0;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h9C: case (row) // 停
                    4'd0: han_row=16'h1040;
                    4'd1: han_row=16'h17FC;
                    4'd2: han_row=16'h3000;
                    4'd3: han_row=16'h33F8;
                    4'd4: han_row=16'h7208;
                    4'd5: han_row=16'h53F8;
                    4'd6: han_row=16'h1FFC;
                    4'd7: han_row=16'h1804;
                    4'd8: han_row=16'h1208;
                    4'd9: han_row=16'h11F0;
                    4'd10: han_row=16'h1040;
                    4'd11: han_row=16'h1040;
                    4'd12: han_row=16'h10C0;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h9D: case (row) // 转
                    4'd0: han_row=16'h1060;
                    4'd1: han_row=16'h1040;
                    4'd2: han_row=16'h7DFC;
                    4'd3: han_row=16'h2040;
                    4'd4: han_row=16'h2840;
                    4'd5: han_row=16'h4BFC;
                    4'd6: han_row=16'h7C80;
                    4'd7: han_row=16'h08F8;
                    4'd8: han_row=16'h0808;
                    4'd9: han_row=16'hFC10;
                    4'd10: han_row=16'h49A0;
                    4'd11: han_row=16'h0860;
                    4'd12: han_row=16'h0830;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h9E: case (row) // 场
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h13F8;
                    4'd2: han_row=16'h1010;
                    4'd3: han_row=16'h1020;
                    4'd4: han_row=16'h1040;
                    4'd5: han_row=16'h7D80;
                    4'd6: han_row=16'h13FC;
                    4'd7: han_row=16'h10B4;
                    4'd8: han_row=16'h10A4;
                    4'd9: han_row=16'h1524;
                    4'd10: han_row=16'h1F64;
                    4'd11: han_row=16'h6244;
                    4'd12: han_row=16'h008C;
                    4'd13: han_row=16'h0318;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'h9F: case (row) // 直
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h0100;
                    4'd2: han_row=16'h7FFC;
                    4'd3: han_row=16'h0100;
                    4'd4: han_row=16'h0100;
                    4'd5: han_row=16'h1FF0;
                    4'd6: han_row=16'h1010;
                    4'd7: han_row=16'h1FF0;
                    4'd8: han_row=16'h1010;
                    4'd9: han_row=16'h1FF0;
                    4'd10: han_row=16'h1010;
                    4'd11: han_row=16'h1FF0;
                    4'd12: han_row=16'h1010;
                    4'd13: han_row=16'h7FFC;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA0: case (row) // 淡
                    4'd0: han_row=16'h6040;
                    4'd1: han_row=16'h3298;
                    4'd2: han_row=16'h0490;
                    4'd3: han_row=16'h00E0;
                    4'd4: han_row=16'h4118;
                    4'd5: han_row=16'h360C;
                    4'd6: han_row=16'h0440;
                    4'd7: han_row=16'h0248;
                    4'd8: han_row=16'h12D8;
                    4'd9: han_row=16'h34C0;
                    4'd10: han_row=16'h20A0;
                    4'd11: han_row=16'h6318;
                    4'd12: han_row=16'h4E0C;
                    4'd13: han_row=16'h0400;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA1: case (row) // 入
                    4'd0: han_row=16'h0400;
                    4'd1: han_row=16'h0600;
                    4'd2: han_row=16'h0300;
                    4'd3: han_row=16'h0100;
                    4'd4: han_row=16'h0180;
                    4'd5: han_row=16'h0280;
                    4'd6: han_row=16'h02C0;
                    4'd7: han_row=16'h0640;
                    4'd8: han_row=16'h0C60;
                    4'd9: han_row=16'h0830;
                    4'd10: han_row=16'h1018;
                    4'd11: han_row=16'h600C;
                    4'd12: han_row=16'h4000;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA2: case (row) // 出
                    4'd0: han_row=16'h0100;
                    4'd1: han_row=16'h2118;
                    4'd2: han_row=16'h2118;
                    4'd3: han_row=16'h2118;
                    4'd4: han_row=16'h2118;
                    4'd5: han_row=16'h3FF8;
                    4'd6: han_row=16'h0100;
                    4'd7: han_row=16'h2108;
                    4'd8: han_row=16'h2108;
                    4'd9: han_row=16'h2108;
                    4'd10: han_row=16'h2108;
                    4'd11: han_row=16'h3FF8;
                    4'd12: han_row=16'h0008;
                    4'd13: han_row=16'h0008;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA3: case (row) // 滑
                    4'd0: han_row=16'h23F8;
                    4'd1: han_row=16'h3210;
                    4'd2: han_row=16'h03D0;
                    4'd3: han_row=16'h0250;
                    4'd4: han_row=16'h6FFC;
                    4'd5: han_row=16'h2804;
                    4'd6: han_row=16'h0BF4;
                    4'd7: han_row=16'h1210;
                    4'd8: han_row=16'h23F0;
                    4'd9: han_row=16'h2210;
                    4'd10: han_row=16'h63F0;
                    4'd11: han_row=16'h4210;
                    4'd12: han_row=16'h0230;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA4: case (row) // 动
                    4'd0: han_row=16'h0020;
                    4'd1: han_row=16'h0020;
                    4'd2: han_row=16'h7E20;
                    4'd3: han_row=16'h01FC;
                    4'd4: han_row=16'h0024;
                    4'd5: han_row=16'h7E24;
                    4'd6: han_row=16'h1024;
                    4'd7: han_row=16'h1064;
                    4'd8: han_row=16'h2244;
                    4'd9: han_row=16'h2244;
                    4'd10: han_row=16'h7FC4;
                    4'd11: han_row=16'h0084;
                    4'd12: han_row=16'h0118;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA5: case (row) // 亮
                    4'd0: han_row=16'h0100;
                    4'd1: han_row=16'h7FFC;
                    4'd2: han_row=16'h0000;
                    4'd3: han_row=16'h1FF0;
                    4'd4: han_row=16'h1830;
                    4'd5: han_row=16'h1FF0;
                    4'd6: han_row=16'h0000;
                    4'd7: han_row=16'h7FFC;
                    4'd8: han_row=16'h4004;
                    4'd9: han_row=16'h07C0;
                    4'd10: han_row=16'h0440;
                    4'd11: han_row=16'h0C44;
                    4'd12: han_row=16'h387C;
                    4'd13: han_row=16'h2000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA6: case (row) // 度
                    4'd0: han_row=16'h0180;
                    4'd1: han_row=16'h3FF8;
                    4'd2: han_row=16'h2000;
                    4'd3: han_row=16'h2220;
                    4'd4: han_row=16'h2FF8;
                    4'd5: han_row=16'h2220;
                    4'd6: han_row=16'h23E0;
                    4'd7: han_row=16'h2000;
                    4'd8: han_row=16'h2FF0;
                    4'd9: han_row=16'h2220;
                    4'd10: han_row=16'h2140;
                    4'd11: han_row=16'h4080;
                    4'd12: han_row=16'h4F7C;
                    4'd13: han_row=16'h1004;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA7: case (row) // 对
                    4'd0: han_row=16'h0018;
                    4'd1: han_row=16'h0010;
                    4'd2: han_row=16'h7E10;
                    4'd3: han_row=16'h05FC;
                    4'd4: han_row=16'h0410;
                    4'd5: han_row=16'h2410;
                    4'd6: han_row=16'h1590;
                    4'd7: han_row=16'h1890;
                    4'd8: han_row=16'h0CD0;
                    4'd9: han_row=16'h1410;
                    4'd10: han_row=16'h3210;
                    4'd11: han_row=16'h6210;
                    4'd12: han_row=16'h4030;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA8: case (row) // 歌
                    4'd0: han_row=16'h0020;
                    4'd1: han_row=16'h7F60;
                    4'd2: han_row=16'h7A40;
                    4'd3: han_row=16'h2A7C;
                    4'd4: han_row=16'h3A8C;
                    4'd5: han_row=16'h0220;
                    4'd6: han_row=16'h7FA0;
                    4'd7: han_row=16'h0220;
                    4'd8: han_row=16'h7A30;
                    4'd9: han_row=16'h6A30;
                    4'd10: han_row=16'h7A58;
                    4'd11: han_row=16'h6ACC;
                    4'd12: han_row=16'h0F84;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hA9: case (row) // 词
                    4'd0: han_row=16'h2000;
                    4'd1: han_row=16'h13FC;
                    4'd2: han_row=16'h1004;
                    4'd3: han_row=16'h03F4;
                    4'd4: han_row=16'h7004;
                    4'd5: han_row=16'h1004;
                    4'd6: han_row=16'h13E4;
                    4'd7: han_row=16'h1224;
                    4'd8: han_row=16'h1224;
                    4'd9: han_row=16'h13E4;
                    4'd10: han_row=16'h1A24;
                    4'd11: han_row=16'h1004;
                    4'd12: han_row=16'h201C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hAA: case (row) // 开
                    4'd0: han_row=16'h0000;
                    4'd1: han_row=16'h2008;
                    4'd2: han_row=16'h3FF8;
                    4'd3: han_row=16'h0460;
                    4'd4: han_row=16'h0460;
                    4'd5: han_row=16'h0460;
                    4'd6: han_row=16'h0460;
                    4'd7: han_row=16'h7FFC;
                    4'd8: han_row=16'h0460;
                    4'd9: han_row=16'h0460;
                    4'd10: han_row=16'h0C60;
                    4'd11: han_row=16'h0860;
                    4'd12: han_row=16'h1860;
                    4'd13: han_row=16'h7060;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hAB: case (row) // 启
                    4'd0: han_row=16'h0180;
                    4'd1: han_row=16'h0080;
                    4'd2: han_row=16'h1FF8;
                    4'd3: han_row=16'h1018;
                    4'd4: han_row=16'h1018;
                    4'd5: han_row=16'h1FF8;
                    4'd6: han_row=16'h1000;
                    4'd7: han_row=16'h1000;
                    4'd8: han_row=16'h3FF8;
                    4'd9: han_row=16'h2C08;
                    4'd10: han_row=16'h2C08;
                    4'd11: han_row=16'h6FF8;
                    4'd12: han_row=16'h4C08;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hAC: case (row) // 关
                    4'd0: han_row=16'h0860;
                    4'd1: han_row=16'h0440;
                    4'd2: han_row=16'h0440;
                    4'd3: han_row=16'h3FF8;
                    4'd4: han_row=16'h0100;
                    4'd5: han_row=16'h0100;
                    4'd6: han_row=16'h0100;
                    4'd7: han_row=16'h7FFC;
                    4'd8: han_row=16'h0180;
                    4'd9: han_row=16'h0280;
                    4'd10: han_row=16'h0660;
                    4'd11: han_row=16'h1838;
                    4'd12: han_row=16'h701C;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hAD: case (row) // 闭
                    4'd0: han_row=16'h13FC;
                    4'd1: han_row=16'h1BFC;
                    4'd2: han_row=16'h008C;
                    4'd3: han_row=16'h608C;
                    4'd4: han_row=16'h608C;
                    4'd5: han_row=16'h7FEC;
                    4'd6: han_row=16'h618C;
                    4'd7: han_row=16'h628C;
                    4'd8: han_row=16'h668C;
                    4'd9: han_row=16'h6C8C;
                    4'd10: han_row=16'h788C;
                    4'd11: han_row=16'h638C;
                    4'd12: han_row=16'h6018;
                    4'd13: han_row=16'h0000;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
                8'hAE: case (row) // 名
                    4'd0: han_row=16'h0600;
                    4'd1: han_row=16'h0400;
                    4'd2: han_row=16'h0FF0;
                    4'd3: han_row=16'h1420;
                    4'd4: han_row=16'h2640;
                    4'd5: han_row=16'h0380;
                    4'd6: han_row=16'h0300;
                    4'd7: han_row=16'h0FF8;
                    4'd8: han_row=16'h7808;
                    4'd9: han_row=16'h4808;
                    4'd10: han_row=16'h0808;
                    4'd11: han_row=16'h0FF8;
                    4'd12: han_row=16'h0808;
                    4'd13: han_row=16'h0800;
                    4'd14: han_row=16'h0000;
                    4'd15: han_row=16'h0000;
                endcase
            endcase
        end
    endfunction

    function [4:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        begin
            case (ch)
                8'h30: case (row) // '0'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10011;
                    3'd3: glyph_row = 5'b10101;
                    3'd4: glyph_row = 5'b11001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h31: case (row) // '1'
                    3'd0: glyph_row = 5'b00100;
                    3'd1: glyph_row = 5'b01100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h32: case (row) // '2'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b00001;
                    3'd3: glyph_row = 5'b00010;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b01000;
                    3'd6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
                8'h33: case (row) // '3'
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b00001;
                    3'd2: glyph_row = 5'b00001;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h34: case (row) // '4'
                    3'd0: glyph_row = 5'b00010;
                    3'd1: glyph_row = 5'b00110;
                    3'd2: glyph_row = 5'b01010;
                    3'd3: glyph_row = 5'b10010;
                    3'd4: glyph_row = 5'b11111;
                    3'd5: glyph_row = 5'b00010;
                    3'd6: glyph_row = 5'b00010;
                    default: glyph_row = 5'b00000;
                endcase
                8'h35: case (row) // '5'
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h36: case (row) // '6'
                    3'd0: glyph_row = 5'b00110;
                    3'd1: glyph_row = 5'b01000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h37: case (row) // '7'
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b00001;
                    3'd2: glyph_row = 5'b00010;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b01000;
                    3'd5: glyph_row = 5'b01000;
                    3'd6: glyph_row = 5'b01000;
                    default: glyph_row = 5'b00000;
                endcase
                8'h38: case (row) // '8'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h39: case (row) // '9'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b01111;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00010;
                    3'd6: glyph_row = 5'b01100;
                    default: glyph_row = 5'b00000;
                endcase
                8'h41: case (row) // 'A'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11111;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
                8'h42: case (row) // 'B'
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h43: case (row) // 'C'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b10000;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h44: case (row) // 'D'
                    0,6: glyph_row = 5'b11110;
                    1,2,3,4,5: glyph_row = 5'b10001;
                    default: glyph_row = 5'd0;
                endcase
                8'h45: case (row) // 'E'
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    3'd6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
                8'h46: case (row) // 'F'
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    3'd6: glyph_row = 5'b10000;
                    default: glyph_row = 5'b00000;
                endcase
                8'h47: case (row) // 'G'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b10111;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01111;
                    default: glyph_row = 5'b00000;
                endcase
                8'h48: case (row) // 'H'
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11111;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
                8'h49: case (row) // 'I'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b00100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h4B: case (row) // 'K'
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b10010;
                    3'd2: glyph_row = 5'b10100;
                    3'd3: glyph_row = 5'b11000;
                    3'd4: glyph_row = 5'b10100;
                    3'd5: glyph_row = 5'b10010;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
                8'h4C: case (row) // 'L'
                    3'd0: glyph_row = 5'b10000;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b10000;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    3'd6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
                8'h4D: case (row) // 'M'
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b11011;
                    3'd2: glyph_row = 5'b10101;
                    3'd3: glyph_row = 5'b10101;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
                8'h4E: case (row) // 'N'
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b11001;
                    3'd2: glyph_row = 5'b10101;
                    3'd3: glyph_row = 5'b10011;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
                8'h4F: case (row) // 'O'
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b10001;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h50: case (row) // 'P'
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    3'd6: glyph_row = 5'b10000;
                    default: glyph_row = 5'b00000;
                endcase
                8'h52: case (row) // 'R'
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10100;
                    3'd5: glyph_row = 5'b10010;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
                8'h53: case (row) // 'S'
                    3'd0: glyph_row = 5'b01111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h54: case (row) // 'T'
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b00100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    3'd6: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00000;
                endcase
                8'h55: case (row) // 'U'
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b10001;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                8'h58: case (row) // 'X'
                    0,6: glyph_row = 5'b10001;
                    1,5: glyph_row = 5'b10001;
                    2,4: glyph_row = 5'b01010;
                    3: glyph_row = 5'b00100;
                    default: glyph_row = 5'd0;
                endcase
                8'h5A: case (row) // 'Z'
                    0,6: glyph_row = 5'b11111;
                    1: glyph_row = 5'b00001;
                    2: glyph_row = 5'b00010;
                    3: glyph_row = 5'b00100;
                    4: glyph_row = 5'b01000;
                    5: glyph_row = 5'b10000;
                    default: glyph_row = 5'd0;
                endcase
                8'h59: case (row) // 'Y'
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b01010;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    3'd6: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00000;
                endcase
                8'h3A: case (row) // ':'
                    1,2,4,5: glyph_row = 5'b00100;
                    default: glyph_row = 5'd0;
                endcase
                8'h2F: case (row) // '/'
                    3'd0: glyph_row = 5'b00001;
                    3'd1: glyph_row = 5'b00010;
                    3'd2: glyph_row = 5'b00010;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b01000;
                    3'd5: glyph_row = 5'b01000;
                    3'd6: glyph_row = 5'b10000;
                    default: glyph_row = 5'b00000;
                endcase
                8'h2D: case (row) // '-'
                    3'd0: glyph_row = 5'b00000;
                    3'd1: glyph_row = 5'b00000;
                    3'd2: glyph_row = 5'b00000;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b00000;
                    3'd5: glyph_row = 5'b00000;
                    3'd6: glyph_row = 5'b00000;
                    default: glyph_row = 5'b00000;
                endcase
                8'h20: case (row) // ' '
                    3'd0: glyph_row = 5'b00000;
                    3'd1: glyph_row = 5'b00000;
                    3'd2: glyph_row = 5'b00000;
                    3'd3: glyph_row = 5'b00000;
                    3'd4: glyph_row = 5'b00000;
                    3'd5: glyph_row = 5'b00000;
                    3'd6: glyph_row = 5'b00000;
                    default: glyph_row = 5'b00000;
                endcase
                default: glyph_row = 5'b00000;
            endcase
        end
    endfunction
endmodule
