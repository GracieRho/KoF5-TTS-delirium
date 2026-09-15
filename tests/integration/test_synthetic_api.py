from __future__ import annotations

import json
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.api import SYNTHETIC_DB_PATIENT, app  # noqa: E402
from tests.synthetic_wav import SYNTHETIC_WAV  # noqa: E402


class SyntheticApiTests(unittest.TestCase):
    def setUp(self) -> None:
        app.state.sessions.clear()
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()

    def test_synthetic_first_flow_and_untrusted_requests(self) -> None:
        root = "/patients/synthetic_patient/conversation"
        self.assertEqual(self.client.get("/health").json(), {"status": "synthetic_demo_only"})
        demo = self.client.get("/demo")
        self.assertEqual(demo.status_code, 200)
        self.assertIn("합성 데이터 전용", demo.text)
        hospital = self.client.get("/demo/hospital")
        self.assertEqual(hospital.status_code, 200)
        self.assertIn("실제 환자 정보를 입력하거나 환자 목소리를 녹음하지 마세요", hospital.text)
        guardian = self.client.get("/demo/guardian")
        self.assertEqual(guardian.status_code, 200)
        self.assertIn("실제 가족 정보나 음성을 입력하지 마세요", guardian.text)
        self.assertEqual(
            self.client.post("/patients/real_patient/conversation/start", json={
                "transcript": "수민아?", "label": "DIRECTED",
            }).status_code,
            404,
        )
        self.assertEqual(self.client.post(f"{root}/turn", json={
            "transcript": "오늘이 며칠이야?", "label": "UNCERTAIN",
        }).status_code, 404)
        self.assertEqual(self.client.post(f"{root}/start", json={
            "transcript": "수민아?", "label": "INVALID",
        }).status_code, 422)

        first = self.client.post(f"{root}/start", json={
            "transcript": "수민아?", "label": "DIRECTED",
        }).json()
        self.assertEqual((first["event"], first["text"]), ("turn", "응, 왜?"))
        self.assertEqual(self.client.post(f"{root}/start", json={
            "transcript": "수민아?", "label": "DIRECTED",
        }).status_code, 409)
        ambient = self.client.post(f"{root}/turn", json={
            "transcript": "TV 뉴스입니다", "label": "AMBIENT",
        }).json()
        self.assertEqual((ambient["event"], ambient["text"]), ("discarded", None))
        date = self.client.post(f"{root}/turn", json={
            "transcript": "오늘이 며칠이야?", "label": "UNCERTAIN",
        }).json()
        self.assertTrue(date["text"].startswith("오늘은 "))
        time_answer = self.client.post(f"{root}/turn", json={
            "transcript": "수민아 지금 몇 시야?", "label": "UNCERTAIN",
        }).json()
        self.assertTrue(time_answer["text"].startswith("지금은 "))
        schedule_time = self.client.post(f"{root}/turn", json={
            "transcript": "CT 검사는 몇 시야?", "label": "UNCERTAIN",
        }).json()
        self.assertIn("확인된 정보가 없어서", schedule_time["text"])
        mixed_schedule = self.client.post(f"{root}/turn", json={
            "transcript": "지금 몇 시에 검사하러 가야 해?", "label": "UNCERTAIN",
        }).json()
        self.assertIn("확인된 정보가 없어서", mixed_schedule["text"])
        medical = self.client.post(f"{root}/turn", json={
            "transcript": "무슨 약을 먹어야 해?", "label": "UNCERTAIN",
        }).json()
        self.assertIn("의료진에게 확인", medical["text"])
        identity = self.client.post(f"{root}/turn", json={
            "transcript": "너 진짜 수민이야?", "label": "UNCERTAIN",
        }).json()
        self.assertIn("AI 음성 대화 도우미", identity["text"])
        memory = self.client.post(f"{root}/turn", json={
            "transcript": "제주도 언제 갔었지?", "label": "UNCERTAIN",
        }).json()
        self.assertIn("2024년 5월", memory["text"])
        dissent = self.client.post(f"{root}/turn", json={
            "transcript": "그만해.", "label": "UNCERTAIN",
        }).json()
        self.assertEqual((dissent["event"], dissent["text"]), ("patient_dissent", None))
        self.assertEqual(self.client.post(f"{root}/start", json={
            "transcript": "수민아?", "label": "DIRECTED",
        }).status_code, 409)
        self.assertEqual(self.client.post(f"{root}/end").json()["state"], "IDLE")

    def test_guardian_portal_exposes_only_a_dedicated_public_supabase_config(self) -> None:
        portal = self.client.get("/guardian")
        self.assertEqual(portal.status_code, 200)
        self.assertIn("보호자 로그인", portal.text)
        hospital = self.client.get("/hospital")
        self.assertEqual(hospital.status_code, 200)
        self.assertIn("병원 직원 로그인", hospital.text)
        env = {
            "KOF5_SUPABASE_URL": "", "KOF5_SUPABASE_PUBLISHABLE_KEY": "",
            "KOF5_SUPABASE_PROJECT_REF": "", "VERCEL": "",
        }
        with patch.dict(os.environ, env):
            self.assertEqual(self.client.get("/guardian/config").status_code, 503)
            self.assertEqual(self.client.get("/portal/config").status_code, 503)
        with patch.dict(os.environ, {**env, "KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
                                          "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
                                          "SUPABASE_SECRET_KEY": "sb_secret_never_return"}):
            config = self.client.get("/guardian/config")
            self.assertEqual(config.json(), {
                "url": "http://127.0.0.1:54341", "publishable_key": "sb_publishable_local",
            })
            self.assertEqual(self.client.get("/portal/config").json(), config.json())
            self.assertNotIn("sb_secret_never_return", config.text)
        with patch.dict(os.environ, {**env, "VERCEL": "1", "KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
                                          "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local"}):
            self.assertEqual(self.client.get("/guardian/config").status_code, 503)
        ref = "abcdefghijklmnopqrst"
        with patch.dict(os.environ, {**env, "KOF5_SUPABASE_URL": f"https://{ref}.supabase.co",
                                          "KOF5_SUPABASE_PROJECT_REF": ref,
                                          "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_remote"}):
            self.assertEqual(self.client.get("/guardian/config").json(), {
                "url": f"https://{ref}.supabase.co", "publishable_key": "sb_publishable_remote",
            })
        with patch.dict(os.environ, {**env, "KOF5_SUPABASE_URL": f"https://{ref}.supabase.co",
                                          "KOF5_SUPABASE_PROJECT_REF": "otherproject",
                                          "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_remote"}):
            self.assertEqual(self.client.get("/guardian/config").status_code, 503)
        with patch.dict(os.environ, {**env, "KOF5_SUPABASE_URL": "https://dqjplezbvtjbsunabxbg.supabase.co",
                                          "KOF5_SUPABASE_PROJECT_REF": "dqjplezbvtjbsunabxbg",
                                          "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_shared"}):
            self.assertEqual(self.client.get("/guardian/config").status_code, 503)

    def test_stale_session_expires_before_uncertain_turn(self) -> None:
        root = "/patients/synthetic_patient/conversation"
        self.client.post(f"{root}/start", json={"transcript": "수민아?", "label": "DIRECTED"})
        app.state.sessions["synthetic_patient"].last_activity = datetime.now(timezone.utc) - timedelta(minutes=5)
        response = self.client.post(f"{root}/turn", json={
            "transcript": "TV 뉴스입니다", "label": "UNCERTAIN",
        }).json()
        self.assertEqual((response["event"], response["state"], response["text"]),
                         ("discarded", "IDLE", None))
        restarted = self.client.post(f"{root}/start", json={
            "transcript": "수민아?", "label": "DIRECTED",
        }).json()
        self.assertEqual((restarted["event"], restarted["text"]), ("turn", "응, 왜?"))

    def test_internal_audio_requires_auth_and_valid_synthetic_wav_before_provider(self) -> None:
        path = "/internal/synthetic/audio"
        with patch.dict(os.environ, {"KOF5_INTERNAL_DEMO_TOKEN": ""}):
            self.assertEqual(self.client.post(path, content=SYNTHETIC_WAV).status_code, 503)
        env = {
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
            "DEEPGRAM_API_KEY": "test-deepgram",
            "OPENAI_API_KEY": "test-openai",
            "ELEVENLABS_API_KEY": "test-eleven",
            "ELEVENLABS_VOICE_ID": "test-voice",
        }
        headers = {"X-Internal-Demo-Token": env["KOF5_INTERNAL_DEMO_TOKEN"],
                   "X-Synthetic-Material": "confirmed", "Content-Type": "audio/wav"}
        with patch.dict(os.environ, {**env, "VOICE_OWNER_CONSENT_RECORD_ID": ""}):
            self.assertEqual(self.client.post(path, content=SYNTHETIC_WAV, headers=headers).status_code, 503)
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.run_synthetic_pipeline", return_value=("수민아?", "응, 왜?", b"mp3")
        ) as pipeline:
            self.assertEqual(self.client.post(path, content=SYNTHETIC_WAV).status_code, 401)
            self.assertEqual(self.client.post(path, content=SYNTHETIC_WAV, headers=[
                (b"x-internal-demo-token", b"\xff"),
            ]).status_code, 401)
            self.assertEqual(self.client.post(path, content=SYNTHETIC_WAV,
                                              headers={"X-Internal-Demo-Token": headers["X-Internal-Demo-Token"]}).status_code, 400)
            self.assertEqual(self.client.post(path, content=SYNTHETIC_WAV,
                                              headers={**headers, "Content-Type": "text/plain"}).status_code, 415)
            self.assertEqual(self.client.post(path, content=b"x" * 2_000_001,
                                              headers=headers).status_code, 413)
            self.assertEqual(self.client.post(path, content=b"RIFF" + b"x" * 60,
                                              headers=headers).status_code, 422)
            bad_chunk = b"RIFF" + (100).to_bytes(4, "little") + b"WAVEJUNK" + (0xffffffff).to_bytes(4, "little")
            self.assertEqual(self.client.post(path, content=bad_chunk,
                                              headers=headers).status_code, 422)
            pipeline.assert_not_called()
            result = self.client.post(path, content=SYNTHETIC_WAV, headers=headers)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json(), {
                "transcript": "수민아?", "reply": "응, 왜?", "audio_mp3_base64": "bXAz",
            })
            self.assertEqual(pipeline.call_count, 1)
            pipeline.side_effect = httpx.ConnectError("private provider detail")
            failed = self.client.post(path, content=SYNTHETIC_WAV, headers=headers)
            self.assertEqual(failed.status_code, 502)
            self.assertNotIn("private provider detail", failed.text)

    def test_internal_audio_round_trips_three_mocked_hosted_providers(self) -> None:
        calls = []

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request.url.host)
            if request.url.host == "api.deepgram.com":
                return httpx.Response(200, json={"results": {"channels": [{"alternatives": [
                    {"transcript": "우리 제주도 언제 갔었지?"},
                ]}]}})
            if request.url.host == "api.openai.com":
                return httpx.Response(200, json={"status": "completed", "output": [{
                    "type": "message", "content": [{"type": "output_text", "text": "2024년에 제주도 갔었어."}],
                }]})
            if request.url.host == "api.elevenlabs.io":
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("unexpected provider")

        env = {
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
            "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
            "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice",
        }
        headers = {"X-Internal-Demo-Token": env["KOF5_INTERNAL_DEMO_TOKEN"],
                   "X-Synthetic-Material": "confirmed", "Content-Type": "audio/wav"}
        hosted = httpx.Client(transport=httpx.MockTransport(respond))
        with patch.dict(os.environ, env), patch("kof5_tts.api.httpx.Client", return_value=hosted):
            response = self.client.post("/internal/synthetic/audio", content=SYNTHETIC_WAV,
                                        headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(calls, ["api.deepgram.com", "api.openai.com", "api.elevenlabs.io"])
        self.assertEqual(response.json(), {
            "transcript": "우리 제주도 언제 갔었지?", "reply": "2024년에 제주도 갔었어.",
            "audio_mp3_base64": "c3ludGhldGljLW1wMw==",
        })


    def test_internal_text_requires_trial_auth_and_never_needs_candidate_audio(self) -> None:
        env = {
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
            "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
            "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice",
        }
        path = "/internal/synthetic/text"
        turn = {"transcript": "수민아?", "label": "DIRECTED"}
        headers = {"X-Internal-Demo-Token": env["KOF5_INTERNAL_DEMO_TOKEN"],
                   "X-Synthetic-Material": "confirmed"}
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.run_synthetic_text_pipeline", return_value=("응, 왜?", b"synthetic-mp3")
        ) as pipeline:
            self.assertEqual(self.client.post(path, json=turn).status_code, 401)
            self.assertEqual(self.client.post(path, json=turn, headers={
                "X-Internal-Demo-Token": headers["X-Internal-Demo-Token"],
            }).status_code, 400)
            self.assertEqual(self.client.post(path, content=b"not-json", headers={
                **headers, "Content-Type": "text/plain",
            }).status_code, 415)
            pipeline.assert_not_called()
            result = self.client.post(path, json=turn, headers=headers)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json(), {"transcript": "수민아?", "reply": "응, 왜?",
                                              "audio_mp3_base64": "c3ludGhldGljLW1wMw=="})
            self.assertEqual(pipeline.call_count, 1)

    def test_paired_device_rechecks_memory_before_hosted_turn(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {
            "KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
            "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
            "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
            "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice",
        }
        headers = {
            "X-Internal-Demo-Token": env["KOF5_INTERNAL_DEMO_TOKEN"],
            "X-Synthetic-Material": "confirmed", "Authorization": "Bearer " + "a" * 40,
        }
        calls = []
        assigned = True
        memory_rows = [{"content": "2024년 5월 제주도에 함께 갔었다."}]

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append((request.url.path, request.headers.get("authorization")))
            self.assertEqual(request.headers["apikey"], "sb_publishable_local")
            if request.url.path.endswith("/patient_family_turn_context"):
                self.assertEqual(request.headers["content-profile"], "api")
                self.assertEqual(json.loads(request.read()), {
                    "p_patient_id": SYNTHETIC_DB_PATIENT, "p_term": "제주도 언제 갔었어?",
                })
                return httpx.Response(200, json=[{
                    "authorized": assigned, "facts": memory_rows if assigned else [],
                }])
            raise AssertionError("unexpected Supabase route")

        async_client_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(respond)),
        ), patch(
            "kof5_tts.api.run_synthetic_text_pipeline", return_value=("2024년 5월에 갔었어.", b"mp3")
        ) as pipeline:
            self.assertEqual(self.client.post(path.replace(SYNTHETIC_DB_PATIENT, "real_patient"),
                                              json={"transcript": "제주도 언제 갔었어?", "label": "DIRECTED"},
                                              headers=headers).status_code, 404)
            self.assertEqual(self.client.post(path, json={"transcript": "제주도 언제 갔었어?",
                                                          "label": "DIRECTED"},
                                              headers={k: v for k, v in headers.items()
                                                       if k != "Authorization"}).status_code, 401)
            pipeline.assert_not_called()
            turn = {"transcript": "제주도 언제 갔었어?", "label": "DIRECTED"}
            result = self.client.post(path, json=turn, headers=headers)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "2024년 5월 제주도에 함께 갔었다.")
            self.assertEqual(result.json()["audio_mp3_base64"], "bXAz")
            self.assertEqual(len(calls), 1, "one RPC atomically checks permission and memory")
            memory_rows = []
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "", "each turn gets fresh memory")
            assigned = False
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 403)
            self.assertEqual(pipeline.call_count, 2, "revoked device cannot use stale memory")

    def test_due_hospital_message_voices_only_atomic_approved_original(self) -> None:
        message_id = "00000000-0000-4000-8000-000000000123"
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/message/{message_id}/audio"
        env = {
            "KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
            "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
            "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
            "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice",
        }
        headers = {
            "X-Internal-Demo-Token": env["KOF5_INTERNAL_DEMO_TOKEN"],
            "X-Synthetic-Material": "confirmed", "Authorization": "Bearer " + "a" * 40,
        }
        approved = "CT 검사는 오늘 14시입니다."
        authorized = True

        def respond(request: httpx.Request) -> httpx.Response:
            self.assertTrue(request.url.path.endswith("/synthetic_due_hospital_message"))
            self.assertEqual(request.headers["content-profile"], "api")
            self.assertEqual(json.loads(request.read()), {
                "_patient_id": SYNTHETIC_DB_PATIENT, "_message_id": message_id,
            })
            return httpx.Response(200, json=[{
                "authorized": authorized,
                "message_id": message_id if authorized else None,
                "approved_text": approved if authorized else None,
            }])

        async_client_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(respond)),
        ), patch("kof5_tts.api.synthesize_mp3", return_value=b"mp3") as voice:
            self.assertEqual(self.client.post(path.replace(SYNTHETIC_DB_PATIENT, "real_patient"),
                                              headers=headers).status_code, 404)
            self.assertEqual(self.client.post(path, headers={k: v for k, v in headers.items()
                                                             if k != "Authorization"}).status_code, 401)
            voice.assert_not_called()
            result = self.client.post(path, headers=headers)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json(), {"approved_text": approved, "audio_mp3_base64": "bXAz"})
            self.assertEqual(voice.call_args.args[1], approved)
            authorized = False
            self.assertEqual(self.client.post(path, headers=headers).status_code, 403)
            self.assertEqual(voice.call_count, 1, "withdrawn message must never reach TTS")


if __name__ == "__main__":
    unittest.main()
