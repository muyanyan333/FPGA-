"""Remove baked-in black padding, preserving source BMP backups and all content."""
import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--card", default="E:/")
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    folder = Path(args.card) / "picture"
    staging = ROOT / "tools/_staging/aspect_backgrounds"
    backups = ROOT / "media/background_originals"
    staging.mkdir(parents=True, exist_ok=True)
    backups.mkdir(parents=True, exist_ok=True)
    paths = sorted(folder.glob("bg_*.bmp"))
    if len(paths) != 12:
        raise ValueError(f"Expected 12 existing backgrounds, found {len(paths)}")
    sheet = Image.new("RGB", (640, 780), "#202020")
    draw = ImageDraw.Draw(sheet)
    records = []
    for index, path in enumerate(paths):
        backup = backups / path.name
        if not backup.exists():
            shutil.copy2(path, backup)
        original = Image.open(backup).convert("RGB")
        bbox = original.getbbox() or (0, 0, original.width, original.height)
        content = original.crop(bbox)
        # The hardware source reader requires >=320x240. Upscale only as much
        # as necessary; never add new padding to satisfy that constraint.
        scale = max(1.0, 320 / content.width, 240 / content.height)
        dimensions = (math.ceil(content.width * scale), math.ceil(content.height * scale))
        if dimensions[0] > 1920 or dimensions[1] > 1080:
            raise ValueError(f"{path.name}: content aspect cannot fit supported BMP bounds")
        prepared = content.resize(dimensions, Image.Resampling.LANCZOS)
        target = staging / path.name
        prepared.save(target, "BMP")
        original_hash, output_hash = digest(backup), digest(target)
        if digest(path) not in (original_hash, output_hash):
            raise ValueError(f"{path.name}: card file changed since original backup; refusing overwrite")
        record = dict(name=path.name, original_size=original.size, content_box=bbox,
                      prepared_size=dimensions, original_sha256=original_hash,
                      prepared_sha256=output_hash)
        records.append(record)
        x, y = (index % 2) * 320, (index // 2) * 130
        for image, offset in ((original, 0), (prepared, 160)):
            preview = ImageOps.contain(image, (154, 105))
            sheet.paste(preview, (x + offset + (154-preview.width)//2, y+20+(105-preview.height)//2))
        draw.text((x+4,y+2), f"{path.name} BEFORE / CONTENT {dimensions[0]}x{dimensions[1]}", fill="white")
        print(f"{path.name}: {original.size} box={bbox} -> {dimensions}")
    (staging / "manifest.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
    sheet.save(staging / "comparison.png")
    if args.install:
        # Validate the complete set before touching any card file.
        for record in records:
            target = folder / record["name"]
            shutil.copy2(staging / record["name"], target)
            if digest(target) != record["prepared_sha256"]:
                raise IOError(f"{target}: copy verification failed")
        print("Installed and hash-verified 12 BMPs; original backups retained locally.")
    else:
        print("Prepared locally; card unchanged. Review comparison.png before --install.")


if __name__ == "__main__":
    main()
