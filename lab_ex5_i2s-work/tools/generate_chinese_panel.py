"""Generate the fixed 16x16 Chinese glyph ROM for property_panel.v."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "src/user_source/hdl_source/property_panel.v"
FONT = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 15)

size_rows = ["图片比例", "图片尺寸", "图片", "原始比例", "按键切换模式", "按键保存设置"]
panel_rows = ["音乐播放器", "曲目", "状态播放暂停", "转场直切淡入淡出滑动", "亮度", "对比度", "歌词开启关闭", "歌名开启", "图片"]
chars = list(dict.fromkeys("".join(size_rows + panel_rows)))
ids = {ch: 0x80 + i for i, ch in enumerate(chars)}

def line(s):
    assert len(s) <= 14, s
    return "{" + ", ".join(f"8'h{ids[c]:02X}" if c in ids else f"8'h{ord(c):02X}" for c in s.ljust(14)) + "}"

def glyph(ch):
    im = Image.new("1", (16, 16))
    draw = ImageDraw.Draw(im)
    draw.text((8, 8), ch, font=FONT, fill=1, anchor="mm")
    return [sum((1 << (15-x)) for x in range(16) if im.getpixel((x, y))) for y in range(16)]

src = TARGET.read_text(encoding="utf-8")
start = src.index("    function [7:0] size_char;")
end = src.index("    function [4:0] glyph_row;", start)
code = """    function [7:0] size_char;
        input [3:0] row, col;
        input [1:0] mode;
        input aspect_edit;
        input [1:0] aspect_mode;
        input [3:0] tens, units;
        reg [111:0] line_text;
        begin
            case (row)
"""
size = ["图片尺寸", "图片 00", "640 X 480", "按键3切换模式", "按键4保存设置"]
for i, s in enumerate(size):
    code += f"                4'd{i}: line_text = {line(s)};\n"
code += """                default: line_text = {14{8'h20}};
            endcase
            if (row == 0 && aspect_edit) line_text = """ + line("图片比例") + """;
            if (row == 2) begin
                if (aspect_edit) begin
                    case (aspect_mode)
"""
for val, s in enumerate(["原始比例", "4:3", "16:9", "1:1"]):
    code += f"                        2'd{val}: line_text = {line(s)};\n"
code += """                    endcase
                end else case (mode)
"""
for val, s in enumerate(["640 X 480", "512 X 384", "320 X 240"]):
    code += f"                    2'd{val}: line_text = {line(s)};\n"
code += """                    default: line_text = """ + line("640 X 480") + """;
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
"""
rows = ["音乐播放器", "曲目 00/00", "状态 播放", "转场 直切", "亮度 0", "对比度 0", "歌词 开启", "歌名 开启", "图片 00/00"]
for i, s in enumerate(rows):
    code += f"                4'd{i}: line_text = {line(s)};\n"
code += """                default: line_text = {14{8'h20}};
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
"""
code += f"                    if (col == 3) panel_char=8'h{ids['暂']:02X};\n"
code += f"                    if (col == 4) panel_char=8'h{ids['停']:02X};\n"
code += """                end
                4'd3: case (effect)
"""
for val,s in [(0,"转场 直切"),(1,"转场 淡入淡出"),(2,"转场 滑动")]:
    code += f"                    2'd{val}: line_text = {line(s)};\n"
code += """                    default: line_text = """ + line("转场 直切") + """;
                endcase
                4'd4: if (col == 3) panel_char=8'h30 + brightness;
                4'd5: if (col == 4) panel_char=8'h30 + contrast;
"""
for row, flag in [(6, "lyric_enabled"), (7, "title_enabled")]:
    code += f"                4'd{row}: if (!{flag}) begin\n"
    code += f"                    if (col == 3) panel_char=8'h{ids['关']:02X};\n"
    code += f"                    if (col == 4) panel_char=8'h{ids['闭']:02X};\n"
    code += "                end\n"
code += """
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
"""
for ch, id in ids.items():
    code += f"                8'h{id:02X}: case (row) // {ch}\n"
    for y,bits in enumerate(glyph(ch)):
        code += f"                    4'd{y}: han_row=16'h{bits:04X};\n"
    code += "                endcase\n"
code += """            endcase
        end
    endfunction

"""
src = src[:start] + code + src[end:]
TARGET.write_text(src, encoding="utf-8")
