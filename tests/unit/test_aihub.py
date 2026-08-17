from __future__ import annotations

import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.preprocessing.aihub import (  # noqa: E402
    AihubError,
    build_download_command,
    download_dataset,
    environment_with_api_key,
    normalize_file_keys,
)


class AihubTests(unittest.TestCase):
    def test_file_keys_are_split_deduplicated_and_validated(self) -> None:
        self.assertEqual(normalize_file_keys(["11,22", "22", " 33 "]), ("11", "22", "33"))
        with self.assertRaises(AihubError):
            normalize_file_keys(["11; echo unsafe"])

    def test_download_command_never_contains_api_key(self) -> None:
        command, file_keys = build_download_command("aihubshell", "123", ["4", "5"])
        self.assertEqual(
            command,
            ["aihubshell", "-mode", "d", "-datasetkey", "123", "-filekey", "4,5"],
        )
        self.assertEqual(file_keys, ("4", "5"))

    def test_environment_reads_local_dotenv_without_overriding_process_value(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            env_file = Path(temporary) / ".env"
            env_file.write_text("# local only\nAIHUB_APIKEY='from-file'\n", encoding="utf-8")
            loaded = environment_with_api_key(env_file=env_file, environ={"PATH": "/bin"})
            preserved = environment_with_api_key(
                env_file=env_file,
                environ={"AIHUB_APIKEY": "from-process"},
            )
        self.assertEqual(loaded["AIHUB_APIKEY"], "from-file")
        self.assertEqual(preserved["AIHUB_APIKEY"], "from-process")

    def test_download_runs_in_isolated_directory_and_requires_completion_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_cli = root / "aihubshell"
            fake_cli.write_text(
                "#!/bin/sh\n"
                "test \"$AIHUB_APIKEY\" = test-only-key || exit 7\n"
                "test \"$1 $2 $3 $4\" = '-mode d -datasetkey 123' || exit 8\n"
                "printf '병합이 완료 되었습니다.\\n'\n",
                encoding="utf-8",
            )
            fake_cli.chmod(fake_cli.stat().st_mode | stat.S_IXUSR)
            output = root / "raw" / "123"
            result = download_dataset(
                "123",
                output,
                cli=str(fake_cli),
                environ={"AIHUB_APIKEY": "test-only-key", "PATH": os.environ["PATH"]},
            )
        self.assertEqual(result.dataset_key, "123")
        self.assertEqual(result.output_dir, output.resolve())

    def test_download_rejects_zero_exit_without_completion_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_cli = root / "aihubshell"
            fake_cli.write_text("#!/bin/sh\nprintf 'Download successful.\\n'\n", encoding="utf-8")
            fake_cli.chmod(fake_cli.stat().st_mode | stat.S_IXUSR)
            with self.assertRaisesRegex(AihubError, "완료 문구"):
                download_dataset(
                    "123",
                    root / "output",
                    cli=str(fake_cli),
                    environ={"AIHUB_APIKEY": "test-only-key", "PATH": os.environ["PATH"]},
                )


if __name__ == "__main__":
    unittest.main()
