from __future__ import annotations

import math
import shutil
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.preprocessing.audio import (  # noqa: E402
    TARGET_CHANNELS,
    TARGET_CODEC,
    TARGET_SAMPLE_FORMAT,
    TARGET_SAMPLE_RATE,
    convert_wav_tree,
    probe_flac,
)


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg 필요")
class AudioConversionIntegrationTests(unittest.TestCase):
    def _write_stereo_wav(self, destination: Path) -> None:
        destination.parent.mkdir(parents=True)
        frames = bytearray()
        sample_rate = 44_100
        for index in range(sample_rate // 20):
            sample = int(10_000 * math.sin(2 * math.pi * 440 * index / sample_rate))
            frames.extend(struct.pack("<hh", sample, -sample))
        with wave.open(str(destination), "wb") as wav_file:
            wav_file.setnchannels(2)
            wav_file.setsampwidth(2)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(frames)

    def test_conversion_preserves_tree_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "raw" / "speaker-a" / "sample.WAV"
            output = root / "flac"
            self._write_stereo_wav(source)

            first = convert_wav_tree(root / "raw", output)
            destination = output / "speaker-a" / "sample.flac"
            stream = probe_flac(destination, shutil.which("ffprobe") or "ffprobe")
            second = convert_wav_tree(root / "raw", output)

        self.assertEqual((first.converted, first.skipped), (1, 0))
        self.assertEqual((second.converted, second.skipped), (0, 1))
        self.assertEqual(stream["codec_name"], TARGET_CODEC)
        self.assertEqual(stream["sample_rate"], str(TARGET_SAMPLE_RATE))
        self.assertEqual(stream["channels"], TARGET_CHANNELS)
        self.assertEqual(stream["sample_fmt"], TARGET_SAMPLE_FORMAT)
        self.assertEqual(stream["bits_per_raw_sample"], "16")


if __name__ == "__main__":
    unittest.main()
