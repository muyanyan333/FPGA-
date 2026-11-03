#!/usr/bin/env python3
"""Build one numbered WAV/LYR2 pair from an MP4 and timed LRC."""

from __future__ import annotations

import argparse
import subprocess
import wave
from pathlib import Path

import imageio_ffmpeg

from prepare_card import DEFAULT_FONT, build_lyr2_from_lrc, wav_duration


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--lrc", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--track", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.track <= 16:
        parser.error("track must be 1..16")
    if not args.video.is_file() or not args.lrc.is_file():
        parser.error("video and LRC must exist")

    args.output.mkdir(parents=True, exist_ok=True)
    wav_path = args.output / f"{args.track:02d}.wav"
    lyr_path = args.output / f"{args.track:02d}.lyr"
    if wav_path.exists() or lyr_path.exists():
        parser.error("output already exists; choose a clean staging directory")

    command = [imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error",
               "-nostdin", "-i", str(args.video), "-vn", "-ac", "2", "-ar", "48000",
               "-acodec", "pcm_s16le", "-f", "s16le", "pipe:1"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        with wave.open(str(wav_path), "wb") as output:
            output.setnchannels(2)
            output.setsampwidth(2)
            output.setframerate(48000)
            while chunk := process.stdout.read(1024 * 1024):
                output.writeframesraw(chunk)
        error = process.stderr.read().decode("utf-8", errors="replace")
        if process.wait() != 0:
            raise RuntimeError(error or "ffmpeg conversion failed")
        seconds = wav_duration(wav_path)
        duration_ms = round(seconds * 1000)
        lyric, frames, lyric_ms = build_lyr2_from_lrc(
            args.lrc, args.title, duration_ms, DEFAULT_FONT, args.track)
        lyr_path.write_bytes(lyric)
        print(f"{wav_path.name}: {seconds:.3f}s, {wav_path.stat().st_size} bytes")
        print(f"{lyr_path.name}: {frames} frames, {lyric_ms}ms, {lyr_path.stat().st_size} bytes")
    except Exception:
        wav_path.unlink(missing_ok=True)
        lyr_path.unlink(missing_ok=True)
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
