"""Local clone ownership must survive uncertain provider results and concurrency."""

from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import httpx

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import demo_voice_enrollment as cli  # noqa: E402
from kof5_tts.cloud_prototype import EnrolledVoice  # noqa: E402
from tests.synthetic_wav import make_synthetic_wav  # noqa: E402


class TestVoiceEnrollmentCli(unittest.TestCase):
    def run_cli(self, args: list[str]) -> int:
        with redirect_stderr(StringIO()), redirect_stdout(StringIO()):
            try:
                return cli.main(args)
            except SystemExit as exit_status:
                return exit_status.code

    def samples(self, directory: Path) -> list[str]:
        paths = [directory / f"own-{index}.wav" for index in range(3)]
        wav = make_synthetic_wav(20)
        for path in paths:
            path.write_bytes(wav)
        return [str(path) for path in paths]

    def test_pending_precedes_post_blocks_retry_and_can_reconcile_delete(self) -> None:
        with TemporaryDirectory() as directory, patch.dict(os.environ, {
            "ELEVENLABS_API_KEY": "test-key", "VOICE_OWNER_CONSENT_RECORD_ID": "own-consent",
        }):
            root = Path(directory)
            args = ["enroll", *self.samples(root), "--own-voice", "--upload"]
            manifest = root / "internal-test-voice.json"

            with patch.object(cli, "MANIFEST", manifest), cli.ownership_lock():
                code = ("import sys; from pathlib import Path; "
                        f"sys.path.insert(0, {str(ROOT / 'scripts')!r}); "
                        "import demo_voice_enrollment as cli; "
                        "cli.MANIFEST=Path(sys.argv[1]); raise SystemExit(cli.main(sys.argv[2:]))")
                competing = subprocess.run([sys.executable, "-c", code, str(manifest), *args],
                                           env=os.environ.copy(), capture_output=True, text=True,
                                           check=False)
                self.assertEqual(competing.returncode, 2)
                self.assertIn("operation is in progress", competing.stderr)
                self.assertFalse(manifest.exists(), "competing process must not create a clone")

            def uncertain(*_):
                self.assertEqual(json.loads(manifest.read_text())["status"], "pending")
                raise httpx.ReadTimeout("unknown clone result")

            with patch.object(cli, "MANIFEST", manifest), patch.object(
                cli, "enroll_test_voice", side_effect=uncertain
            ) as provider:
                self.assertEqual(self.run_cli(args), 2)
                self.assertEqual(self.run_cli(args), 2)
                self.assertEqual(provider.call_count, 1, "pending must prevent a second POST")
                with cli.ownership_lock():
                    with self.assertRaises(ValueError):
                        with cli.ownership_lock():
                            pass

                with patch.object(cli, "find_test_voice", return_value="recovered-id") as search, \
                        patch.object(cli, "delete_test_voice") as delete:
                    self.assertEqual(self.run_cli(["reconcile"]), 0)
                    self.assertEqual(json.loads(manifest.read_text())["voice_id"], "recovered-id")
                    self.assertEqual(self.run_cli(["delete"]), 2)
                    self.assertEqual(self.run_cli(["delete", "--confirm-delete"]), 0)
                    search.assert_called_once()
                    delete.assert_called_once()
                    self.assertFalse(manifest.exists())

    def test_known_id_is_saved_even_when_verification_state_is_unknown(self) -> None:
        with TemporaryDirectory() as directory, patch.dict(os.environ, {
            "ELEVENLABS_API_KEY": "test-key", "VOICE_OWNER_CONSENT_RECORD_ID": "own-consent",
        }):
            root = Path(directory)
            manifest = root / "internal-test-voice.json"
            with patch.object(cli, "MANIFEST", manifest), patch.object(
                cli, "enroll_test_voice", return_value=EnrolledVoice("known-id", None)
            ):
                self.assertEqual(self.run_cli(["enroll", *self.samples(root),
                                               "--own-voice", "--upload"]), 0)
                self.assertEqual(json.loads(manifest.read_text())["voice_id"], "known-id")
                self.assertIsNone(json.loads(manifest.read_text())["requires_verification"])

    def test_delete_pending_survives_stale_lookup_then_finishes_without_second_delete(self) -> None:
        with TemporaryDirectory() as directory, patch.dict(os.environ, {
            "ELEVENLABS_API_KEY": "test-key",
        }):
            manifest = Path(directory) / "internal-test-voice.json"
            manifest.write_text(json.dumps({
                "status": "created", "name": "KoF5 internal self-voice test " + "a" * 32,
                "voice_id": "own-id",
            }))
            calls = []
            def respond(request: httpx.Request) -> httpx.Response:
                calls.append(request.method)
                if request.method == "DELETE":
                    return httpx.Response(200, json={"status": "ok"})
                self.assertEqual(request.url.params.get_list("voice_ids"), ["own-id"])
                return httpx.Response(200, json={
                    "voices": [{"voice_id": "own-id"}] if calls.count("GET") == 1 else [],
                    "has_more": False,
                })
            real_client = httpx.Client
            with patch.object(cli, "MANIFEST", manifest), patch.object(
                cli.httpx, "Client", side_effect=lambda **_: real_client(
                    transport=httpx.MockTransport(respond)
                ),
            ):
                self.assertEqual(self.run_cli(["delete", "--confirm-delete"]), 2)
                pending = json.loads(manifest.read_text())
                self.assertEqual((pending["status"], pending["voice_id"]),
                                 ("deletion_pending", "own-id"))
                self.assertEqual(self.run_cli(["delete", "--confirm-delete"]), 0)
                self.assertFalse(manifest.exists())
            self.assertEqual(calls, ["DELETE", "GET", "GET"])

    def test_corrupt_ownership_record_never_deletes_provider_voice(self) -> None:
        with TemporaryDirectory() as directory, patch.dict(os.environ, {
            "ELEVENLABS_API_KEY": "test-key",
        }):
            manifest = Path(directory) / "internal-test-voice.json"
            manifest.write_text(json.dumps({"name": "unowned voice", "voice_id": "known-id"}))
            with patch.object(cli, "MANIFEST", manifest), patch.object(cli, "delete_test_voice") as delete:
                self.assertEqual(self.run_cli(["delete", "--confirm-delete"]), 2)
                delete.assert_not_called()
                self.assertTrue(manifest.exists())


if __name__ == "__main__":
    unittest.main()
