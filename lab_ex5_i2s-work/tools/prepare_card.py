#!/usr/bin/env python3
"""Prepare the exFAT TF card for the HX4S20 audio + lyric player.

What it does:
  1. Converts the 12 background JPGs to 640x480 24-bit uncompressed BMP.
  2. Regenerates each lyric file as LYR2:
         32-byte header | zero padding to 512 | 512-byte title block
         | N * 1024-byte lyric frames (frames start at offset 1024)
     The title block is a 16px-wide x 256px-tall vertical column of 16x16
     glyphs rendered from playlist.csv with a Windows CJK font.
  3. Copies the generated files to E:\\MUSIC and E:\\picture.
  4. Moves non-played sources into second-level folders (never deletes them):
       E:\\Checkmate_48k16_PCM.wav -> E:\\MUSIC\\source_mp4\\
       E:\\MUSIC\\*.mvi             -> E:\\MUSIC\\source_mp4\\mvi\\
       E:\\picture\\*.jpg           -> E:\\picture\\src\\
  5. Verifies WAV format, duration and numeric WAV/LYR track pairing.

Run with --dry-run first to see the plan without touching the card.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import shutil
import struct
import sys
import wave
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

CELL = 16
TITLE_COLUMN_PX = 256           # 16 glyphs of 16 px, vertically centred
TITLE_BYTES = 512               # 16 px * 256 rows / 8
LYRIC_W, LYRIC_H, LYRIC_INTERVAL = 512, 16, 500
LYRIC_DATA_OFFSET = 1024
BMP_W, BMP_H = 640, 480

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LYRICS = PROJECT_ROOT.parent / "lyric_build"
DEFAULT_PLAYLIST = PROJECT_ROOT / "media" / "playlist.csv"
DEFAULT_LRC_DIR = PROJECT_ROOT / "lyrics_lrc"
DEFAULT_FONT = Path("C:/Windows/Fonts/msyh.ttc")
STAGING = PROJECT_ROOT / "tools" / "_staging"


def natural_key(path: Path):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", path.name)]


def exfat_name_hash(name: str) -> int:
    """exFAT up-case-table hash for ASCII names (digits/letters unchanged)."""
    h = 0
    for ch in name:
        c = ord(ch)
        if "a" <= ch <= "z":
            c = ord(ch.upper())
        h = ((h << 15) | (h >> 1)) & 0xFFFF
        h = (h + (c & 0xFF)) & 0xFFFF
        h = ((h << 15) | (h >> 1)) & 0xFFFF
        h = (h + (c >> 8)) & 0xFFFF
    return h


def render_title_block(text: str, font_path: Path, font_size: int = 16,
                       threshold: int = 96) -> bytes:
    """Render text into a 16x256 mono bitmap, top-to-bottom, MSB first."""
    chars = [ch for ch in text]
    if len(chars) > TITLE_COLUMN_PX // CELL:
        raise ValueError(f"title has {len(chars)} characters; max is "
                         f"{TITLE_COLUMN_PX // CELL}: {text!r}")
    font = ImageFont.truetype(str(font_path), font_size)
    rows = [[0] * CELL for _ in range(TITLE_COLUMN_PX)]
    top = (TITLE_COLUMN_PX - len(chars) * CELL) // 2
    for index, ch in enumerate(chars):
        if ch == " ":
            continue
        glyph = Image.new("L", (CELL, CELL), 0)
        ImageDraw.Draw(glyph).text((CELL / 2, CELL / 2), ch, fill=255,
                                   font=font, anchor="mm")
        for y in range(CELL):
            for x in range(CELL):
                if glyph.getpixel((x, y)) >= threshold:
                    rows[top + index * CELL + y][x] = 1
    out = bytearray()
    for row in rows:
        value = 0
        for bit in row:
            value = (value << 1) | bit
        out += struct.pack(">H", value)
    assert len(out) == TITLE_BYTES
    return bytes(out)


def parse_lyr_header(raw: bytes):
    magic, version, flags, width, height, interval, frames, duration, data_off = \
        struct.unpack_from("<4sBBHHHIII", raw, 0)
    if magic != b"LYR1":
        raise ValueError("not a LYR1 file")
    if (width, height, interval) != (LYRIC_W, LYRIC_H, LYRIC_INTERVAL):
        raise ValueError(f"unexpected lyric geometry {width}x{height} {interval}ms")
    return version, frames, duration, data_off


def build_lyr2(source: Path, title: str, font_path: Path,
               track_no: int) -> tuple[bytes, int, int]:
    raw = source.read_bytes()
    version, frames, duration, data_off = parse_lyr_header(raw)
    if data_off != 32:
        raise ValueError(f"{source.name}: source data_offset {data_off}, expected 32")
    lyric = raw[32:32 + frames * 1024]
    if len(lyric) != frames * 1024:
        raise ValueError(f"{source.name}: truncated lyric frames")
    header = struct.pack("<4sBBHHHIIIB7x", b"LYR1", 2, 0,
                         LYRIC_W, LYRIC_H, LYRIC_INTERVAL,
                         frames, duration, LYRIC_DATA_OFFSET,
                         track_no & 0xFF)
    assert len(header) == 32
    preamble = header + b"\x00" * (512 - len(header))
    title_block = render_title_block(title, font_path)
    blob = preamble + title_block + lyric
    assert len(blob) == LYRIC_DATA_OFFSET + frames * 1024
    assert len(blob) % 512 == 0
    return blob, frames, duration


_LRC_TIME = re.compile(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")
_LRC_OFFSET = re.compile(r"\[offset:([+-]?\d+)\]", re.IGNORECASE)


def parse_lrc(path: Path) -> list[tuple[int, str]]:
    """Return sorted (time_ms, text) events. Empty text clears the strip."""
    offset_ms = 0
    events: list[tuple[int, str]] = []
    lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    # LRC metadata is global even when an editor appends it after the lyrics.
    for raw_line in lines:
        match = _LRC_OFFSET.search(raw_line)
        if match:
            offset_ms = int(match.group(1))
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        match = _LRC_OFFSET.search(line)
        if match:
            continue
        stamps = list(_LRC_TIME.finditer(line))
        if not stamps:
            continue
        text = line[stamps[-1].end():].strip()
        for stamp in stamps:
            minutes = int(stamp.group(1))
            seconds = int(stamp.group(2))
            fraction = stamp.group(3) or ""
            if len(fraction) == 0:
                millis = 0
            elif len(fraction) == 1:
                millis = int(fraction) * 100
            elif len(fraction) == 2:
                millis = int(fraction) * 10
            else:
                millis = int(fraction)
            time_ms = max(0, minutes * 60000 + seconds * 1000 + millis -
                          offset_ms)
            events.append((time_ms, text))
    events.sort(key=lambda item: item[0])
    return events


def render_lyric_line(text: str, font_path: Path) -> bytes:
    """Render one line into the 512x16 mono strip with a fixed font size."""
    if not text:
        return bytes(LYRIC_W * LYRIC_H // 8)
    scale = 2
    width, height = LYRIC_W * scale, LYRIC_H * scale
    size = LYRIC_H * scale
    image = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(font_path), size)
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = max(1, bbox[2] - bbox[0])
    # Most lyric lines fit at the nominal size. A long line shrinks slightly
    # instead of being clipped; every other line keeps the same font size.
    if text_width > width - 8:
        size = max(8 * scale, int(size * (width - 8) / text_width))
        font = ImageFont.truetype(str(font_path), size)
    draw.text((width / 2, height / 2), text, fill=255, font=font, anchor="mm")
    image = image.resize((LYRIC_W, LYRIC_H), Image.Resampling.LANCZOS)
    pixels = list(image.getdata())
    out = bytearray()
    for row in range(LYRIC_H):
        for col in range(0, LYRIC_W, 8):
            value = 0
            for bit in range(8):
                if pixels[row * LYRIC_W + col + bit] >= 80:
                    value |= 1 << (7 - bit)
            out.append(value)
    assert len(out) == LYRIC_W * LYRIC_H // 8
    return bytes(out)


def build_lyr2_from_lrc(lrc_path: Path, title: str, duration_ms: int,
                        font_path: Path,
                        track_no: int) -> tuple[bytes, int, int]:
    events = parse_lrc(lrc_path)
    if not events:
        raise ValueError(f"{lrc_path.name}: no timed lyric lines")
    # Keep the audio/video duration as the authority.  An LRC from a slightly
    # longer release may have a few trailing timestamps; those lines cannot be
    # heard in this WAV, so they are simply not displayed.
    frames = max(1, math.ceil(duration_ms / LYRIC_INTERVAL))
    frame_data = bytearray()
    event_index = 0
    current = ""
    for frame in range(frames):
        frame_time = frame * LYRIC_INTERVAL
        while event_index < len(events) and events[event_index][0] <= frame_time:
            current = events[event_index][1]
            event_index += 1
        frame_data += render_lyric_line(current, font_path)
    header = struct.pack("<4sBBHHHIIIB7x", b"LYR1", 2, 0,
                         LYRIC_W, LYRIC_H, LYRIC_INTERVAL,
                         frames, duration_ms, LYRIC_DATA_OFFSET,
                         track_no & 0xFF)
    assert len(header) == 32
    preamble = header + b"\x00" * (512 - len(header))
    title_block = render_title_block(title, font_path)
    blob = preamble + title_block + bytes(frame_data)
    assert len(blob) == LYRIC_DATA_OFFSET + frames * 1024
    assert len(blob) % 512 == 0
    return blob, frames, duration_ms


def convert_background(source: Path, output: Path) -> None:
    with Image.open(source) as image:
        rgb = image.convert("RGB")
        fitted = ImageOps.contain(rgb, (BMP_W, BMP_H), Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", (BMP_W, BMP_H), (0, 0, 0))
        canvas.paste(fitted, ((BMP_W - fitted.width) // 2,
                              (BMP_H - fitted.height) // 2))
        canvas.save(output, "BMP")


def verify_bmp(path: Path) -> None:
    data = path.read_bytes()[:54]
    if data[:2] != b"BM":
        raise ValueError(f"{path.name}: missing BM signature")
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bit_count = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if (width, abs(height), bit_count, compression, offset) != (BMP_W, BMP_H, 24, 0, 54):
        raise ValueError(f"{path.name}: bad BMP header "
                         f"{width}x{height} {bit_count}bpp comp={compression} off={offset}")


def wav_duration(path: Path) -> float:
    # The FPGA accepts the canonical 44-byte PCM header, not arbitrary RIFF
    # chunks. A desktop decoder can accept LIST/JUNK while hardware cannot.
    with path.open("rb") as handle:
        header = handle.read(44)
    if (len(header) != 44 or header[:4] != b"RIFF" or
            header[8:16] != b"WAVEfmt " or header[36:40] != b"data" or
            struct.unpack_from("<I", header, 16)[0] != 16):
        raise ValueError(f"{path.name}: requires canonical 44-byte PCM WAV header")
    fmt, channels, rate, byte_rate, align, bits = struct.unpack_from("<HHIIHH", header, 20)
    data_bytes = struct.unpack_from("<I", header, 40)[0]
    if (fmt != 1 or channels not in (1, 2) or rate != 48000 or bits != 16 or
            align != channels * 2 or byte_rate != rate * align or
            data_bytes == 0 or data_bytes % align or data_bytes > path.stat().st_size - 44):
        raise ValueError(f"{path.name}: requires nonempty, aligned 48 kHz/16-bit PCM")
    with wave.open(str(path), "rb") as handle:
        return handle.getnframes() / handle.getframerate()


def validate_playlist(rows: list[dict]) -> None:
    """Match the FPGA's numeric track slots; directory order is irrelevant."""
    if not 1 <= len(rows) <= 16:
        raise ValueError("playlist must contain 1..16 tracks")
    seen = set()
    for row in rows:
        track = int(row["track"])
        if not 1 <= track <= 16 or track in seen:
            raise ValueError(f"invalid or duplicate track number: {track}")
        seen.add(track)
        for field, extension in (("wav", ".wav"), ("lyric", ".lyr")):
            if row[field] != f"{track:02d}{extension}":
                raise ValueError(f"track {track:02d}: {field} must be {track:02d}{extension}")


