"""Restore only the pre-menu player UI from the local video archive."""
from pathlib import Path

target = Path("lab_ex5_i2s-work/src/user_source/hdl_source/top_tf_hdmi_audio.v")
archive = Path("_archive/video_20261021/top_tf_hdmi_audio.v")
source = target.read_text(encoding="utf-8-sig")
original = archive.read_text(encoding="utf-8-sig")

for start, end in [
    ("wire        edit_active;", "wire [1:0]  current_image_aspect;"),
    ("reg  [4:0]  panel_track_v0", "reg  [1:0]  music_enable_audio;"),
]:
    first = source.index(start)
    last = source.index(end, first) + len(end)
    old_first = original.index(start)
    old_last = original.index(end, old_first) + len(end)
    source = source[:first] + original[old_first:old_last] + source[last:]

for marker in ("player_key_control u_player_keys(", "property_panel u_property_panel("):
    first = source.index(marker)
    last = source.index(");", first) + 2
    old_first = original.index(marker)
    old_last = original.index(");", old_first) + 2
    source = source[:first] + original[old_first:old_last] + source[last:]

target.write_text(source, encoding="utf-8")
print("Restored original menu declarations and instances")
