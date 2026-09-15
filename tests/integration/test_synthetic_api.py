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
        memory_rows = [{"category": "travel", "content": "2024년 5월 제주도에 함께 갔었다."}]

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append((request.url.path, request.headers.get("authorization")))
            if not request.url.path.endswith("/embeddings"):
                self.assertEqual(request.headers["apikey"], "sb_publishable_local")
            if request.url.path.endswith("/patient_device_context"):
                return httpx.Response(200, json=[{
                    "patient_id": SYNTHETIC_DB_PATIENT, "encounter_id": "synthetic-encounter",
                }] if assigned else [])
            if request.url.path.endswith("/embeddings"):
                self.assertEqual(json.loads(request.read()), {
                    "model": "text-embedding-3-small", "input": "제주도 언제 갔었어?",
                })
                return httpx.Response(200, json={"model": "text-embedding-3-small",
                                                 "data": [{"index": 0, "embedding": [0.1] * 1536}]})
            if request.url.path.endswith("/patient_family_semantic_turn_context"):
                self.assertEqual(request.headers["content-profile"], "api")
                self.assertEqual(json.loads(request.read()), {
                    "p_patient_id": SYNTHETIC_DB_PATIENT, "p_query_embedding": [0.1] * 1536,
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
            self.assertEqual([path.rsplit("/", 1)[-1] for path, _ in calls],
                             ["patient_device_context", "embeddings", "patient_family_semantic_turn_context"])
            memory_rows = []
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "", "each turn gets fresh memory")
            memory_rows = [{"category": "medication", "content": "약물 기록"}]
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 503)
            self.assertEqual(pipeline.call_count, 2, "unsafe namespace must not reach reply")
            assigned = False
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 403)
            self.assertEqual(pipeline.call_count, 2, "revoked device cannot use stale memory")
            self.assertEqual([path.rsplit("/", 1)[-1] for path, _ in calls[-1:]],
                             ["patient_device_context"], "revocation blocks outbound transcript")

    def test_paired_turn_uses_one_approved_fact_namespace_per_question(self) -> None:
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
        authorized = True
        hospital_facts = [{
            "category": "test_schedule", "content": "CT 검사는 오늘 14시입니다.",
            "verified_at": "2026-09-16T01:00:00Z", "valid_until": None,
        }]

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request.url.path)
            if not request.url.path.endswith("/embeddings"):
                self.assertEqual(request.headers["content-profile"], "api")
            if request.url.path.endswith("/patient_hospital_turn_context"):
                return httpx.Response(200, json=[{"authorized": authorized,
                                                  "facts": hospital_facts if authorized else []}])
            if request.url.path.endswith("/patient_device_context"):
                return httpx.Response(200, json=[{
                    "patient_id": SYNTHETIC_DB_PATIENT, "encounter_id": "synthetic-encounter",
                }] if authorized else [])
            if request.url.path.endswith("/embeddings"):
                return httpx.Response(200, json={"model": "text-embedding-3-small",
                                                 "data": [{"index": 0, "embedding": [0.1] * 1536}]})
            if request.url.path.endswith("/patient_family_semantic_turn_context"):
                return httpx.Response(200, json=[{"authorized": authorized,
                                                  "facts": [{"category": "travel", "content": "2024년 제주도 여행"}] if authorized else []}])
            raise AssertionError("unrecognized fact namespace")

        async_client_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(respond)),
        ), patch("kof5_tts.api.run_synthetic_text_pipeline", return_value=("합성 답", b"mp3")) as pipeline:
            hospital_turn = {"transcript": "수민아 CT 검사는 몇 시야?", "label": "DIRECTED"}
            self.assertEqual(self.client.post(path, json=hospital_turn, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "CT 검사는 오늘 14시입니다.")
            self.assertEqual(pipeline.call_args.kwargs["namespace"], "hospital_context")
            family_turn = {"transcript": "수민아 제주도 언제 갔어?", "label": "DIRECTED"}
            self.assertEqual(self.client.post(path, json=family_turn, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "2024년 제주도 여행")
            self.assertEqual(pipeline.call_args.kwargs["namespace"], "family_context")
            self.assertEqual(len([path for path in calls if path.endswith("_turn_context")]), 2,
                             "each question uses one current authorization/fact RPC")
            hospital_facts.append(dict(hospital_facts[0], content="MRI 검사는 오늘 16시입니다."))
            self.assertEqual(self.client.post(path, json=hospital_turn, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "", "ambiguous schedules cannot pick a random fact")
            authorized = False
            self.assertEqual(self.client.post(path, json=hospital_turn, headers=headers).status_code, 403)
            self.assertEqual(pipeline.call_count, 3, "withdrawal blocks the provider")

    def test_paired_visit_reservation_reaches_exact_hospital_reply(self) -> None:
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
        approved = "수민이 면회 예약은 오늘 오후 4시입니다."

        def respond(request: httpx.Request) -> httpx.Response:
            self.assertTrue(request.url.path.endswith("/patient_hospital_turn_context"))
            return httpx.Response(200, json=[{"authorized": True, "facts": [{
                "category": "visit_schedule", "content": approved,
                "verified_at": "2026-09-16T01:00:00Z", "valid_until": None,
            }]}])

        async_client_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(respond)),
        ), patch("kof5_tts.cloud_prototype.synthesize_mp3", return_value=b"mp3"), patch(
            "kof5_tts.cloud_prototype.generate_short_reply",
            side_effect=AssertionError("approved hospital fact must not reach LLM"),
        ):
            result = self.client.post(path, json={
                "transcript": "수민아 면회 예약은 몇 시야?", "label": "DIRECTED",
            }, headers=headers)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["reply"], approved)

    def test_guardian_indexes_only_current_synthetic_fact_with_server_key(self) -> None:
        fact_id = "00000000-0000-4000-8000-000000000321"
        path = f"/internal/synthetic/guardian/{SYNTHETIC_DB_PATIENT}/fact/{fact_id}/embedding"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_SUPABASE_SECRET_KEY": "sb_secret_" + "s" * 32,
               "OPENAI_API_KEY": "test-openai"}
        headers = {"Authorization": "Bearer " + "g" * 40, "X-Synthetic-Material": "confirmed"}
        content = "2024년 5월 수민과 제주도 여행을 갔다."
        calls: list[str] = []
        ready = True
        category = "travel"

        def respond(request: httpx.Request) -> httpx.Response:
            calls.append(request.url.path.rsplit("/", 1)[-1])
            if request.url.path.endswith("/guardian_links"):
                return httpx.Response(200, json=[{
                    "patient_id": SYNTHETIC_DB_PATIENT, "access_status": "verified",
                    "effective_at": "2026-09-14T00:00:00Z", "expires_at": None,
                }] if ready else [])
            if request.url.path.endswith("/family_context"):
                return httpx.Response(200, json=[{
                    "fact_id": fact_id, "patient_id": SYNTHETIC_DB_PATIENT,
                    "content": content, "sensitivity": "ordinary", "category": category,
                    "active": True, "valid_from": "2026-09-14T00:00:00Z", "valid_until": None,
                }])
            if request.url.path.endswith("/embeddings"):
                self.assertEqual(json.loads(request.read())["input"], content)
                return httpx.Response(200, json={"model": "text-embedding-3-small",
                                                 "data": [{"index": 0, "embedding": [0.2] * 1536}]})
            if request.url.path.endswith("/upsert_synthetic_family_fact_embedding"):
                if request.headers["apikey"].startswith("sb_secret_"):
                    self.assertEqual(request.headers["apikey"], env["KOF5_SUPABASE_SECRET_KEY"])
                    self.assertNotIn("authorization", request.headers,
                                     "new Supabase secret keys must be apikey-only")
                else:
                    self.assertEqual(request.headers["authorization"],
                                     "Bearer " + request.headers["apikey"])
                body = json.loads(request.read())
                self.assertEqual(body["p_fact_id"], fact_id)
                self.assertEqual(body["p_model"], "text-embedding-3-small")
                self.assertEqual(body["p_embedding"], [0.2] * 1536)
                self.assertEqual(len(body["p_content_md5"]), 32)
                return httpx.Response(200, json=True)
            raise AssertionError("unexpected hosted route")

        async_client_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(respond)),
        ):
            self.assertEqual(self.client.post(path, headers={"X-Synthetic-Material": "confirmed"}).status_code, 401)
            self.assertEqual(calls, [])
            self.assertEqual(self.client.post(path, headers=headers).json(),
                             {"status": "ready", "fact_id": fact_id})
            self.assertEqual(calls, ["guardian_links", "family_context", "embeddings",
                                     "upsert_synthetic_family_fact_embedding"])
            calls.clear()
            ready = False
            self.assertEqual(self.client.post(path, headers=headers).status_code, 403)
            self.assertEqual(calls, ["guardian_links"], "withdrawal blocks fact export")
            ready = True
            calls.clear()
            category = "medication"
            self.assertEqual(self.client.post(path, headers=headers).status_code, 409)
            self.assertEqual(calls, ["guardian_links", "family_context"],
                             "unsafe fact category must not leave for embedding")
            category = "travel"
            calls.clear()
            with patch.dict(os.environ, {"KOF5_SUPABASE_SECRET_KEY": "",
                                       "KOF5_SUPABASE_SERVICE_ROLE_KEY": "eyJ" + "l" * 40}):
                result = self.client.post(path, headers=headers)
            self.assertEqual(result.status_code, 200)

    def test_semantic_provider_or_late_withdrawal_fails_closed(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
               "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
               "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "d" * 40}
        provider_ok = False
        seen: list[str] = []

        def respond(request: httpx.Request) -> httpx.Response:
            seen.append(request.url.path.rsplit("/", 1)[-1])
            if request.url.path.endswith("/patient_device_context"):
                return httpx.Response(200, json=[{"patient_id": SYNTHETIC_DB_PATIENT,
                                                  "encounter_id": "synthetic-encounter"}])
            if request.url.path.endswith("/embeddings"):
                return (httpx.Response(200, json={"model": "text-embedding-3-small",
                                                   "data": [{"index": 0, "embedding": [0.1] * 1536}]})
                        if provider_ok else httpx.Response(500))
            if request.url.path.endswith("/patient_family_semantic_turn_context"):
                return httpx.Response(200, json=[{"authorized": False, "facts": []}])
            raise AssertionError("unexpected hosted route")

        async_client_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(respond)),
        ), patch("kof5_tts.api.run_synthetic_text_pipeline") as pipeline:
            turn = {"transcript": "수민아 우리 휴가 어디였지?", "label": "DIRECTED"}
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 502)
            self.assertEqual(seen, ["patient_device_context", "embeddings"])
            provider_ok = True
            seen.clear()
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 403)
            self.assertEqual(seen, ["patient_device_context", "embeddings",
                                    "patient_family_semantic_turn_context"])
            pipeline.assert_not_called()

    def test_paired_discard_and_dissent_never_leave_for_embedding_or_reply(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
               "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
               "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "d" * 40}
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient", side_effect=AssertionError("discard must not call hosted API"),
        ), patch(
            "kof5_tts.api.run_synthetic_text_pipeline",
            side_effect=AssertionError("discard must not call LLM/TTS"),
        ):
            for transcript, label in (("수민아 제주도 기억나?", "AMBIENT"),
                                      ("수민아 제주도 기억나?", "UNCERTAIN"),
                                      ("수민아 그만해", "DIRECTED")):
                result = self.client.post(path, json={"transcript": transcript, "label": label},
                                          headers=headers)
                self.assertEqual(result.status_code, 200)
                self.assertIsNone(result.json()["reply"])
                self.assertIsNone(result.json()["audio_mp3_base64"])

    def test_semantic_fact_reaches_real_reply_pipeline_without_word_overlap(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
               "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
               "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "d" * 40}
        transcript = "수민아 그때 뭘 먹었어?"
        fact = "흑돼지를 좋아했다."
        hosted: list[str] = []

        def db_and_embedding(request: httpx.Request) -> httpx.Response:
            hosted.append(request.url.path.rsplit("/", 1)[-1])
            if request.url.path.endswith("/patient_device_context"):
                return httpx.Response(200, json=[{"patient_id": SYNTHETIC_DB_PATIENT,
                                                  "encounter_id": "synthetic-encounter"}])
            if request.url.path.endswith("/embeddings"):
                self.assertEqual(json.loads(request.read())["input"], transcript)
                return httpx.Response(200, json={"model": "text-embedding-3-small",
                                                 "data": [{"index": 0, "embedding": [0.1] * 1536}]})
            if request.url.path.endswith("/patient_family_semantic_turn_context"):
                self.assertEqual(json.loads(request.read())["p_query_embedding"], [0.1] * 1536)
                return httpx.Response(200, json=[{"authorized": True,
                                                  "facts": [{"category": "food", "content": fact}]}])
            raise AssertionError("unexpected DB route")

        def reply_and_voice(request: httpx.Request) -> httpx.Response:
            if request.url.path.endswith("/responses"):
                self.assertIn(fact, json.loads(request.read())["input"])
                return httpx.Response(200, json={"status": "completed", "output": [{
                    "type": "message", "content": [{"type": "output_text", "text": "흑돼지를 좋아했어."}],
                }]})
            if "/text-to-speech/" in request.url.path:
                self.assertEqual(json.loads(request.read())["text"], "흑돼지를 좋아했어.")
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("unexpected reply provider route")

        async_class = httpx.AsyncClient
        sync_class = httpx.Client
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(db_and_embedding)),
        ), patch(
            "kof5_tts.api.httpx.Client",
            side_effect=lambda **_: sync_class(transport=httpx.MockTransport(reply_and_voice)),
        ):
            result = self.client.post(path, json={"transcript": transcript, "label": "DIRECTED"},
                                      headers=headers)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["reply"], "흑돼지를 좋아했어.")
        self.assertEqual(result.json()["audio_mp3_base64"], "c3ludGhldGljLW1wMw==")
        self.assertEqual(hosted, ["patient_device_context", "embeddings",
                                  "patient_family_semantic_turn_context"])

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
