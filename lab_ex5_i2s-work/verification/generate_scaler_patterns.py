"""Generate uncompressed RGB BMPs for checking the FPGA's 640x480 scaler."""

from pathlib import Path
import wave
from PIL import Image, ImageDraw, ImageFont


OUT = Path(__file__).with_name("scaler_bmps")
CASES = [
    ("01_native_640x480.bmp", 640, 480),
    ("02_upscale_320x240.bmp", 320, 240),
    ("03_wide_1280x720.bmp", 1280, 720),
    ("04_portrait_480x800.bmp", 480, 800),
    ("05_padding_321x240.bmp", 321, 240),
]


def font(size: int):
    for name in ("C:/Windows/Fonts/arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def pattern(width: int, height: int) -> Image.Image:
    image = Image.new("RGB", (width, height), (230, 235, 242))
    draw = ImageDraw.Draw(image)
    unit = max(2, min(width, height) // 48)
    for x in range(0, width, max(1, width // 8)):
        draw.line((x, 0, x, height - 1), fill=(170, 180, 190), width=1)
    for y in range(0, height, max(1, height // 6)):
        draw.line((0, y, width - 1, y), fill=(170, 180, 190), width=1)
    draw.rectangle((0, 0, width - 1, height - 1), outline=(20, 20, 20), width=unit)
    corner = max(20, min(width, height) // 9)
    draw.rectangle((unit, unit, corner, corner), fill=(235, 50, 45))
    draw.rectangle((width - corner, unit, width - unit - 1, corner), fill=(45, 185, 75))
    draw.rectangle((unit, height - corner, corner, height - unit - 1), fill=(50, 90, 230))
    draw.rectangle((width - corner, height - corner, width - unit - 1, height - unit - 1), fill=(245, 195, 35))
    cx, cy = width // 2, height // 2
    radius = min(width, height) // 5
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                 outline=(25, 25, 25), width=max(2, unit // 2))
    draw.line((cx - radius, cy, cx + radius, cy), fill=(25, 25, 25), width=2)
    draw.line((cx, cy - radius, cx, cy + radius), fill=(25, 25, 25), width=2)
    label = f"{width} x {height}"
    label_font = font(max(18, min(width, height) // 12))
    bounds = draw.textbbox((0, 0), label, font=label_font)
    text_w, text_h = bounds[2] - bounds[0], bounds[3] - bounds[1]
    draw.rectangle((cx - text_w // 2 - unit, cy - text_h // 2 - unit,
                    cx + text_w // 2 + unit, cy + text_h // 2 + unit),
                   fill=(255, 255, 255), outline=(20, 20, 20), width=2)
    draw.text((cx - text_w // 2, cy - text_h // 2 - bounds[1]),
              label, fill=(15, 15, 15), font=label_font)
    if width == 1280:
        for x in range(240, 440):
            draw.line((x, 140, x, 190), fill=(0, 0, 0) if x & 1 else (255, 255, 255))
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, width, height in CASES:
        path = OUT / name
        pattern(width, height).save(path, format="BMP")
        with Image.open(path) as check:
            assert check.format == "BMP" and check.mode == "RGB"
            assert check.size == (width, height)
        print(f"{path.name}: {width}x{height}, {path.stat().st_size} bytes")
    silence = OUT / "06_silence_48k_16bit.wav"
    with wave.open(str(silence), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(48000)
        audio.writeframes(b"\x00\x00" * (48000 * 2))
    print(f"{silence.name}: 48 kHz mono PCM, {silence.stat().st_size} bytes")


if __name__ == "__main__":
    main()
