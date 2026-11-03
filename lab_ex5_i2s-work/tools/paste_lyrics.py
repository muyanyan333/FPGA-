#!/usr/bin/env python3
"""Paste lyrics for one or more songs and generate LRC files in batch.

Interactive use:
    python tools/paste_lyrics.py

For each song:
  1. enter the song name (or track number),
  2. paste the lyrics,
  3. type END on its own line to finish that song.

The pasted block may be:
  * a normal LRC with [mm:ss.xx] timestamps (used as-is),
  * lines prefixed with mm:ss.xx (converted to LRC),
  * plain lyric lines (timestamps are generated from the WAV duration).

Then the tool writes lyrics_lrc/NN.lrc and optionally runs prepare_card.py to
render LYR2 and copy it to the card.  Only metadata is printed; lyric text is
never echoed to the log.
"""
from __future__ import annotations

import argparse
import csv
import difflib
import re
import shutil
import subprocess
import sys
import wave
from pathlib import Path

WORK = Path(__file__).resolve().parents[1]
PLAYLIST = WORK / "media" / "playlist.csv"
BACKUP_PLAYLIST = WORK / "media" / "playlist_12tracks.csv"
DEST = WORK / "lyrics_lrc"
CARD = Path("E:/")

LRC_TIME = re.compile(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")
PLAIN_TIME = re.compile(r"^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\s+(.*)$")
META = re.compile(r"^\[(ti|ar|al|by|offset):.*\]$", re.IGNORECASE)


def normalize(text: str) -> str:
    text = text.lower()
    return re.sub(r"[\s\-_.,，。、:：()（）\[\]【】《》'\"!！?？]", "", text)


def ms_from(groups) -> int:
    minutes = int(groups[0])
    seconds = int(groups[1])
    fraction = groups[2] or ""
    if len(fraction) == 0:
        millis = 0
    elif len(fraction) == 1:
        millis = int(fraction) * 100
    elif len(fraction) == 2:
        millis = int(fraction) * 10
    else:
        millis = int(fraction)
    return minutes * 60000 + seconds * 1000 + millis


def fmt(ms: int) -> str:
    ms = max(0, int(ms))
    minutes, rem = divmod(ms, 60000)
    seconds, millis = divmod(rem, 1000)
    return f"[{minutes:02d}:{seconds:02d}.{millis // 10:02d}]"


def load_tracks(card: Path, path: Path = PLAYLIST):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    tracks = []
    for row in rows:
        tracks.append({
            "track": row["track"].strip(),
            "title": row["title"].strip(),
            "wav": row["wav"].strip(),
            "lyric": row["lyric"].strip(),
            "cover": row.get("cover", "").strip(),
            "source": row.get("source", "").strip(),
            "norm": normalize(row["title"]),
        })
    return tracks


def ensure_wav(card: Path, track: dict):
    """Restore a track WAV from removed_songs if it was cleaned earlier."""
    target = card / "MUSIC" / track["wav"]
    if target.is_file():
        return True
    backup = card / "MUSIC" / "source_mp4" / "removed_songs" / track["wav"]
    if backup.is_file():
        shutil.copyfile(backup, target)
        print(f"  已从 removed_songs 恢复 {track['wav']}")
        return True
    print(f"  warning: 卡上找不到 {track['wav']}，也没有 removed_songs 备份")
    return False


def wav_info(card: Path, track: dict):
    path = card / "MUSIC" / track["wav"]
    if not path.is_file():
        return None, None
    try:
        with wave.open(str(path), "rb") as handle:
            seconds = handle.getnframes() / handle.getframerate()
            return seconds, (handle.getframerate(), handle.getnchannels(),
                             handle.getsampwidth())
    except (wave.Error, EOFError):
        return None, None


def match_track(query: str, tracks):
    query = query.strip()
    if query.isdigit():
        for track in tracks:
            if track["track"] == query:
                return track
        return None
    norm = normalize(query)
    best, score = None, 0.0
    for track in tracks:
        if not track["norm"]:
            continue
        if norm == track["norm"]:
            return track
        ratio = difflib.SequenceMatcher(None, norm, track["norm"]).ratio()
        if norm in track["norm"] or track["norm"] in norm:
            ratio = max(ratio, 0.9)
        if ratio > score:
            best, score = track, ratio
    return best if score >= 0.55 else None


def parse_block(lines):
    """Return ('lrc', text) or ('timed', events) or ('plain', lines)."""
    meaningful = [line for line in lines if line.strip()]
    if not meaningful:
        return "plain", []
    stamps = sum(1 for line in meaningful if LRC_TIME.search(line))
    plain_stamps = sum(1 for line in meaningful if PLAIN_TIME.match(line))
    if stamps >= max(2, len(meaningful) // 2):
        return "lrc", "\n".join(lines)
    if plain_stamps >= max(2, len(meaningful) // 2):
        events = []
        for line in meaningful:
            match = PLAIN_TIME.match(line)
            if match:
                events.append((ms_from((match.group(1), match.group(2),
                                        match.group(3))), match.group(4).strip()))
        return "timed", events
    return "plain", [line.strip() for line in meaningful if line.strip()]


def ask_seconds(prompt: str, default: float) -> float:
    value = input(f"{prompt}（默认 {default:.2f}）: ").strip()
    if not value:
        return default
    if ":" in value:
        parts = value.split(":")
        return float(parts[0]) * 60 + float(parts[1])
    return float(value)


def write_lrc(path: Path, title: str, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    stamps = [ms_from(m.groups()) for m in LRC_TIME.finditer(text)]
    print(f"  wrote {path.name}: {len(stamps)} timestamps, "
          f"last {max(stamps)/1000 if stamps else 0:.1f}s")


def convert_block(title: str, kind, payload, duration_s: float | None,
                  start_s: float, interval_s: float | None) -> str:
    if kind == "lrc":
        return payload if payload.endswith("\n") else payload + "\n"
    if kind == "timed":
        events = sorted(payload, key=lambda item: item[0])
        body = "\n".join(f"{fmt(ms)}{text}" for ms, text in events)
        return f"[ti:{title}]\n{body}\n"
    lines = payload
    if not lines:
        raise ValueError("empty lyric block")
    if interval_s is None:
        total = duration_s if duration_s else 240.0
        usable = max(10.0, total - start_s - 5.0)
        interval_s = max(1.0, usable / len(lines))
        print(f"  auto timing: start {start_s:.1f}s, interval {interval_s:.2f}s "
              f"({len(lines)} lines)")
    body = "\n".join(f"{fmt((start_s + index * interval_s) * 1000)}{line}"
                     for index, line in enumerate(lines))
    return f"[ti:{title}]\n{body}\n"


def add_track_to_playlist(track: dict):
    with PLAYLIST.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if any(row["track"].strip() == track["track"] for row in rows):
        return
    with PLAYLIST.open("a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=["track", "title", "wav", "lyric", "cover", "source"])
        writer.writerow({
            "track": track["track"], "title": track["title"],
            "wav": track["wav"], "lyric": track["lyric"],
            "cover": track.get("cover", ""), "source": track.get("source", ""),
        })
    print(f"  appended track {track['track']} to {PLAYLIST.name}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Interactive paste-to-LRC generator for the FPGA player.")
    parser.add_argument("--card", default="E:/")
    parser.add_argument("--dest", default=str(DEST),
                        help="output folder for NN.lrc (default lyrics_lrc)")
    parser.add_argument("--start", type=float, default=None,
                        help="plain-text start time in seconds (asked if omitted)")
    parser.add_argument("--interval", type=float, default=None,
                        help="seconds per plain lyric line (default: fit audio)")
    parser.add_argument("--write-card", action="store_true",
                        help="after the batch, render LYR2 and copy to the card")
    args = parser.parse_args()

    card = Path(args.card)
    dest = Path(args.dest)
    tracks = load_tracks(card)
    written = []

    print("粘贴歌词工具。歌名留空直接回车结束。")
    print("每首歌粘贴完后，单独一行输入 END。\n")

    while True:
        query = input("歌名或曲目号: ").strip()
        if not query:
            break
        track = match_track(query, tracks)
        if track is None and BACKUP_PLAYLIST.is_file():
            backup = load_tracks(card, BACKUP_PLAYLIST)
            track = match_track(query, backup)
            if track is not None:
                print(f"  从原始清单找到：曲目 {track['track']}《{track['title']}》")
        if track is None:
            print("  未找到该歌名。")
            track_no = input("  请输入曲目号 (1-16): ").strip()
            if not track_no.isdigit() or not (1 <= int(track_no) <= 16):
                print("  无效曲目号，跳过。")
                continue
            title = input("  歌名: ").strip() or track_no
            number = f"{int(track_no):02d}"
            track = {"track": number, "title": title,
                     "wav": f"{number}.wav", "lyric": f"{number}.lyr",
                     "cover": f"music_{number}.bmp", "source": "",
                     "norm": normalize(title)}
        if not any(item["track"] == track["track"] for item in tracks):
            ensure_wav(card, track)
            tracks.append(track)
            add_track_to_playlist(track)
        print(f"  -> 曲目 {track['track']}《{track['title']}》")

        print("  粘贴歌词，最后单独一行输入 END：")
        lines = []
        while True:
            line = sys.stdin.readline()
            if line == "":
                break
            line = line.rstrip("\n")
            if line.strip().upper() == "END":
                break
            lines.append(line)

        kind, payload = parse_block(lines)
        seconds, fmt_info = wav_info(card, track)
        if seconds is None:
            print("  warning: 卡上的 WAV 找不到，自动定时将按 240s 估算")
        if kind == "lrc":
            print("  检测到 LRC 时间轴，直接使用")
            text = convert_block(track["title"], kind, payload, seconds, 0, None)
        elif kind == "timed":
            print("  检测到 mm:ss 前缀，转换为 LRC")
            text = convert_block(track["title"], kind, payload, seconds, 0, None)
        else:
            start = args.start
            if start is None:
                start = ask_seconds("首句时间(秒或 mm:ss)", 0.0)
            interval = args.interval
            if interval is None:
                answer = input("每行间隔秒数（回车=按音频时长均分）: ").strip()
                if answer:
                    interval = float(answer)
            text = convert_block(track["title"], kind, payload, seconds, start, interval)

        target = dest / f"{track['track']}.lrc"
        write_lrc(target, track["title"], text)
        written.append(target)
        if seconds is not None:
            print(f"  WAV {seconds:.1f}s "
                  f"({fmt_info[0]} Hz, {fmt_info[1]} ch, {fmt_info[2]*8}-bit)")
        print()

    if not written:
        print("没有写入任何文件。")
        return 0

    print(f"本次生成 {len(written)} 个 LRC：")
    for path in written:
        print(f"  {path}")
    if args.write_card or input("现在渲染 LYR2 并写入卡？(y/n): ").strip().lower() == "y":
        command = [sys.executable, str(WORK / "tools" / "prepare_card.py"),
                   "--card", str(card), "--skip-images", "--skip-housekeeping"]
        print("运行:", " ".join(command))
        subprocess.run(command, check=False)
    else:
        print("未写卡。之后可运行：python tools/prepare_card.py --skip-images --skip-housekeeping")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