def copy_fresh(source: Path, destination: Path) -> None:
    """Copy a generated file; remove the old generated copy first."""
    if destination.exists():
        destination.unlink()
    shutil.copyfile(source, destination)


def move_if_present(source: Path, destination_dir: Path) -> str | None:
    if not source.exists():
        return None
    destination_dir.mkdir(parents=True, exist_ok=True)
    target = destination_dir / source.name
    if target.exists():
        return f"skip (already present): {target}"
    shutil.move(str(source), str(target))
    return f"moved {source} -> {target}"


def make_preview(background: Path, lyric_blob: bytes, title_text: str,
                 font_path: Path, output: Path) -> None:
    with Image.open(background) as image:
        scene = image.convert("RGB")
    title_block = render_title_block(title_text, font_path)
    pixels = scene.load()
    for y in range(20):
        for x in range(BMP_W):
            r, g, b = pixels[x, y]
            pixels[x, y] = (r // 4, g // 4, b // 4)
    for y in range(112, 368):
        for x in range(608, 640):
            r, g, b = pixels[x, y]
            pixels[x, y] = (r // 4, g // 4, b // 4)

    frames = (len(lyric_blob) - LYRIC_DATA_OFFSET) // 1024
    frame_index = min(frames - 1, 60)  # 30 s into the track
    frame = lyric_blob[LYRIC_DATA_OFFSET + frame_index * 1024:
                       LYRIC_DATA_OFFSET + (frame_index + 1) * 1024]
    for y in range(LYRIC_H):
        for x in range(LYRIC_W):
            if frame[y * 64 + (x >> 3)] & (0x80 >> (x & 7)):
                pixels[64 + x, 2 + y] = (255, 255, 255)

    for y in range(TITLE_COLUMN_PX):
        word = (title_block[y * 2] << 8) | title_block[y * 2 + 1]
        for x in range(CELL):
            if word & (0x8000 >> x):
                pixels[616 + x, 112 + y] = (255, 224, 128)

    scene.save(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--card", default="E:/", help="card root (default E:/)")
    parser.add_argument("--lyrics", default=str(DEFAULT_LYRICS),
                        help="folder with source 01..12.lyr")
    parser.add_argument("--playlist", default=str(DEFAULT_PLAYLIST))
    parser.add_argument("--lrc-dir", default=str(DEFAULT_LRC_DIR),
                        help="optional folder with 01.lrc..12.lrc; when a "
                             "matching file exists it is rendered with a "
                             "uniform font instead of the video-extracted strip")
    parser.add_argument("--font", default=str(DEFAULT_FONT))
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan without writing or moving files")
    parser.add_argument("--skip-images", action="store_true",
                        help="do not convert or install background BMPs")
    parser.add_argument("--skip-housekeeping", action="store_true",
                        help="do not move source media into second-level folders")
    args = parser.parse_args()

    card = Path(args.card)
    music_dir = card / "MUSIC"
    picture_dir = card / "picture"
    lyrics_dir = Path(args.lyrics)
    lrc_dir = Path(args.lrc_dir)
    font_path = Path(args.font)
    playlist_path = Path(args.playlist)

    if not music_dir.is_dir():
        print(f"error: {music_dir} not found", file=sys.stderr)
        return 2
    if not lyrics_dir.is_dir():
        print(f"error: {lyrics_dir} not found", file=sys.stderr)
        return 2
    if not font_path.is_file():
        print(f"error: font {font_path} not found", file=sys.stderr)
        return 2

    with playlist_path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    try:
        validate_playlist(rows)
    except (ValueError, KeyError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    rows.sort(key=lambda row: int(row["track"]))
    print("WAV/LYR numeric track pairing: OK")

    STAGING.mkdir(parents=True, exist_ok=True)
    staging_lyrics = STAGING / "lyrics"
    staging_bmps = STAGING / "bmp"
    staging_lyrics.mkdir(exist_ok=True)
    staging_bmps.mkdir(exist_ok=True)

    plan: list[str] = []
    built: list[tuple[Path, bytes, int, int, str]] = []
    for row in rows:
        wav_path = music_dir / row["wav"]
        lyr_path = lyrics_dir / row["lyric"]
        lrc_path = lrc_dir / (Path(row["lyric"]).stem + ".lrc")
        if not wav_path.is_file():
            print(f"error: missing WAV {wav_path}", file=sys.stderr)
            return 2
        if not lyr_path.is_file() and not lrc_path.is_file():
            print(f"error: missing LYR/LRC for {row['wav']}", file=sys.stderr)
            return 2
        track_no = int(row["track"])
        wav_seconds = wav_duration(wav_path)
        if lrc_path.is_file():
            # An LRC belongs to the current WAV.  A stale LYR1 with the same
            # numeric stem may be left from an older playlist entry, so never
            # use that file's duration for an LRC-backed track.
            source_duration = int(round(wav_seconds * 1000))
            blob, frames, lyr_ms = build_lyr2_from_lrc(
                lrc_path, row["title"], source_duration, font_path, track_no)
            lyric_source = f"LRC {lrc_path.name}"
        else:
            source_duration = parse_lyr_header(lyr_path.read_bytes())[2]
            blob, frames, lyr_ms = build_lyr2(lyr_path, row["title"], font_path,
                                              track_no)
            lyric_source = f"LYR1 {lyr_path.name}"
        delta = lyr_ms / 1000.0 - wav_seconds
        status = "OK" if abs(delta) < 0.15 else "MISMATCH"
        print(f"{row['track']} {row['title']}: [{lyric_source}] "
              f"lyric {lyr_ms/1000:.2f}s / wav {wav_seconds:.2f}s "
              f"(delta {delta:+.2f}s) {status}")
        if status != "OK":
            print(f"error: {row['wav']} and {row['lyric']} are not aligned",
                  file=sys.stderr)
            return 3
        target = staging_lyrics / row["lyric"]
        target.write_bytes(blob)
        built.append((target, blob, frames, lyr_ms, row["title"]))
        plan.append(f"install {target.name} -> {music_dir / row['lyric']} "
                    f"({len(blob)} bytes, {frames} frames)")

    image_pairs: list[tuple[Path, Path]] = []
    if not args.skip_images:
        sources = sorted(picture_dir.glob("*.jpg"), key=natural_key)
        if len(sources) != 12:
            print(f"warning: found {len(sources)} JPG files in {picture_dir}, "
                  f"expected 12", file=sys.stderr)
        for index, source in enumerate(sources, start=1):
            target = staging_bmps / f"bg_{index:02d}.bmp"
            convert_background(source, target)
            verify_bmp(target)
            image_pairs.append((target, picture_dir / target.name))
            plan.append(f"install {target.name} -> {picture_dir / target.name} "
                        f"({target.stat().st_size} bytes)")

    # Preview uses the first track and first background.
    if built and image_pairs:
        make_preview(image_pairs[0][0], built[0][1], built[0][4], font_path,
                     PROJECT_ROOT / "tools" / "preview_screen.png")
        plan.append(f"preview -> {PROJECT_ROOT / 'tools' / 'preview_screen.png'}")

    if not args.skip_housekeeping:
        plan.append(f"move {music_dir / '01.mvi'} ... -> {music_dir / 'source_mp4' / 'mvi'}")
        plan.append(f"move {picture_dir / '*.jpg'} -> {picture_dir / 'src'}")
        plan.append(f"move {card / 'Checkmate_48k16_PCM.wav'} "
                    f"-> {music_dir / 'source_mp4'}")

    if args.dry_run:
        print("\n--dry-run: no card changes")
        for line in plan:
            print("  " + line)
        return 0

    for target, destination in [(t, music_dir / t.name) for t, *_ in built]:
        copy_fresh(target, destination)
    for target, destination in image_pairs:
        copy_fresh(target, destination)

    if not args.skip_housekeeping:
        print("\nhousekeeping:")
        messages = []
        source_wav = card / "Checkmate_48k16_PCM.wav"
        if source_wav.exists():
            messages.append(move_if_present(source_wav, music_dir / "source_mp4"))
        for path in sorted(music_dir.glob("*.mvi")):
            messages.append(move_if_present(path, music_dir / "source_mp4" / "mvi"))
        for path in sorted(picture_dir.glob("*.jpg")):
            messages.append(move_if_present(path, picture_dir / "src"))
        for message in messages:
            if message:
                print("  " + message)

    print("\ninstalled:")
    for line in plan:
        if line.startswith("install"):
            print("  " + line)
    print("\nverification files:")
    print(f"  {PROJECT_ROOT / 'tools' / 'preview_screen.png'}")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
