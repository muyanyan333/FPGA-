"""Convert a local video to the HX4S20 MVI video + canonical PCM soundtrack pair.

Profiles: MVI4 per-frame palette/30 fps (default) or 25 fps,
MVI3 global palette/20 fps, MVI2 RGB332/20 fps,
or legacy MVI1 RGB565LE/8 fps.
Both use 320x240 bottom-up frames and a 48k/16/stereo soundtrack.
Conversion is streamed to disk; a five-minute input does not fill RAM.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import wave

WIDTH, HEIGHT, SAMPLE_RATE = 320, 240, 48000


def convert(source, output, ffmpeg, profile='palette_30', fit='contain'):
    fps, pixel_format, bytes_per_pixel, signature = {
        'palette_20': (20, 'pal8', 1, b'MVI3'),
        'palette_25': (25, 'pal8', 1, b'MVI4'),
        'palette_30': (30, 'pal8', 1, b'MVI4'),
        'rgb332_20': (20, 'rgb8', 1, b'MVI2'),
        'rgb565_8': (8, 'rgb565le', 2, b'MVI1'),
    }[profile]
    frame_bytes = WIDTH * HEIGHT * bytes_per_pixel
    indexed = pixel_format=='pal8'
    dynamic = signature==b'MVI4'
    source, output = Path(source).resolve(), Path(output).resolve()
    if not source.is_file():
        raise ValueError(f'找不到输入视频：{source}')
    output.mkdir(parents=True, exist_ok=True)
    movie, soundtrack = output/'01.MVI', output/'00.wav'
    if movie.exists() or soundtrack.exists():
        raise ValueError('输出目录已有 01.MVI 或 00.wav，请选择新的目录，避免覆盖。')
    with tempfile.TemporaryDirectory(prefix='video-', dir=output) as temp:
        temp = Path(temp)
        raw, pcm = temp/'frames.rgb565', temp/'audio.pcm'
        if fit not in ('contain','cover'): raise ValueError('fit must be contain or cover')
        filters = (f'fps={fps},scale=320:240:force_original_aspect_ratio=' +
                   ('increase,crop=320:240,vflip' if fit=='cover' else
                    'decrease,pad=320:240:(ow-iw)/2:(oh-ih)/2:black,vflip'))
        if indexed:
            packed = temp/'indexed.pal8'
            if dynamic:
                # The palette changes every frame but remains one byte per
                # pixel on TF. Ordered dithering avoids moving error noise.
                filters=filters.replace('scale=320:240:', 'scale=320:240:flags=lanczos+accurate_rnd:')
                graph=(f'{filters},split[a][b];'
                    '[a]palettegen=stats_mode=single:max_colors=256:reserve_transparent=0[p];'
                    '[b][p]paletteuse=new=1:dither=bayer:bayer_scale=3')
                subprocess.run([ffmpeg,'-nostdin','-v','error','-i',str(source),'-t','300',
                    '-filter_complex',graph,'-an','-pix_fmt','pal8','-f','rawvideo',str(packed)],check=True)
            else:
                palette = temp/'palette.png'
                subprocess.run([ffmpeg,'-nostdin','-v','error','-i',str(source),'-t','300',
                    '-vf',filters+',palettegen=max_colors=256:reserve_transparent=0',
                    '-frames:v','1',str(palette)],check=True)
                subprocess.run([ffmpeg,'-nostdin','-v','error','-i',str(source),'-i',str(palette),
                    '-t','300','-filter_complex',f'[0:v]{filters}[v];[v][1:v]paletteuse=dither=sierra2_4a',
                    '-an','-pix_fmt','pal8','-f','rawvideo',str(packed)],check=True)
            palette_bytes = None
            with packed.open('rb') as src, raw.open('wb') as dst:
                while indices := src.read(WIDTH*HEIGHT):
                    colors = src.read(1024)
                    if len(indices)!=WIDTH*HEIGHT or len(colors)!=1024:
                        raise ValueError('Incomplete indexed frame')
                    if dynamic or palette_bytes is None:
                        palette_bytes=colors
                        rgb=b''.join(bytes((colors[i+2],colors[i+1],colors[i])) for i in range(0,1024,4))
                        dst.write(signature+rgb+(bytes([fps])+bytes(251) if dynamic else bytes(252)))
                    elif colors!=palette_bytes:
                        raise ValueError('Frame palette changed')
                    dst.write(indices)
        else:
            subprocess.run([ffmpeg, '-nostdin', '-v', 'error', '-i', str(source),
                            '-t', '300', '-an', '-vf', filters,
                            '-pix_fmt', pixel_format, '-f', 'rawvideo', str(raw)], check=True)
        count, partial = divmod(raw.stat().st_size - (1024 if indexed and not dynamic else 0),
                                frame_bytes+(1024 if dynamic else 0))
        if partial or count < 1:
            raise ValueError('转换输出缺帧或没有有效画面。')
        # Probe whether the source has audio; a silent source gets zero PCM.
        decoded = subprocess.run([ffmpeg, '-nostdin', '-v', 'error', '-i', str(source),
                                  '-t', '300', '-vn', '-map', '0:a:0?', '-ac', '2',
                                  '-ar', '48000', '-f', 's16le', str(pcm)],
                                 capture_output=True)
        if decoded.returncode and b'does not contain any stream' not in decoded.stderr:
            raise RuntimeError(decoded.stderr.decode('utf-8', errors='replace'))
        needed = count * (SAMPLE_RATE // fps) * 4
        if not pcm.exists(): pcm.touch()
        with pcm.open('r+b') as stream:
            stream.truncate(needed)  # pads a short source with silence
        with raw.open('r+b') as stream:
            stream.write(signature)
        wav_temp = temp/'00.wav'
        with wave.open(str(wav_temp), 'wb') as target, pcm.open('rb') as stream:
            target.setparams((2, 2, SAMPLE_RATE, 0, 'NONE', 'not compressed'))
            while chunk := stream.read(1024*1024): target.writeframesraw(chunk)
        with wav_temp.open('rb') as stream:
            header = stream.read(44)
        if header[:4]!=b'RIFF' or header[36:40]!=b'data':
            raise ValueError('音轨没有生成硬件要求的 44 字节 WAV 头。')
        # Create outside TemporaryDirectory so final files inherit the output
        # folder's ACL and remain readable by Windows tools and other users.
        movie_part, audio_part = output/'01.MVI.part', output/'00.wav.part'
        shutil.copyfile(raw, movie_part)
        shutil.copyfile(wav_temp, audio_part)
        os.replace(movie_part, movie)
        os.replace(audio_part, soundtrack)
    result = dict(source=source.name, fit=fit, width=WIDTH, height=HEIGHT, fps=fps,
                  frames=count, duration_seconds=count/fps,
                  video_bytes=movie.stat().st_size, audio_bytes=soundtrack.stat().st_size,
                  format=f'{signature.decode()}_{profile.upper()}_BOTTOM_UP_320x240')
    (output/'video_info.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    parser.add_argument('--profile', choices=['palette_30','palette_25','palette_20','rgb332_20','rgb565_8'], default='palette_30')
    parser.add_argument('--fit',choices=['contain','cover'],default='contain',help='contain保留全画面；cover保持比例并裁边铺满屏幕')
    args=parser.parse_args()
    if not args.ffmpeg: parser.error('需要 --ffmpeg 指定 FFmpeg 可执行文件')
    print(json.dumps(convert(args.source,args.output,args.ffmpeg,args.profile,args.fit),ensure_ascii=False,indent=2))
