# H4 equal-aspect viewport / H5 music editor

## Current menu

| Item | KEY3 action | KEY4 short |
|---|---|---|
| H1 | Brightness level | Keep changes, home |
| H2 | Contrast level | Keep changes, home |
| H3 | Size: 640x480 / 512x384 / 320x240 | Keep changes, home |
| H4 | Original / 4:3 / 16:9 / 1:1 viewport | Keep changes, home |
| H5 selection | No action | Enter music editor |
| H5 music editor | Next track; KEY2 = previous | Pause/resume |

Long KEY4 opens the menu from home and closes it while editing. KEY2 cycles all
five items. Menu timeout is 3 seconds, retaining changes; holding a key
prevents timeout. H5 music editor does not time out.

H3 size and H4 viewport are separate settings for each image (16 slots), kept
in registers until reset or card reinitialization. Music, lyrics, HDMI timing and
the full SDRAM 640x480 output frame remain unchanged.

## Equal-aspect behavior

Each picture is fit completely and centered inside a selected viewport, with
black padding outside the content. No stretching and no content crop is used
by H4. Original mode and 4:3 mode may look identical because the display canvas
and H3 base sizes are already 4:3.

| H3 size | Original / 4:3 viewport | 16:9 viewport | 1:1 viewport |
|---|---|---|---|
| 640x480 | 640x480 | 640x360 | 480x480 |
| 512x384 | 512x384 | 512x288 | 384x384 |
| 320x240 | 320x240 | 320x180 | 240x240 |

For example, a 4:3 photo inside a 16:9 640x360 viewport occupies 480x360; its
content remains 4:3. H4 changes the available display box, not the photo's
intrinsic aspect ratio. Different viewport choices can therefore produce the
same content size for some source aspect ratios.

H3/H4 freeze the slideshow. Both use complete-frame preview/reload, latch
geometry at frame start and bypass transitions during editing. Requests that
finish for another image cannot replace the image being edited.

## Background preparation

The previous 12 BMPs contained permanently baked black padding. Their original
binary files are backed up at `media/background_originals/bg_01.bmp` through
`bg_12.bmp`. `tools/prepare_aspect_backgrounds.py` removed only exterior entirely
black rows/columns, preserving every nonblack content pixel. Narrow source
content was proportionally resampled to meet the hardware minimum source size
320x240. Output remains 24-bit uncompressed, bottom-up BMP with row padding.

The prepared files were written to the same 12 paths in `E:/picture/`, then each
was SHA256-verified. No music/lyrics files were changed. Source images and output
hashes are recorded in `tools/_staging/aspect_backgrounds/manifest.json`; visual
before/after comparison is `tools/_staging/aspect_backgrounds/comparison.png`.

The script defaults to local preparation only; `--install` writes the card. It
refuses to overwrite a card image that no longer matches either its backed-up
original or the prepared output. Keep backups when changing/replacing media.
The old `prepare_card.py` background conversion adds a 640x480 padded canvas;
use `--skip-images` for lyric updates to preserve these native-content BMPs.

## Implementation and verification

- Menu index expanded from 2 to 3 bits with explicit wrap at H5.
- Per-image aspect table is separate from the size table. Latest geometry
  change coalesces a reload; in-flight frame metadata stays latched.
- Scaler compares source against the selected viewport's aspect, not a fixed
  4:3 ratio. All products are constant shift/add expressions, avoiding new DSPs.
- H4 panel displays the ratio; seven-segment display shows H4 and mode 1..4.
  H5 editor displays H5 and playback state.
- `tb_player_keys`: H3/H4 parameter actions, save/timeout, H5 confirmation,
  music actions, chord suppression, remote/local arbitration; passed.
- `tb_music_scheduler`: independent size/aspect tables, wrap, preview requests,
  edit freeze and old-frame completion protection; passed.
- `tb_image_size`: 12 complete, pixel-checked 640x480 output frames, including
  all aspect modes, multiple sizes, wide/portrait and odd source dimensions;
  each frame's size/aspect inputs changed mid-load to verify latching; passed.
- `tb_bmp_row_padding`: BMP pixels and row padding; passed.
- Top syntax, media script syntax and H4 panel rendering/visual review passed.

Build: `src/td_project/build_image_aspect.tcl`, seed 1.
Output: `src/td_project/full_build_h4_aspect_h5_music.bit`.
TD full build completed on 2026-10-17 at 23:26:55 (seed 1). SHA256:
`4945BC213D2F5DD20C0BA5B46483A402DD4D1243DB40FED3C393FEAC4DB0458C`.
LUT 17566/19600 (89.62%), registers 8189, BRAM 55/64, DSP 15/29.
Setup WNS -6.699 ns and hold WNS -1.540 ns: existing SDRAM/cross-domain timing
limitations remain. Bit generation does not establish full timing closure;
continuous playback, resizing and H5 controls require board verification.
