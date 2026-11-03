# Music player logic review — 2026-10-17

## Delivered build

- Script: `src/td_project/build_music_lyrics_optimized.tcl`, top `top`, seed 1.
- Bit: `src/td_project/full_build_music_lyrics_optimized.bit`.
- SHA256: `75A880C7B84D2865821864EAF787CD3421BBE3516AD51F50DCBB7D38D0AEB75D`.
- Original `full_build_music_lyrics.bit` preserved for comparison.

## Corrected behavior

1. Lyric valid/title valid/display bank synchronizers now run in `video_clk`,
   the domain consuming the bitmaps. Previously they ran in the SD domain.
2. Lyric header checks cover version 2, 512x16 geometry, 500 ms interval,
   nonzero frame count, offset and file bounds. Frame bound checking uses
   subtraction/division rather than an overflow-prone left shift.
3. Each WAV independently enables its matching numbered lyric. A missing lyric
   for another track no longer disables all lyrics. Full 8-bit lyric IDs are
   range checked before indexing the 16-slot table.
4. Automatic next-track waits for the PCM FIFO to drain, plus four sample times
   for I2S prefetch. EOF from the SD reader alone no longer discards the tail.
5. Manual next/previous stops new WAV data-sector requests and waits for the
   current SD transaction to end. FIFO reset is issued at the actual stream
   restart boundary, preventing late old-track writes after an early reset.
6. Lyric file LBA and WAV contiguous-file flag are captured at start, so changing
   the selected track cannot redirect an unfinished old stream.
7. The lyric timer no longer resets after title loading; PCM ticks counted while
   the title is loading remain part of the song timeline.
8. LRC offset is global, even when placed at the end of the file. Negative offset
   delays lyrics. Track 02 uses -1500 ms; its first event is now 2670 ms.
9. Card preparation validates actual canonical 44-byte PCM WAV headers, sample
   format, alignment and numeric filename pairing. Discovery order is irrelevant.

## Verification

Passed with Icarus Verilog:

- `tb_lyric_title`: independent 100 MHz/38.46 MHz clocks, frame switching,
  restart, incompatible version and overflow-sized frame-count rejection.
- `tb_music_scheduler`: sparse track IDs, a missing lyric on another track,
  FIFO tail drain and manual restart at a clean SD ownership boundary.
  Peripheral status is isolated; this is not a physical SPI end-to-end test.
- `tb_exfat_pcm_wav_reader`: 128 stereo frames.
- `tb_pcm_i2s_path`: FIFO through I2S receiver.
- `tb_exfat_audio_discovery`: four BMPs plus WAV and BMP candidate lookup.
  The old test SD model was fixed to latch each request address and allow a
  completion cycle before accepting the next request; failures now use fatal.
- `tb_bmp_fit_scaler`: 320x240 and 1280x720 to 640x480.
- Top-level syntax check.

`python sim/test_lrc_offset.py`: 3 tests passed (offset placement, numeric track
pairing and actual hardware WAV format). Six-track card preparation dry run
passed; it made no further card changes.

TD completed synthesis, placement, routing and bit generation:

- LUT 17180/19600 (87.65%), registers 8163/19600.
- BRAM 55/64, DSP 15/29.
- Setup WNS -6.699 ns; hold WNS -1.540 ns. Timing is **not closed**.
- Local clock routing and SDRAM placement warnings remain in the build log.
- No encrypted HDL, pins or timing exceptions were changed to hide violations.
- Hardware validation of this new bit is still required.

## Card updates

- `E:/MUSIC/02.lyr`: regenerated with the now-effective 1500 ms delay.
- `E:/MUSIC/12.wav`: normalized to a 44-byte header (previous ffmpeg output
  contained a LIST chunk); PCM rate/duration preserved.
- Both copies were hash checked. Sources/backups and other tracks retained.

Lyric display granularity remains 500 ms. A whole-song offset cannot correct
individual timestamps or a different recording version; track 02's new delay
still requires listening confirmation.
