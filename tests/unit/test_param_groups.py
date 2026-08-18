from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.training.param_groups import (  # noqa: E402
    ParamGroupError,
    is_trainable,
    resolve_targets,
)


class ParamGroupTests(unittest.TestCase):
    def test_named_groups_resolve_to_prefixes(self) -> None:
        prefixes, blocks = resolve_targets(["text_embedding", "text_encoder"], depth=22)
        self.assertEqual(blocks, set())
        self.assertTrue(
            is_trainable("transformer.text_embed.text_embed.weight", prefixes, blocks)
        )
        self.assertTrue(
            is_trainable("transformer.text_embed.text_blocks.0.dwconv.weight", prefixes, blocks)
        )
        self.assertFalse(
            is_trainable("transformer.transformer_blocks.0.attn.to_q.weight", prefixes, blocks)
        )

    def test_block_range_is_inclusive_and_bounded(self) -> None:
        prefixes, blocks = resolve_targets(["dit_blocks:0-5"], depth=22)
        self.assertEqual(blocks, set(range(6)))
        self.assertTrue(
            is_trainable("transformer.transformer_blocks.5.ff.ff.0.0.weight", prefixes, blocks)
        )
        self.assertFalse(
            is_trainable("transformer.transformer_blocks.6.ff.ff.0.0.weight", prefixes, blocks)
        )
        with self.assertRaises(ParamGroupError):
            resolve_targets(["dit_blocks:0-22"], depth=22)

    def test_all_selects_every_group(self) -> None:
        prefixes, blocks = resolve_targets(["all"], depth=22)
        self.assertEqual(blocks, set(range(22)))
        self.assertTrue(is_trainable("transformer.proj_out.weight", prefixes, blocks))


if __name__ == "__main__":
    unittest.main()
