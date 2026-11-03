# Player key control review

Historical three-item-menu record. The current four-item H1/H2/H3-size/H4-music
layout supersedes this key table; see `IMAGE_SIZE_H3_H4.md`.

## Behavior

| Context | KEY2 | KEY3 | KEY4 short | KEY4 long (2 s) |
|---|---|---|---|---|
| Home | Cycle C/F/S | Next background | Pause/resume | Open H1 menu |
| H1/H2/H3 selection | Cycle H1/H2/H3 | Increment selected brightness/contrast; H3 selection unchanged | Save and close H1/H2; enter H3 | Close menu |
| H3 music editor | Previous track | Next track | Pause/resume | Close H3 |

- Menu closes after 2 s without input; holding any debounced key stops the idle
  timer. H3 editor stays open until explicitly closed.
- KEY4 events have priority. While KEY4 is held, KEY2/KEY3 do not act.
- KEY2+KEY3 events/holds suppress the other key's action; no simultaneous
  previous/next track command is emitted.
- One event per stable press. Long hold does not auto-repeat; KEY4 long release
  never generates an additional short press.
- A valid UART setting overrides a simultaneous local change to the same
  setting, while unrelated menu/pause events still execute. Out-of-range remote
  brightness/contrast/effect values are ignored.

## Implementation

- `top_tf_hdmi_audio.v`: `player_key_control` is the sole owner of UI state,
  play/pause, brightness, contrast, effect and track toggles. State is one of
  HOME/MENU/MUSIC_EDIT; edit flags are derived, rather than independently set.
- `player_button_debounce` supplies reset-initialized, 20 ms filters for KEY2/3.
  KEY3 is debounced once and routed according to the UI state at the event.
- `sd_card_bmp` receives that background event in the same 50 MHz domain.
  Legacy raw-button input remains available with `USE_KEY_NEXT_EVENT=0`.
- Legacy debounce edge detection was corrected to emit on press rather than
  accidentally using the previous stable state at release.
- Manual background selection wins over an automatic tick on the same cycle.
- Filter/hold counters are sized to their configured limits; minimum count is
  one cycle, avoiding zero-width/zero-threshold parameter cases.
- Modules remain in existing project source files; no encrypted IP or pin and
  clock constraints were changed.

## Verification

- `tb_player_keys`: home/menu/H3 routing, simultaneous KEY2+KEY3, simultaneous
  UART and KEY4, no background event during editing, held-key timeout protection,
  H3 without idle timeout, save/exit, debounce and release rearming; PASS.
- `tb_key_short_long`: short/long split, bounce rejection, long hold one-shot and
  release without an extra short press; PASS.
- `tb_music_scheduler`: sparse track pairing, EOF FIFO drain and safe restart;
  PASS after the scheduler interface update.
- Top-level Icarus syntax check; PASS.

Build script: `src/td_project/build_music_keys.tcl` (seed 1).
Output: `src/td_project/full_build_music_keys.bit`.
TD build completed on 2026-10-17 at 22:52:47 with seed 1. SHA256:
`BECCA687F81C682F36BD461B06BFAAC06A3A72C05F300F280B5AD045F9F33609`.

LUT 17032/19600 (148 fewer than the previous optimized build), registers
8119/19600 (44 fewer), BRAM 55/64 and DSP 15/29. Existing SDRAM and cross-domain
timing violations remain: setup WNS -6.699 ns, hold WNS -1.540 ns. Full timing
closure is not claimed; local clock routing and SDRAM placement warnings remain.
Previous optimized firmware is retained for comparison. Hardware key testing
is still needed after downloading this build.
