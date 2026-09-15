from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import demo_cloud_pipeline  # noqa: E402


class DemoCloudPipelineLatencyTests(unittest.TestCase):
    def test_measures_provider_completion_without_reporting_kpi_or_private_text(self) -> None:
        with TemporaryDirectory() as directory:
            wav = Path(directory) / "synthetic.wav"
            wav.write_bytes(b"synthetic fixture")
            output = StringIO()
            with patch.dict(os.environ, {
                "VOICE_OWNER_CONSENT_RECORD_ID": "consented-self-voice",
                "DEEPGRAM_API_KEY": "secret-deepgram",
                "OPENAI_API_KEY": "secret-openai",
                "ELEVENLABS_API_KEY": "secret-eleven",
                "ELEVENLABS_VOICE_ID": "test-voice",
            }), patch.object(demo_cloud_pipeline, "perf_counter", side_effect=[10, 12.25]), \
                    patch.object(demo_cloud_pipeline.httpx, "Client", return_value=MagicMock()), \
                    patch.object(demo_cloud_pipeline, "run_synthetic_pipeline",
                                 return_value=("private transcript", None, None)), redirect_stdout(output):
                result = demo_cloud_pipeline.main([str(wav), "--synthetic-only"])
            self.assertEqual(result, 0)
            self.assertIn("2.25초", output.getvalue())
            self.assertIn("CLI 수치만으로 판정하지 않습니다", output.getvalue())
            self.assertNotIn("private transcript", output.getvalue())
            self.assertNotIn("secret-", output.getvalue())

    def test_reports_first_tts_byte_separately_from_provider_completion(self) -> None:
        with TemporaryDirectory() as directory:
            wav = Path(directory) / "synthetic.wav"
            wav.write_bytes(b"synthetic fixture")
            output = StringIO()
            original_tempfile = demo_cloud_pipeline.tempfile.NamedTemporaryFile

            def synthetic_run(client, material, known_fact, credentials, *, on_first_audio):
                on_first_audio()
                return "private transcript", "private reply", b"synthetic mp3"

            def task_owned_tempfile(**kwargs):
                return original_tempfile(dir=directory, prefix="preview-", suffix=".mp3", delete=False)

            with patch.dict(os.environ, {
                "VOICE_OWNER_CONSENT_RECORD_ID": "consented-self-voice",
                "DEEPGRAM_API_KEY": "secret-deepgram",
                "OPENAI_API_KEY": "secret-openai",
                "ELEVENLABS_API_KEY": "secret-eleven",
                "ELEVENLABS_VOICE_ID": "test-voice",
            }), patch.object(demo_cloud_pipeline, "perf_counter", side_effect=[10, 11.5, 12.25]), \
                    patch.object(demo_cloud_pipeline.httpx, "Client", return_value=MagicMock()), \
                    patch.object(demo_cloud_pipeline, "run_synthetic_pipeline", side_effect=synthetic_run), \
                    patch.object(demo_cloud_pipeline.tempfile, "NamedTemporaryFile", side_effect=task_owned_tempfile), \
                    redirect_stdout(output):
                result = demo_cloud_pipeline.main([str(wav), "--synthetic-only"])
            self.assertEqual(result, 0)
            self.assertIn("첫 TTS 바이트 수신까지: 1.50초", output.getvalue())
            self.assertIn("공급업체 응답 완료까지: 2.25초", output.getvalue())
            self.assertIn("CLI 수치만으로 판정하지 않습니다", output.getvalue())
            self.assertNotIn("private transcript", output.getvalue())
            self.assertNotIn("private reply", output.getvalue())

    def test_provider_failure_hides_exception_details(self) -> None:
        with TemporaryDirectory() as directory:
            wav = Path(directory) / "synthetic.wav"
            wav.write_bytes(b"synthetic fixture")
            error = StringIO()
            with patch.dict(os.environ, {
                "VOICE_OWNER_CONSENT_RECORD_ID": "consented-self-voice",
                "DEEPGRAM_API_KEY": "secret-deepgram",
                "OPENAI_API_KEY": "secret-openai",
                "ELEVENLABS_API_KEY": "secret-eleven",
                "ELEVENLABS_VOICE_ID": "test-voice",
            }), patch.object(demo_cloud_pipeline.httpx, "Client", return_value=MagicMock()), \
                    patch.object(demo_cloud_pipeline, "run_synthetic_pipeline",
                                 side_effect=ValueError("secret-openai private transcript")), redirect_stderr(error):
                result = demo_cloud_pipeline.main([str(wav), "--synthetic-only"])
            self.assertEqual(result, 1)
            self.assertIn("지연 KPI를 판정할 수 없습니다", error.getvalue())
            self.assertNotIn("secret-", error.getvalue())
            self.assertNotIn("private transcript", error.getvalue())


if __name__ == "__main__":
    unittest.main()
