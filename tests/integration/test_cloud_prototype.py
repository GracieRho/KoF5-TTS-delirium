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

from kof5_tts.cloud_prototype import (  # noqa: E402
    CloudCredentials, delete_test_voice, enroll_test_voice, find_test_voice,
    run_synthetic_pipeline, run_synthetic_text_pipeline,
)
from tests.synthetic_wav import SYNTHETIC_WAV, make_synthetic_wav  # noqa: E402

TEST_VOICE_NAME = "KoF5 internal self-voice test " + "a" * 32


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

    def test_own_voice_cli_requires_explicit_upload_and_consent_before_file_read(self) -> None:
        environment = os.environ.copy()
        environment.pop("VOICE_OWNER_CONSENT_RECORD_ID", None)
        command = [sys.executable, str(ROOT / "scripts" / "demo_voice_enrollment.py"),
                   "enroll", "/nonexistent/one.wav", "/nonexistent/two.wav", "/nonexistent/three.wav"]
        no_flags = subprocess.run(command, env=environment, capture_output=True, text=True,
                                  check=False)
        self.assertEqual(no_flags.returncode, 2)
        self.assertIn("--own-voice", no_flags.stderr)
        no_consent = subprocess.run(command + ["--own-voice", "--upload"], env=environment,
                                    capture_output=True, text=True, check=False)
        self.assertEqual(no_consent.returncode, 2)
        self.assertIn("동의 기록", no_consent.stderr)

    def test_synthetic_three_provider_flow_and_privacy_flags(self) -> None:
        calls = []
        first_audio_events = []

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
                on_first_audio=lambda: first_audio_events.append(len(calls)),
            )
        self.assertEqual(result, (
            "우리 제주도 언제 갔었지?", "2024년 5월에 제주도 갔었어.", b"synthetic-mp3",
        ))
        self.assertEqual(first_audio_events, [3], "first hosted TTS chunk is reported once after STT and LLM")
        self.assertEqual(len(calls), 3)
        self.assertIn("mip_opt_out=true", str(calls[0].url))
        self.assertIn("language=ko", str(calls[0].url))
        self.assertIn(b'"store":false', calls[1].content)
        self.assertEqual(calls[2].url.path, "/v1/text-to-speech/voice-test")

    def test_local_text_path_skips_hosted_stt_and_discards_ambient_speech(self) -> None:
        hosts = []

        def respond(request: httpx.Request) -> httpx.Response:
            hosts.append(request.url.host)
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"status": "completed", "output": [{
                    "type": "message", "content": [{"type": "output_text", "text": "2024년 5월에 같이 갔어."}],
                }]})
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("text path must not call hosted STT")

        credentials = CloudCredentials("d", "o", "e", "v", True)
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            self.assertEqual(run_synthetic_text_pipeline(
                client, "TV 뉴스입니다", "AMBIENT", "2024년 5월 제주도 여행", credentials,
            ), (None, None))
            with self.assertRaises(ValueError):
                run_synthetic_text_pipeline(client, " " * 3, "DIRECTED", "known fact", credentials)
            self.assertEqual(run_synthetic_text_pipeline(
                client, "우리 제주도 언제 갔었지?", "DIRECTED", "2024년 5월 제주도 여행", credentials,
            ), ("2024년 5월에 같이 갔어.", b"synthetic-mp3"))
        self.assertEqual(hosts, ["api.openai.com", "api.elevenlabs.io"])

    def test_unrelated_family_and_hospital_questions_do_not_reach_llm(self) -> None:
        hosts = []
        def respond(request: httpx.Request) -> httpx.Response:
            hosts.append(request.url.host)
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("unsupported fact must not reach LLM")
        credentials = CloudCredentials("d", "o", "e", "v", True)
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            for question in ("CT 검사 결과 어때?", "수민이는 어디 있어?", "2024년 수민이는 어디 있어?"):
                reply, audio = run_synthetic_text_pipeline(
                    client, question, "DIRECTED", "2024년 5월 제주도 여행", credentials,
                )
                self.assertIn("확인된 정보가 없어서", reply)
                self.assertEqual(audio, b"synthetic-mp3")
            reply, audio = run_synthetic_text_pipeline(
                client, "우리 여행 이야기해줘", "DIRECTED", "", credentials,
            )
            self.assertIn("확인된 정보가 없어서", reply)
            self.assertEqual(audio, b"synthetic-mp3")
        self.assertEqual(hosts, ["api.elevenlabs.io"] * 4)

    def test_semantic_family_match_can_answer_without_literal_overlap(self) -> None:
        hosts = []
        def respond(request: httpx.Request) -> httpx.Response:
            hosts.append(request.url.host)
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"status": "completed", "output": [{
                    "type": "message", "content": [{"type": "output_text",
                    "text": "수민은 회사에 다니고 있어."}],
                }]})
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("unexpected provider")

        question = "수민아 우리 딸 요즘 직장은 뭐야?"
        fact = "딸 수민은 회사에 다닌다."
        credentials = CloudCredentials("d", "o", "e", "v", True)
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            unknown, _ = run_synthetic_text_pipeline(
                client, question, "DIRECTED", fact, credentials,
            )
            self.assertIn("확인된 정보가 없어서", unknown)
            answer, audio = run_synthetic_text_pipeline(
                client, question, "DIRECTED", fact, credentials, semantic_match=True,
            )
            self.assertEqual((answer, audio), ("수민은 회사에 다니고 있어.", b"synthetic-mp3"))
            hospital, _ = run_synthetic_text_pipeline(
                client, "수민아 CT 검사 결과 어때?", "DIRECTED", fact, credentials,
                semantic_match=True,
            )
            self.assertIn("의료", hospital)
        self.assertEqual(hosts, ["api.elevenlabs.io", "api.openai.com",
                                 "api.elevenlabs.io", "api.elevenlabs.io"])

    def test_approved_hospital_fact_uses_exact_text_without_family_or_llm(self) -> None:
        hosts = []

        def respond(request: httpx.Request) -> httpx.Response:
            hosts.append(request.url.host)
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("approved hospital wording must not reach an LLM")

        credentials = CloudCredentials("d", "o", "e", "v", True)
        approved = "CT 검사는 오늘 14시입니다."
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            self.assertEqual(run_synthetic_text_pipeline(
                client, "수민아 CT 검사는 몇 시야?", "DIRECTED", approved, credentials,
                namespace="hospital_context",
            ), (approved, b"synthetic-mp3"))
            for question, reserved in (
                ("수민아 CT 검사 예약은 몇 시야?", "CT 검사 예약은 오늘 오후 4시입니다."),
                ("수민아 면회 예약은 몇 시야?", "수민이 면회 예약은 오늘 오후 4시입니다."),
            ):
                self.assertEqual(run_synthetic_text_pipeline(
                    client, question, "DIRECTED", reserved, credentials,
                    namespace="hospital_context",
                ), (reserved, b"synthetic-mp3"))
            family_question, _ = run_synthetic_text_pipeline(
                client, "우리 제주도 언제 갔었어?", "DIRECTED", approved, credentials,
                namespace="hospital_context",
            )
            self.assertIn("확인된 정보가 없어서", family_question)
            unsafe, _ = run_synthetic_text_pipeline(
                client, "수민아 CT 검사는 몇 시야?", "DIRECTED", "약을 복용하세요.", credentials,
                namespace="hospital_context",
            )
            self.assertIn("확인된 정보가 없어서", unsafe)
            result_question, _ = run_synthetic_text_pipeline(
                client, "수민아 CT 검사 결과 어때?", "DIRECTED", approved, credentials,
                namespace="hospital_context",
            )
            self.assertIn("확인된 정보가 없어서", result_question)
        self.assertEqual(hosts, ["api.elevenlabs.io"] * 6)

    def test_llm_extra_hospital_or_date_claim_does_not_reach_tts(self) -> None:
        for invented in ("내일 CT 검사를 받으러 가.", "2027년 5월에 제주도 갔었어.",
                         "수민이는 내일 와."):
            with self.subTest(invented=invented):
                hosts = []
                def respond(request: httpx.Request) -> httpx.Response:
                    hosts.append(request.url.host)
                    if request.url.host == "api.openai.com":
                        return httpx.Response(200, json={"status": "completed", "output": [{
                            "type": "message", "content": [{"type": "output_text", "text": invented}],
                        }]})
                    raise AssertionError("unverified fact must not reach TTS")
                with httpx.Client(transport=httpx.MockTransport(respond)) as client:
                    with self.assertRaisesRegex(ValueError, "unverified fact claim"):
                        run_synthetic_text_pipeline(
                            client, "우리 제주도 언제 갔었지?", "DIRECTED",
                            "2024년 5월 제주도 여행", CloudCredentials("d", "o", "e", "v", True),
                        )
                self.assertEqual(hosts, ["api.openai.com"])

    def test_historical_family_fact_cannot_become_current_location(self) -> None:
        hosts = []
        def respond(request: httpx.Request) -> httpx.Response:
            hosts.append(request.url.host)
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"status": "completed", "output": [{
                    "type": "message", "content": [{"type": "output_text", "text": "수민이는 제주도에 있어."}],
                }]})
            raise AssertionError("unverified whereabouts must not reach TTS")
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            with self.assertRaisesRegex(ValueError, "unverified current location"):
                run_synthetic_text_pipeline(
                    client, "우리 제주도 언제 갔었지?", "DIRECTED",
                    "2024년 5월에 수민과 제주도 여행을 갔다.",
                    CloudCredentials("d", "o", "e", "v", True),
                )
        self.assertEqual(hosts, ["api.openai.com"])

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
                run_synthetic_pipeline(client, SYNTHETIC_WAV, "2024년 5월 제주도 여행", credentials)
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

    def test_medical_advice_from_llm_never_reaches_tts_in_text_or_audio_path(self) -> None:
        credentials = CloudCredentials("d", "o", "e", "v", True)
        for unsafe in ("이 약은 안전해. 바로 먹어도 돼.", "독감 진단이 확실해.",
                       "처방한 약은 그냥 끊어."):
            for audio_path in (False, True):
                with self.subTest(unsafe=unsafe, audio_path=audio_path):
                    hosts = []
                    def respond(request: httpx.Request) -> httpx.Response:
                        hosts.append(request.url.host)
                        if request.url.host == "api.deepgram.com":
                            return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                                {"transcript": "우리 제주도 언제 갔었지?"},
                            ]}]}})
                        if request.url.host == "api.openai.com":
                            return httpx.Response(200, json={"status": "completed", "output": [{
                                "type": "message", "content": [{"type": "output_text", "text": unsafe}],
                            }]})
                        raise AssertionError("medical advice must never reach TTS")
                    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
                        with self.assertRaisesRegex(ValueError, "hard safety rule"):
                            if audio_path:
                                run_synthetic_pipeline(client, SYNTHETIC_WAV,
                                                       "2024년 5월 제주도 여행", credentials)
                            else:
                                run_synthetic_text_pipeline(
                                    client, "우리 제주도 언제 갔었지?", "DIRECTED",
                                    "2024년 5월 제주도 여행", credentials,
                                )
                    self.assertEqual(hosts, (["api.deepgram.com"] if audio_path else [])
                                     + ["api.openai.com"])

    def test_own_voice_enrollment_and_task_owned_delete_contract(self) -> None:
        calls = []

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request)
            if request.method == "POST":
                return httpx.Response(200, json={"voice_id": "internal-voice-123",
                                                 "requires_verification": True})
            if request.method == "DELETE":
                return httpx.Response(200, json={"status": "ok"})
            self.assertEqual(request.url.params.get_list("voice_ids"), ["internal-voice-123"])
            return httpx.Response(200, json={"voices": [], "has_more": False})

        samples = [make_synthetic_wav(20) for _ in range(3)]
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            enrolled = enroll_test_voice(client, samples, "test-key", True, TEST_VOICE_NAME)
            delete_test_voice(client, enrolled.voice_id, "test-key")
        self.assertEqual((enrolled.voice_id, enrolled.requires_verification),
                         ("internal-voice-123", True))
        self.assertEqual((calls[0].method, calls[0].url.path), ("POST", "/v1/voices/add"))
        self.assertEqual(calls[0].content.count(b'name="files[]"'), 3)
        self.assertIn(TEST_VOICE_NAME.encode(), calls[0].content)
        self.assertEqual((calls[1].method, calls[1].url.path),
                         ("DELETE", "/v1/voices/internal-voice-123"))
        self.assertEqual((calls[2].method, calls[2].url.path),
                         ("GET", "/v2/voices"))

    def test_delete_response_does_not_prove_voice_absence(self) -> None:
        for lookup in (
            httpx.Response(200, json={"voices": [{"voice_id": "own-id"}], "has_more": False}),
            httpx.Response(503, json={"detail": "lookup unavailable"}),
        ):
            with self.subTest(status=lookup.status_code):
                def respond(request: httpx.Request) -> httpx.Response:
                    if request.method == "DELETE":
                        return httpx.Response(200, json={"status": "ok"})
                    self.assertEqual(request.url.params.get_list("voice_ids"), ["own-id"])
                    return lookup
                with httpx.Client(transport=httpx.MockTransport(respond)) as client:
                    with self.assertRaises((ValueError, httpx.HTTPStatusError)):
                        delete_test_voice(client, "own-id", "test-key")

    def test_voice_enrollment_rejects_unconsented_short_or_invalid_response(self) -> None:
        samples = [make_synthetic_wav(20) for _ in range(3)]
        def unexpected(request: httpx.Request) -> httpx.Response:
            raise AssertionError("invalid enrollment must not upload samples")
        with httpx.Client(transport=httpx.MockTransport(unexpected)) as client:
            with self.assertRaises(ValueError):
                enroll_test_voice(client, samples, "test-key", False, TEST_VOICE_NAME)
            with self.assertRaises(ValueError):
                enroll_test_voice(client, [SYNTHETIC_WAV] * 3, "test-key", True,
                                  TEST_VOICE_NAME)
            with self.assertRaises(ValueError):
                delete_test_voice(client, "https://other", "test-key")

        def malformed(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json={"voice_id": 123, "requires_verification": False})
        with httpx.Client(transport=httpx.MockTransport(malformed)) as client:
            with self.assertRaisesRegex(ValueError, "no valid ID"):
                enroll_test_voice(client, samples, "test-key", True, TEST_VOICE_NAME)

    def test_missing_verification_state_preserves_created_id_and_recovery_name(self) -> None:
        samples = [make_synthetic_wav(20) for _ in range(3)]
        def respond(request: httpx.Request) -> httpx.Response:
            if request.method == "POST":
                return httpx.Response(200, json={"voice_id": "created-id"})
            self.assertEqual(request.url.path, "/v2/voices")
            self.assertEqual(request.url.params.get("search"), TEST_VOICE_NAME)
            return httpx.Response(200, json={"voices": [
                {"name": TEST_VOICE_NAME, "voice_id": "created-id"},
                {"name": "another voice", "voice_id": "other-id"},
            ], "has_more": False})
        with httpx.Client(transport=httpx.MockTransport(respond)) as client:
            created = enroll_test_voice(client, samples, "test-key", True, TEST_VOICE_NAME)
            recovered = find_test_voice(client, TEST_VOICE_NAME, "test-key")
        self.assertEqual((created.voice_id, created.requires_verification), ("created-id", None))
        self.assertEqual(recovered, "created-id")

    def test_pending_voice_absence_needs_complete_provider_list(self) -> None:
        with httpx.Client(transport=httpx.MockTransport(
            lambda request: httpx.Response(200, json={"voices": []})
        )) as client:
            with self.assertRaisesRegex(ValueError, "inconclusive"):
                find_test_voice(client, TEST_VOICE_NAME, "test-key")


if __name__ == "__main__":
    unittest.main()
