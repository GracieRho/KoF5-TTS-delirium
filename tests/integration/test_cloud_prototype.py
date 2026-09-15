from __future__ import annotations

import sys
import unittest
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.cloud_prototype import CloudCredentials, run_synthetic_pipeline  # noqa: E402


class CloudPrototypeTests(unittest.TestCase):
    def test_synthetic_three_provider_flow_and_privacy_flags(self) -> None:
        calls = []

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request)
            if request.url.host == "api.deepgram.com":
                return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                    {"transcript": "우리 제주도 언제 갔었지?"},
                ]}]}})
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"output": [{"type": "message", "content": [
                    {"type": "output_text", "text": "2024년 5월에 제주도 갔었어."},
                ]}]})
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("unexpected provider")

        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            result = run_synthetic_pipeline(
                client, b"RIFF" + b"\0" * 64, "2024년 5월 제주도 여행",
                CloudCredentials("deepgram-test", "openai-test", "eleven-test", "voice-test", True),
            )
        self.assertEqual(result, (
            "우리 제주도 언제 갔었지?", "2024년 5월에 제주도 갔었어.", b"synthetic-mp3",
        ))
        self.assertEqual(len(calls), 3)
        self.assertIn("mip_opt_out=true", str(calls[0].url))
        self.assertIn("language=ko", str(calls[0].url))
        self.assertIn(b'"store":false', calls[1].content)
        self.assertEqual(calls[2].url.path, "/v1/text-to-speech/voice-test")

    def test_missing_consent_and_invalid_audio_never_reach_providers(self) -> None:
        with self.assertRaises(ValueError):
            CloudCredentials("d", "o", "e", "v", False)
        def unexpected(request: httpx.Request) -> httpx.Response:
            raise AssertionError("invalid input must not call a provider")
        with httpx.Client(transport=httpx.MockTransport(unexpected)) as client:
            with self.assertRaises(ValueError):
                run_synthetic_pipeline(
                    client, b"not wav", "known fact", CloudCredentials("d", "o", "e", "v", True),
                )

    def test_empty_transcript_stops_before_llm_or_tts(self) -> None:
        calls = []
        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request.url.host)
            return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                {"transcript": ""},
            ]}]}})
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            with self.assertRaisesRegex(ValueError, "empty speech"):
                run_synthetic_pipeline(
                    client, b"RIFF" + b"\0" * 64, "known fact",
                    CloudCredentials("d", "o", "e", "v", True),
                )
        self.assertEqual(calls, ["api.deepgram.com"])


if __name__ == "__main__":
    unittest.main()
