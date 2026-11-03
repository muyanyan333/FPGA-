# H3 per-image display size / H4 music editor

## Controls

Long-press KEY4 for 2 seconds to open the property menu. KEY2 cycles H1 → H2 →
H3 → H4 → H1. The main-screen KEY2/KEY3 actions remain effect/background.

| Item | KEY3 | KEY4 short | KEY4 long |
|---|---|---|---|
| H1 brightness | Next brightness level | Keep changes and return home | Return home |
| H2 contrast | Next contrast level | Keep changes and return home | Return home |
| H3 image size | Next size for the displayed image | Keep changes and return home | Return home |
| H4 selection | No action | Enter music editor | Return home |
| H4 music editor | Next track (KEY2 = previous) | Pause/resume | Return home |

H1/H2/H3/H4 selection times out after 2 seconds of inactivity, retaining changes.
Held debounced buttons stop the timeout. H4 music editor does not time out.
KEY4 has priority; KEY2+KEY3 chords do not issue both actions.

## H3 display sizes

- Level 1: fit inside 640×480.
- Level 2: fit inside 512×384.
- Level 3: fit inside 320×240.

The image retains its aspect ratio and is centered on a 640×480 black canvas.
For example, 16:9 content at level 2 occupies 512×288; portrait 2:3 content at
level 3 occupies 160×240. HDMI timing and SDRAM frame length remain 640×480.
The input BMP file and source resolution do not change; no card conversion is
required.

Each discovered image slot has its own 2-bit setting (up to 16 images), retained
until reset/card reinitialization. There is no new SD write path or power-off
persistence. Brightness and contrast keep their existing global behavior.

H3 freezes the displayed image while editing. A different automatic background
already loading when H3 opens is allowed to finish writing, but is not committed
over the displayed image. KEY3 schedules a reload of the same image. Rapid size
changes coalesce into the latest requested setting; the scaler latches its size
at frame start. Completed previews swap via the existing SDRAM buffer commit.
During H3, transition effects are bypassed so a subsequent preview does not
overwrite an old buffer still held by a fade or slide.

The right-side H3 panel displays image number, selected viewport and controls.
The 7-segment display shows current image number, size level (1/2/3), and H3.
H4 music editor shows H4, track number and playback status. The home display now
also distinguishes playing P from paused S.

## Implementation and tests

- `top_tf_hdmi_audio.v`: four-item menu, H3 event routing, H4 editor, panel/7-seg
  updates and direct frame selection for size preview.
- `SD/sd_card_bmp.v`: per-image table, preview scheduling, slideshow freeze and
  rejection of a different image completing underneath the H3 editor.
- `SD/bmp_fit_scaler.v`: optional viewport selection, constant shift/add scaling
  factors, latched viewport, full-size black-border output.
- `property_panel.v`: H3 image-size panel; existing music panel used for H4.

Icarus verification passed:

- `tb_player_keys`: H3 edits size and saves home; H4 requires confirmation,
  routes previous/next/pause correctly; key isolation, timeout and debounce.
- `tb_music_scheduler`: prior audio regression plus independent settings on
  two image slots, wraparound, pending previews, slideshow freeze and an old
  background completion not replacing the edited image.
- `tb_image_size`: every output pixel checked for full 640×480 frame count,
  centered borders and constant image color, for all three sizes, portrait and
  wide images. Changing the input size mid-frame does not affect its geometry.
- Top-level syntax and both property-panel preview renders passed. H3 preview:
  `sim/image_size_panel_preview.png`.

Build entry: `src/td_project/build_image_size.tcl`, seed 1.
Output: `src/td_project/full_build_h3_size_h4_music.bit`.
TD full build completed 2026-10-17 23:06:27. SHA256:
`2A8FA881ED6907274842645697CCFBFE1127AB1DA7894FD5AC85A2736C8D173A`.
Resources: LUT 17254/19600 (88.03%), registers 8170, BRAM 55/64, DSP 15/29.
Existing SDRAM/cross-domain timing violations remain: setup WNS -6.699 ns,
hold WNS -1.530 ns. Successful bit generation does not establish full timing
closure or replace board testing.
Earlier firmware remains available. Hardware verification is required after
downloading, particularly repeated resizing while playing audio.
