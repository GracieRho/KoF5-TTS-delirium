from __future__ import annotations

import sys
import unittest
import os
import subprocess
from io import BytesIO
from pathlib import Path
import wave

import httpx

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.cloud_prototype import CloudCredentials, run_synthetic_pipeline  # noqa: E402
from tests.synthetic_wav import SYNTHETIC_WAV  # noqa: E402


class CloudPrototypeTests(unittest.TestCase):
    def test_live_cli_requires_consent_before_file_or_network(self) -> None:
        environment = os.environ.copy()
        environment.pop("VOICE_OWNER_CONSENT_RECORD_ID", None)
        run = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "demo_cloud_pipeline.py"),
             "/nonexistent/synthetic.wav", "--synthetic-only"],
            env=environment, capture_output=True, text=True, check=False,
        )
        self.assertEqual(run.returncode, 2)
        self.assertIn("VOICE_OWNER_CONSENT_RECORD_ID", run.stderr)

    def test_synthetic_three_provider_flow_and_privacy_flags(self) -> None:
        calls = []

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request)
            if request.url.host == "api.deepgram.com":
                return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                    {"transcript": "우리 제주도 언제 갔었지?"},
                ]}]}})
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"status": "completed", "output": [{"type": "message", "content": [
                    {"type": "output_text", "text": "2024년 5월에 제주도 갔었어."},
                ]}]})
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("unexpected provider")

        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            result = run_synthetic_pipeline(
                client, SYNTHETIC_WAV, "2024년 5월 제주도 여행",
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

    def test_truncated_and_long_wav_never_reach_stt(self) -> None:
        def unexpected(request: httpx.Request) -> httpx.Response:
            raise AssertionError("invalid WAV must not call a provider")
        long_audio = BytesIO()
        with wave.open(long_audio, "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(16_000)
            audio.writeframes(b"\0" * (16_000 * 2 * 31))
        with httpx.Client(transport=httpx.MockTransport(unexpected)) as client:
            bad_chunk = b"RIFF" + (100).to_bytes(4, "little") + b"WAVEJUNK" + (0xffffffff).to_bytes(4, "little")
            for wav in (SYNTHETIC_WAV[:-100], long_audio.getvalue(), bad_chunk):
                with self.subTest(size=len(wav)), self.assertRaises(ValueError):
                    run_synthetic_pipeline(
                        client, wav, "known fact", CloudCredentials("d", "o", "e", "v", True),
                    )

    def test_oversized_tts_stops_reading_provider_stream(self) -> None:
        chunks_sent = []

        class OversizedAudio(httpx.SyncByteStream):
            def __iter__(self):
                for index in range(5):
                    chunks_sent.append(index)
                    yield b"x" * 1_000_000

        def respond(request: httpx.Request) -> httpx.Response:
            if request.url.host == "api.deepgram.com":
                return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                    {"transcript": "수민아?"},
                ]}]}})
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, stream=OversizedAudio())
            raise AssertionError("first turn must skip LLM")

        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            with self.assertRaisesRegex(ValueError, "oversized audio"):
                run_synthetic_pipeline(client, SYNTHETIC_WAV, "known fact",
                                       CloudCredentials("d", "o", "e", "v", True))
        self.assertEqual(chunks_sent, [0, 1, 2])

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
                    client, SYNTHETIC_WAV, "known fact",
                    CloudCredentials("d", "o", "e", "v", True),
                )
        self.assertEqual(calls, ["api.deepgram.com"])

    def test_dissent_and_risk_never_call_llm(self) -> None:
        for transcript, expected_hosts, expected_reply in (
            ("그만해.", ["api.deepgram.com"], None),
            ("숨이 너무 차.", ["api.deepgram.com", "api.elevenlabs.io"], "기존 호출 버튼"),
            ("지금 몇 시야?", ["api.deepgram.com", "api.elevenlabs.io"], "지금은"),
            ("CT 검사는 몇 시야?", ["api.deepgram.com", "api.elevenlabs.io"], "확인된 정보가 없어서"),
            ("수민이는 몇 시에 와?", ["api.deepgram.com", "api.elevenlabs.io"], "확인된 정보가 없어서"),
            ("간호사가 지금 몇 시에 검사한다고 했지?", ["api.deepgram.com", "api.elevenlabs.io"], "확인된 정보가 없어서"),
            ("무슨 약을 먹어야 해?", ["api.deepgram.com", "api.elevenlabs.io"], "의료진에게 확인"),
        ):
            with self.subTest(transcript=transcript):
                hosts = []
                def respond(request: httpx.Request) -> httpx.Response:
                    hosts.append(request.url.host)
                    if request.url.host == "api.deepgram.com":
                        return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                            {"transcript": transcript},
                        ]}]}})
                    if request.url.host == "api.elevenlabs.io":
                        return httpx.Response(200, content=b"synthetic-mp3")
                    raise AssertionError("safety route must not call LLM")
                with httpx.Client(transport=httpx.MockTransport(respond)) as client:
                    result = run_synthetic_pipeline(
                        client, SYNTHETIC_WAV, "known fact",
                        CloudCredentials("d", "o", "e", "v", True),
                    )
                self.assertEqual(hosts, expected_hosts)
                if expected_reply is None:
                    self.assertEqual(result[1:], (None, None))
                else:
                    self.assertIn(expected_reply, result[1])

    def test_directed_name_activation_reaches_tts_without_llm(self) -> None:
        hosts = []

        def respond(request: httpx.Request) -> httpx.Response:
            hosts.append(request.url.host)
            if request.url.host == "api.deepgram.com":
                return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                    {"transcript": "수민아?"},
                ]}]}})
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("directed name activation must not call LLM")

        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            result = run_synthetic_pipeline(
                client, SYNTHETIC_WAV, "2024년 5월 제주도 여행",
                CloudCredentials("d", "o", "e", "v", True),
            )
        self.assertEqual(result, ("수민아?", "응, 왜?", b"synthetic-mp3"))
        self.assertEqual(hosts, ["api.deepgram.com", "api.elevenlabs.io"])

    def test_credentials_repr_and_incomplete_llm_response(self) -> None:
        credentials = CloudCredentials("secret-d", "secret-o", "secret-e", "voice-test", True)
        self.assertNotIn("secret-", repr(credentials))
        calls = []
        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request.url.host)
            if request.url.host == "api.deepgram.com":
                return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                    {"transcript": "제주도 언제 갔었지?"},
                ]}]}})
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"status": "incomplete", "output": [{"type": "message", "content": [
                    {"type": "output_text", "text": "잘못된 응답"},
                ]}]})
            raise AssertionError("incomplete answer must never reach TTS")
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            with self.assertRaisesRegex(ValueError, "not complete"):
                run_synthetic_pipeline(client, SYNTHETIC_WAV, "known fact", credentials)
        self.assertEqual(calls, ["api.deepgram.com", "api.openai.com"])

    def test_unsafe_generated_claim_never_reaches_tts(self) -> None:
        calls = []
        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request.url.host)
            if request.url.host == "api.deepgram.com":
                return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                    {"transcript": "우리 제주도 언제 갔었지?"},
                ]}]}})
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"status": "completed", "output": [
                    {"type": "message", "content": [{"type": "output_text",
                                                  "text": "내가 수민이야. 의료진에게 알렸어."}]},
                ]})
            raise AssertionError("unsafe text must never reach voice TTS")
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            with self.assertRaisesRegex(ValueError, "hard safety rule"):
                run_synthetic_pipeline(
                    client, SYNTHETIC_WAV, "2024년 5월 제주도 여행",
                    CloudCredentials("d", "o", "e", "v", True),
                )
        self.assertEqual(calls, ["api.deepgram.com", "api.openai.com"])


if __name__ == "__main__":
    unittest.main()
