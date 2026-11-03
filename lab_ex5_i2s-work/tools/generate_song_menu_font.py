"""Generate the fixed song-name glyphs for the FPGA HDMI menu."""
import csv
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / "media" / "playlist.csv"
VERILOG = ROOT / "src" / "user_source" / "hdl_source" / "property_panel.v"
FONT = Path("C:/Windows/Fonts/msyh.ttc")
START = "    // BEGIN GENERATED SONG MENU FONT\n"
END = "    // END GENERATED SONG MENU FONT\n"

with CSV.open(encoding="utf-8-sig", newline="") as stream:
    titles = {int(row["track"]) - 1: row["title"] for row in csv.DictReader(stream)}
glyphs = list(dict.fromkeys("".join(titles.values())))
if len(glyphs) > 80:
    raise SystemExit("Song menu glyph table exceeds the reserved character range")
codes = {char: 0xB0 + idx for idx, char in enumerate(glyphs)}
font = ImageFont.truetype(str(FONT), 16)
lines = [START,
    "    function [7:0] song_name_char;\n",
    "        input [3:0] index, position;\n",
    "        begin\n",
    "            song_name_char = 8'h20;\n",
    "            case (index)\n"]
for index, title in sorted(titles.items()):
    lines.append(f"                4'd{index}: case (position)\n")
    for position, char in enumerate(title):
        lines.append(f"                    4'd{position}: song_name_char=8'h{codes[char]:02X}; // {char}\n")
    lines.append("                    default: ;\n                endcase\n")
lines += ["                default: ;\n", "            endcase\n", "        end\n", "    endfunction\n",
          "    function [15:0] song_glyph_row;\n", "        input [7:0] character;\n",
          "        input [3:0] row;\n", "        begin\n", "            song_glyph_row = 16'h0000;\n",
          "            case (character)\n"]
for char, code in codes.items():
    image = Image.new("L", (16, 16))
    bbox = font.getbbox(char)
    ImageDraw.Draw(image).text(((16 - (bbox[2] - bbox[0])) // 2 - bbox[0], -bbox[1]),
                               char, font=font, fill=255)
    lines.append(f"                8'h{code:02X}: case (row) // {char}\n")
    for y in range(16):
        bits = sum((1 << (15 - x)) for x in range(16) if image.getpixel((x, y)) >= 128)
        lines.append(f"                    4'd{y}: song_glyph_row=16'h{bits:04X};\n")
    lines.append("                    default: ;\n                endcase\n")
lines += ["                default: ;\n", "            endcase\n", "        end\n", "    endfunction\n", END]
source = VERILOG.read_text(encoding="utf-8")
if START in source:
    source = source[:source.index(START)] + source[source.index(END) + len(END):]
source = source.replace("endmodule\n", "".join(lines) + "endmodule\n", 1)
VERILOG.write_text(source, encoding="utf-8")
print(f"Generated {len(titles)} titles and {len(glyphs)} Chinese glyphs")
