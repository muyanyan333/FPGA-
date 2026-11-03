#!/usr/bin/env python3
"""Regenerate LYR1 lyric strips from the user's own MP4s (v2 extraction).

Portrait lyric videos show a scrolling list of lines.  The line being sung is
kept near 73% of the frame height by the video template, so this version picks
the text line closest to that position and renders only that single line.
Landscape videos use the old extraction result unchanged (they are subtitle
style and were not the source of the ghosting).

Output: lyric_build_v2/01..12.lyr, same frame count/duration as the source
LYR1 files in ../lyric_build, so prepare_card.py can pair and verify them.
"""
from __future__ import annotations

import csv
import shutil
import struct
from pathlib import Path

import cv2
import numpy as np

WORK = Path(__file__).resolve().parents[1]
SRC_LYR = WORK.parent / "lyric_build"
OUT_DIR = WORK / "lyric_build_v2"
PLAYLIST = WORK / "media" / "playlist.csv"
VIDEO_DIR = Path("E:/MUSIC/source_mp4")
TARGET_FRAC = 0.73


def row_bands(gray, roi0, min_h=12, max_h=70, thresh=20):
    roi = gray[roi0:, :]
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (19, 19))
    res = cv2.morphologyEx(roi, cv2.MORPH_TOPHAT, kernel)
    mask = (res > thresh).astype(np.uint8)
    row = mask.sum(axis=1)
    bands = []
    in_band = False
    start = 0
    for index, value in enumerate(row):
        if value > 4 and not in_band:
            in_band = True
            start = index
        elif value <= 4 and in_band:
            in_band = False
            if min_h <= index - start <= max_h:
                bands.append((roi0 + start, roi0 + index))
    if in_band and min_h <= len(row) - start <= max_h:
        bands.append((roi0 + start, roi0 + len(row)))
    return bands


def render_line(frame, band):
    a, b = band
    pad = 6
    a = max(0, a - pad)
    b = min(frame.shape[0], b + pad)
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 15))
    res = cv2.morphologyEx(gray[a:b, :], cv2.MORPH_TOPHAT, kernel)
    mask = (res > 18).astype(np.uint8) * 255
    cols = np.where(mask.sum(axis=0) > 0)[0]
    if len(cols) == 0:
        return np.zeros((16, 512), np.uint8)
    x0 = max(0, cols.min() - 4)
    x1 = min(mask.shape[1], cols.max() + 5)
    line = mask[:, x0:x1]
    h, w = line.shape
    scale = min(512 / w, 16 / h)
    nw = max(1, int(w * scale))
    nh = max(1, int(h * scale))
    line = cv2.resize(line, (nw, nh), interpolation=cv2.INTER_AREA)
    out = np.zeros((16, 512), np.uint8)
    y = (16 - nh) // 2
    x = (512 - nw) // 2
    out[y:y + nh, x:x + nw] = line
    return (out >= 96).astype(np.uint8) * 255


def pick_band(frame, target_frac=TARGET_FRAC):
    h, w = frame.shape[:2]
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    if w >= h:
        return None
    bands = row_bands(gray, int(h * 0.55))
    bands = [band for band in bands if (band[1] - band[0]) < 80]
    if not bands:
        return None
    target = h * target_frac
    return min(bands, key=lambda band: abs((band[0] + band[1]) / 2 - target))


def pack_frame(image):
    # image is 16x512 with 0/255; packbits gives 16 rows x 64 bytes.
    bits = (image >= 128).astype(np.uint8)
    return np.packbits(bits, axis=1, bitorder="big").tobytes()


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rows = list(csv.DictReader(PLAYLIST.open(encoding="utf-8-sig", newline="")))
    for row in rows:
        stem = Path(row["lyric"]).stem
        source = SRC_LYR / f"{stem}.lyr"
        raw = source.read_bytes()
        magic, version, flags, width, height, interval, frames, duration, offset = \
            struct.unpack_from("<4sBBHHHIII", raw, 0)
        if magic != b"LYR1" or offset != 32:
            raise RuntimeError(f"bad source {source}")
        # playlist.csv has the mp4 name in the source column
        candidates = list(VIDEO_DIR.glob(f"{stem}_*.mp4"))
        if not candidates:
            raise RuntimeError(f"missing video for track {stem}")
        video = candidates[0]
        cap = cv2.VideoCapture(str(video))
        if not cap.isOpened():
            raise RuntimeError(f"cannot open {video}")
        w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
        h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
        portrait = h >= w
        data = bytearray()
        if not portrait:
            # Keep the landscape extraction (03) from the original LYR1.
            data += raw[32:32 + frames * 1024]
            print(f"{stem}: landscape, keep original ({video.name})")
        else:
            for n in range(frames):
                cap.set(cv2.CAP_PROP_POS_MSEC, n * 500)
                ok, frame = cap.read()
                band = pick_band(frame) if ok else None
                image = render_line(frame, band) if band else np.zeros((16, 512), np.uint8)
                data += pack_frame(image)
            print(f"{stem}: portrait, new extraction ({video.name})")
        cap.release()
        header = struct.pack("<4sBBHHHIII8x", b"LYR1", 1, 0,
                             width, height, interval, frames, duration, offset)
        out = OUT_DIR / f"{stem}.lyr"
        out.write_bytes(header + bytes(data))
        print(f"  -> {out} ({out.stat().st_size} bytes, {frames} frames)")


if __name__ == "__main__":
    main()
