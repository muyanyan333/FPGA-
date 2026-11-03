"""Export Git-visible source files, excluding local data and generated output."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
git = ['git', '-c', f'safe.directory={ROOT.as_posix()}']
raw = subprocess.check_output(git + ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT)
names = sorted(set(raw.decode('utf-8').rstrip('\0').split('\0')))
for name in names:
    p = Path(name)
    assert p.suffix.lower() not in {'.keystore', '.jks', '.pem', '.p12', '.pfx', '.wav', '.mp3', '.mp4', '.lrc', '.lyr'}, name
    assert p.name not in {'local.properties', '.env'}, name
    assert not any(part in {'_archive', 'android_toolchain', '.android_gradle', '.git', 'signing'} for part in p.parts), name
    assert (ROOT / p).stat().st_size < 10 * 1024 * 1024, f'Unexpected large file: {name}'

# Every path in the FPGA project must also be available in a clean source export.
project = Path('lab_ex5_i2s-work/src/td_project/full_camera_player.prj')
for ref in re.findall(r'<File Path="([^"]+)"', (ROOT / project).read_text(encoding='utf-8')):
    rel = (ROOT / project.parent / ref).resolve().relative_to(ROOT).as_posix()
    assert rel.lower() in {n.lower() for n in names}, f'Project dependency excluded: {rel}'

output = ROOT / 'FPGA_Multimedia_GitHub_Source.zip'
manifest = []
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for name in names:
        data = (ROOT / name).read_bytes()
        z.writestr(name, data)
        manifest.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    z.writestr('SOURCE_MANIFEST.json', json.dumps(manifest, ensure_ascii=False, indent=2))
with zipfile.ZipFile(output) as z:
    for item in manifest:
        assert hashlib.sha256(z.read(item['path'])).hexdigest() == item['sha256']
print(f'Export verified: {len(names)} files, {sum(i["bytes"] for i in manifest):,} source bytes')
print(output)
