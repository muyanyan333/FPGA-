"""LRC metadata placement must not change lyric/audio alignment."""
import tempfile
import unittest
from pathlib import Path
import sys
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.prepare_card import parse_lrc, wav_duration, validate_playlist


class OffsetTest(unittest.TestCase):
    def test_numeric_pairing(self):
        track = {"track": "02", "wav": "02.wav", "lyric": "02.lyr"}
        validate_playlist([track])
        with self.assertRaises(ValueError):
            validate_playlist([track, track])
        with self.assertRaises(ValueError):
            validate_playlist([{**track, "lyric": "06.lyr"}])

    def test_global_offset_before_or_after_events(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.lrc"
            for text in (
                "[offset:-1500]\n[00:01.17]test\n[00:02.50]second\n",
                "[00:01.17]test\n[00:02.50]second\n[offset:-1500]\n",
            ):
                path.write_text(text, encoding="utf-8")
                self.assertEqual(parse_lrc(path), [(2670, "test"), (4000, "second")])

    def test_hardware_wav_format(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.wav"
            with wave.open(str(path), "wb") as handle:
                handle.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
                handle.writeframes(bytes(192000))
            self.assertEqual(wav_duration(path), 1.0)
            content = bytearray(path.read_bytes())
            content[36:40] = b"LIST"
            path.write_bytes(content)
            with self.assertRaises(ValueError):
                wav_duration(path)


if __name__ == "__main__":
    unittest.main()
