"""Run the open RTL video regressions; encrypted vendor IP is not simulated.

Pass --iverilog/--vvp when Icarus is not on PATH. Results stay in _archive.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / 'lab_ex5_i2s-work/src/user_source/hdl_source'
TEST = ROOT / 'lab_ex5_i2s-work/src/test'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--only', nargs='+', help='Run only the named cases')
    args = parser.parse_args()
    cases = [
        ('spi_fast', 'spi_video_fast_read_tb', ['SD/spi_master.v', 'SD/sd_card_cmd.v'], {}, []),
        ('spi_legacy', 'spi_video_fast_read_tb', ['SD/spi_master.v', 'SD/sd_card_cmd.v'], {'FAST_ENGINE': 0}, []),
        ('video_dynamic', 'video_reader_tb', ['SD/exfat_raw_video_reader.v', 'SD/bmp_fit_scaler.v'], {'COMPACT': 1, 'INDEXED': 1, 'DYNAMIC': 1}, []),
        ('video_fragmented', 'video_reader_tb', ['SD/exfat_raw_video_reader.v', 'SD/bmp_fit_scaler.v'], {'COMPACT': 1, 'INDEXED': 1, 'DYNAMIC': 1}, ['+fragmented']),
        ('video_legacy', 'video_reader_tb', ['SD/exfat_raw_video_reader.v', 'SD/bmp_fit_scaler.v'], {'COMPACT': 1, 'INDEXED': 1}, []),
        ('video_eof', 'video_startup_tb', ['SD/sd_card_bmp.v', 'SD/bmp_fit_scaler.v', 'SD/exfat_raw_video_reader.v', 'SD/exfat_pcm_wav_reader.v'], {'COMPACT': 1, 'INDEXED': 1, 'DYNAMIC': 1, 'REAL_EOF': 1, 'TWO_FRAMES': 1}, []),
        ('video_return', 'video_auto_return_tb', ['top_tf_hdmi_audio.v'], {}, []),
        ('media_reset', 'media_reset_cdc_tb', ['top_tf_hdmi_audio.v', 'hdmi_phy_warpper.v', 'lane_lvds_10_1.v'], {}, []),
        ('volume', 'pcm_volume_tb', ['pcm_i2s_tx.v'], {}, []),
    ]
    names = {case[0] for case in cases}
    if args.only and set(args.only) - names:
        parser.error('Unknown cases: ' + ', '.join(sorted(set(args.only) - names)))
    if args.only:
        cases = [case for case in cases if case[0] in args.only]
    dest = ROOT / '_archive/video_optimize/tests'
    dest.mkdir(parents=True, exist_ok=True)

    def run(case):
        name, top, sources, params, runtime = case
        executable = dest / (name + '.vvp')
        # -i is required for intentionally isolated integration harnesses:
        # SD transport/catalog and encrypted hardware IP are driven by the TB.
        command = [args.iverilog, '-g2012', '-i', '-s', top, '-I', str(HDL / 'include'), '-o', str(executable)]
        command += [f'-P{top}.{key}={value}' for key, value in params.items()]
        command += [str(TEST / (top + '.v'))] + [str(HDL / source) for source in sources]
        log = dest / (name + '.log')
        try:
            with log.open('w', encoding='utf-8') as output:
                subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=120)
                subprocess.run([args.vvp, str(executable), *runtime], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=600)
            if 'PASS' not in log.read_text(encoding='utf-8'):
                raise RuntimeError('No PASS marker')
            print(f'PASS {name}', flush=True)
            return True
        except (subprocess.SubprocessError, OSError, RuntimeError) as error:
            print(f'FAIL {name}: {error}; see {log}', flush=True)
            return False

    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(run, cases))
    return 0 if all(results) else 1


if __name__ == '__main__':
    sys.exit(main())
