#!/usr/bin/env python3
"""Batch-import LRC files that the user obtained themselves.

This tool does NOT download lyrics.  It scans a folder for .lrc files, matches
them to the 12 playlist tracks by track number / [ti:] tag / filename, checks
the timestamps against the WAV durations, and copies them to lyrics_lrc/NN.lrc.

Only metadata (timestamps, durations, match status) is printed; lyric text is
never reproduced on stdout.
"""
from __future__ import annotations

import argparse
import csv
import difflib
import re
import shutil
import sys
import wave
from pathlib import Path

WORK = Path(__file__).resolve().parents[1]
DEFAULT_PLAYLIST = WORK / "media" / "playlist.csv"
DEFAULT_DEST = WORK / "lyrics_lrc"

TIME_RE = re.compile(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")
TI_RE = re.compile(r"\[ti:(.*?)\]", re.IGNORECASE)
OFFSET_RE = re.compile(r"\[offset:([+-]?\d+)\]", re.IGNORECASE)


def read_text(path: Path) -> str:
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "big5"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    return path.read_text(encoding="utf-8", errors="replace")


def lrc_meta(path: Path):
    text = read_text(path)
    title = ""
    match = TI_RE.search(text)
    if match:
        title = match.group(1).strip()
    times = []
    offset = 0
    match = OFFSET_RE.search(text)
    if match:
        offset = int(match.group(1))
    for match in TIME_RE.finditer(text):
        minutes = int(match.group(1))
        seconds = int(match.group(2))
        fraction = match.group(3) or ""
        if len(fraction) == 0:
            millis = 0
        elif len(fraction) == 1:
            millis = int(fraction) * 100
        elif len(fraction) == 2:
            millis = int(fraction) * 10
        else:
            millis = int(fraction)
        times.append(max(0, minutes * 60000 + seconds * 1000 + millis - offset))
    return title, times


def normalize(text: str) -> str:
    text = text.lower()
    return re.sub(r"[\s\-_.,，。、:：()（）\[\]【】《》'\"!！?？]", "", text)


def wav_seconds(path: Path) -> float | None:
    if not path.is_file():
        return None
    try:
        with wave.open(str(path), "rb") as handle:
            return handle.getnframes() / handle.getframerate()
    except (wave.Error, EOFError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Match user-provided LRC files to playlist tracks and copy "
                    "them to lyrics_lrc/. This tool never downloads lyrics.")
    parser.add_argument("--src", required=True,
                        help="folder containing the .lrc files you downloaded")
    parser.add_argument("--dest", default=str(DEFAULT_DEST))
    parser.add_argument("--playlist", default=str(DEFAULT_PLAYLIST))
    parser.add_argument("--card", default="E:/",
                        help="card root for WAV duration checks (default E:/)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true",
                        help="overwrite existing lyrics_lrc/NN.lrc")
    args = parser.parse_args()

    src = Path(args.src)
    dest = Path(args.dest)
    card = Path(args.card)
    if not src.is_dir():
        print(f"error: {src} is not a folder", file=sys.stderr)
        return 2

    with Path(args.playlist).open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    tracks = []
    for row in rows:
        stem = Path(row["lyric"]).stem
        tracks.append({
            "stem": stem,
            "title": row["title"],
            "norm": normalize(row["title"]),
            "wav": card / "MUSIC" / row["wav"],
            "matched": None,
        })

    lrc_files = sorted(p for p in src.rglob("*") if p.suffix.lower() == ".lrc")
    print(f"found {len(lrc_files)} LRC files in {src}")

    for path in lrc_files:
        title, times = lrc_meta(path)
        if not times:
            print(f"  skip (no timestamps): {path.name}")
            continue
        stem_guess = path.stem.lower()
        best = None
        best_score = 0.0
        for track in tracks:
            if track["matched"] is not None:
                continue
            score = 0.0
            if re.search(rf"\b{re.escape(track['stem'])}\b", stem_guess):
                score = 1.0
            else:
                haystack = normalize(path.stem + " " + title)
                if track["norm"] and track["norm"] in haystack:
                    score = 0.98
                else:
                    score = difflib.SequenceMatcher(
                        None, track["norm"], normalize(path.stem + " " + title)
                    ).ratio()
            if score > best_score:
                best_score = score
                best = track
        if best is None or best_score < 0.5:
            print(f"  unmatched ({best_score:.2f}): {path.name}")
            continue
        best["matched"] = path
        last_ms = max(times)
        wav_s = wav_seconds(best["wav"])
        if wav_s is None:
            delta = "wav n/a"
        else:
            delta = f"{(last_ms/1000.0) - wav_s:+.1f}s"
        print(f"  {best['stem']} <- {path.name}  "
              f"items={len(times)} last={last_ms/1000:.1f}s wav={wav_s or 0:.1f}s "
              f"delta={delta} score={best_score:.2f}")

    dest.mkdir(parents=True, exist_ok=True)
    installed = 0
    print("\nresult:")
    for track in tracks:
        path = track["matched"]
        if path is None:
            print(f"  {track['stem']} {track['title']}: NO LRC (will keep v2 extraction)")
            continue
        target = dest / f"{track['stem']}.lrc"
        if target.exists() and not args.force:
            print(f"  {track['stem']} {track['title']}: {target.name} already exists "
                  f"(use --force to replace)")
            continue
        print(f"  {track['stem']} {track['title']}: {path.name} -> {target}")
        if not args.dry_run:
            if target.exists():
                target.unlink()
            shutil.copyfile(path, target)
        installed += 1

    if args.dry_run:
        print("\n--dry-run: nothing copied")
    else:
        print(f"\ncopied {installed} LRC files to {dest}")
        print("next: python tools/prepare_card.py --dry-run")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
