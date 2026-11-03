"""Stage the user supplied TF-card song as track 08 without modifying the card."""
import csv
import shutil
import subprocess
import wave
from pathlib import Path

import imageio_ffmpeg
from prepare_card import build_lyr2_from_lrc, DEFAULT_FONT, parse_lrc

work = Path(__file__).resolve().parents[1]
stage = work / 'media' / 'track08'
stage.mkdir(exist_ok=True)
source = Path('E:/MUSIC/source_mp4/恶作剧.mp4')
lrc_source = Path('E:/MUSIC/恶作剧.lrc')
assert source.is_file() and lrc_source.is_file()
for encoding in ('utf-8-sig', 'gb18030', 'big5'):
    try:
        text = lrc_source.read_text(encoding=encoding)
        break
    except UnicodeDecodeError:
        continue
else:
    raise ValueError('Unrecognized lyric encoding')
lrc = work / 'lyrics_lrc' / '08.lrc'
lrc.write_text(text, encoding='utf-8')
events = parse_lrc(lrc)
assert events, 'No timed lyrics'
raw = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-v', 'error', '-i', str(source),
                      '-map', '0:a:0', '-vn', '-ac', '2', '-ar', '48000',
                      '-f', 's16le', '-acodec', 'pcm_s16le', 'pipe:1'],
                     check=True, stdout=subprocess.PIPE).stdout
assert raw and len(raw) % 4 == 0
with wave.open(str(stage / '08.wav'), 'wb') as out:
    out.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
    out.writeframes(raw)
duration_ms = round(len(raw) / 192)
assert events[-1][0] <= duration_ms + 2000, 'Lyrics exceed audio duration'
blob, frames, _ = build_lyr2_from_lrc(lrc, '恶作剧', duration_ms, DEFAULT_FONT, 8)
(stage / '08.lyr').write_bytes(blob)
playlist = work / 'media' / 'playlist.csv'
with playlist.open(encoding='utf-8-sig', newline='') as f:
    reader = csv.DictReader(f)
    fields = reader.fieldnames
    rows = list(reader)
assert fields
entry = dict(track='08', title='恶作剧', wav='08.wav', lyric='08.lyr', cover='', source='source_mp4/恶作剧.mp4')
existing = [row for row in rows if row['track'] == '08' or row['title'] == '恶作剧']
assert not existing or existing == [entry], 'Track 08 already occupied'
if not existing:
    rows.append(entry)
with playlist.open('w', encoding='utf-8', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
shutil.copyfile(playlist, stage / 'playlist.csv')
with wave.open(str(stage / '08.wav'), 'rb') as audio:
    assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (2, 2, 48000)
assert (stage / '08.wav').read_bytes()[36:40] == b'data'
assert blob[:6] == b'LYR1\x02\x00' and blob[24] == 8
print(f'Staged track 08: {duration_ms / 1000:.3f}s, {frames} lyric frames, {len(events)} lyric events')
