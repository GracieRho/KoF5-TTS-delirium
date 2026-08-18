from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.training.vocab import (  # noqa: E402
    VocabError,
    characters_in_manifest,
    new_characters,
    read_vocab,
)


class VocabTests(unittest.TestCase):
    def test_vocab_ignores_trailing_newline_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "vocab.txt"
            path.write_text("a\nb\n \n", encoding="utf-8")
            self.assertEqual(read_vocab(path), ["a", "b", " "])

    def test_manifest_characters_are_normalized_to_nfc(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "metadata.csv"
            path.write_text("audio_file|text\nwavs/a.flac|안녕\n", encoding="utf-8")
            self.assertEqual(characters_in_manifest(path), {"안", "녕"})

    def test_new_characters_are_sorted_and_exclude_known(self) -> None:
        self.assertEqual(new_characters(["a", "안"], {"안", "녕", "가"}), ("가", "녕"))

    def test_empty_vocab_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "vocab.txt"
            path.write_text("", encoding="utf-8")
            with self.assertRaises(VocabError):
                read_vocab(path)


if __name__ == "__main__":
    unittest.main()
