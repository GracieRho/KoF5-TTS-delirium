from __future__ import annotations

import ast
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("generate_architecture.py")
SPEC = importlib.util.spec_from_file_location("generate_architecture", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ArchitectureGeneratorTests(unittest.TestCase):
    def test_module_name_uses_project_package(self) -> None:
        root = Path("/tmp/src/kof5_tts")
        self.assertEqual(
            MODULE.module_name(root / "training" / "trainer.py", root),
            "kof5_tts.training.trainer",
        )

    def test_relative_import_is_resolved(self) -> None:
        self.assertEqual(
            MODULE.resolve_import_from("kof5_tts.training.trainer", "utils", 2),
            "kof5_tts.utils",
        )

    def test_python_module_finds_internal_imports(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "kof5_tts"
            path = root / "training" / "trainer.py"
            path.parent.mkdir(parents=True)
            path.write_text(
                "import kof5_tts.evaluation\nfrom ..preprocessing import audio\n",
                encoding="utf-8",
            )
            record = MODULE.parse_python_module(path, root)
        self.assertEqual(
            record["imports"],
            ["kof5_tts.evaluation", "kof5_tts.preprocessing"],
        )

    def test_generated_outputs_are_deterministic(self) -> None:
        catalog = MODULE.build_catalog()
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_path = Path(first)
            second_path = Path(second)
            MODULE.write_outputs(first_path, catalog)
            MODULE.write_outputs(second_path, catalog)
            self.assertEqual(MODULE.compare_outputs(first_path, second_path), [])

    def test_generated_mermaid_is_valid_ast_independent_text(self) -> None:
        mermaid = MODULE.render_mermaid(MODULE.build_catalog())
        self.assertTrue(mermaid.startswith("flowchart LR\n"))
        self.assertIn("원본 WAV", mermaid)
        ast.parse(SCRIPT.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
