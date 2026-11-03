#!/usr/bin/env python3
"""Convert lyric-video frames into an FPGA-friendly timed bitmap stream.

The source video is sampled every 500 ms.  The strongest lyric-like text row in
the lower panel is isolated and stored as a 512x16 one-bit bitmap.  No Chinese
font ROM or run-time text decoder is required in the FPGA.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

import cv2
import numpy as np


WIDTH = 512
HEIGHT = 16
INTERVAL_MS = 500
HEADER_SIZE = 32


def text_bitmap(frame: np.ndarray) -> np.ndarray:
    h, w = frame.shape[:2]
    # Portrait lyric videos use a lower scrolling panel.  The one landscape
    # source uses ordinary subtitles in the lower half.
    y0 = int(h * (0.60 if w >= h else 0.64))
    roi = frame[y0:h, :]
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)

    # A morphological top-hat rejects the slowly varying sunset/gradient
    # background while retaining bright lyric strokes.
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (19, 19))
    bright = cv2.morphologyEx(gray, cv2.MORPH_TOPHAT, kernel)
    otsu_level, mask = cv2.threshold(
        bright, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
    )
    if otsu_level < 18:
        _, mask = cv2.threshold(bright, 18, 255, cv2.THRESH_BINARY)

    # Reject isolated landscape/video texture.  Lyric glyph components are
    # compact, while horizons, clouds and waveform traces are usually very
    # wide or only one pixel tall.
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    clean = np.zeros_like(mask)
    for component in range(1, count):
        x, y, cw, ch, area = stats[component]
        if 14 <= area <= 1200 and 3 <= cw <= max(180, w // 3) and 7 <= ch <= 52:
            clean[labels == component] = 255
    mask = clean

    # Score a 36-pixel-high moving band.  Suppress the extreme edges where
    # watermarks are normally placed.
    margin = max(8, w // 20)
    mask[:, :margin] = 0
    mask[:, w - margin :] = 0
    row_energy = (mask > 0).sum(axis=1).astype(np.float32)
    band_h = max(24, int(h * 0.032))
    score = np.convolve(row_energy, np.ones(band_h, np.float32), mode="same")
    if score.size == 0 or float(score.max()) < 20.0:
        return np.zeros((HEIGHT, WIDTH), np.uint8)
    center = int(score.argmax())
    top = max(0, center - band_h // 2)
    bottom = min(mask.shape[0], top + band_h)
    line = mask[top:bottom, :]

    # Remove isolated video texture and normalize into the HDMI lyric strip.
    line = cv2.morphologyEx(line, cv2.MORPH_CLOSE, np.ones((2, 2), np.uint8))
    scale = min(WIDTH / w, HEIGHT / max(1, line.shape[0]))
    out_w = max(1, min(WIDTH, int(round(w * scale))))
    out_h = max(1, min(HEIGHT, int(round(line.shape[0] * scale))))
    line = cv2.resize(line, (out_w, out_h), interpolation=cv2.INTER_AREA)
    line = (line >= 96).astype(np.uint8)
    canvas = np.zeros((HEIGHT, WIDTH), np.uint8)
    x = (WIDTH - out_w) // 2
    y = (HEIGHT - out_h) // 2
    canvas[y : y + out_h, x : x + out_w] = line
    return canvas


def pack_bitmap(bitmap: np.ndarray) -> bytes:
    return np.packbits(bitmap, axis=1, bitorder="big").tobytes()


def convert(source: Path, output: Path) -> tuple[int, int]:
    cap = cv2.VideoCapture(str(source))
    if not cap.isOpened():
        raise RuntimeError(f"cannot open {source}")
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    duration_ms = int(round(frame_count * 1000.0 / fps))
    lyric_frames = (duration_ms + INTERVAL_MS - 1) // INTERVAL_MS

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as stream:
        header = struct.pack(
            "<4sBBHHHIII8x",
            b"LYR1",
            1,
            0,
            WIDTH,
            HEIGHT,
            INTERVAL_MS,
            lyric_frames,
            duration_ms,
            HEADER_SIZE,
        )
        assert len(header) == HEADER_SIZE
        stream.write(header)
        for index in range(lyric_frames):
            cap.set(cv2.CAP_PROP_POS_MSEC, index * INTERVAL_MS)
            ok, frame = cap.read()
            bitmap = text_bitmap(frame) if ok else np.zeros((HEIGHT, WIDTH), np.uint8)
            stream.write(pack_bitmap(bitmap))
    cap.release()
    return lyric_frames, duration_ms


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    count, duration = convert(args.source, args.output)
    print(f"{args.output.name}: {count} frames, {duration / 1000:.2f}s")


if __name__ == "__main__":
    main()
