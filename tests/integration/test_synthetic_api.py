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
from tests.synthetic_wav import SYNTHETIC_WAV, make_synthetic_wav  # noqa: E402

READY_CLONE = {"authorized": True,
               "guardian_user_id": "00000000-0000-4000-8000-000000000913",
               "clone_id": "00000000-0000-4000-8000-000000000914",
               "provider": "elevenlabs", "voice_id": "guardian-clone-975"}
SERVICE_KEY = "sb_secret_" + "s" * 32
PAIRED_TURN_ID = "00000000-0000-4000-8000-000000000999"


class SyntheticApiTests(unittest.TestCase):
    def setUp(self) -> None:
        app.state.sessions.clear()
        self._paired_session_rows: dict[str, dict] = {}
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()

    def _with_synthetic_session(self, responder):
        """Add a task-local CAS fixture to older mocks focused on other boundaries."""
        def handle(request: httpx.Request) -> httpx.Response:
            route = request.url.path.rsplit("/", 1)[-1]
            if route not in {"synthetic_conversation_session_read",
                             "synthetic_conversation_session_commit"}:
                return responder(request)
            bearer = request.headers.get("authorization", "")
            row = self._paired_session_rows.setdefault(bearer, {
                "authorized": True,
                "encounter_id": "00000000-0000-4000-8000-000000000976",
                "session_id": None, "version": 0, "state": "IDLE",
                "last_activity": None, "proactive_paused": False,
            })
            if route == "synthetic_conversation_session_read":
                return httpx.Response(200, json=[dict(row)])
            body = json.loads(request.read())
            if (body.get("p_expected_session_id") != row["session_id"]
                    or body.get("p_expected_version") != row["version"]):
                return httpx.Response(200, json=[{
                    "authorized": True, "committed": False,
                    "session_id": None, "version": None,
                }])
            row["session_id"] = row["session_id"] or "00000000-0000-4000-8000-000000000971"
            row["version"] += 1
            row["state"] = body["p_new_state"]
            row["proactive_paused"] = body["p_proactive_paused"]
            row["last_activity"] = (datetime.now(timezone.utc).isoformat()
                                    if row["state"] == "ACTIVE_LISTENING" else None)
            return httpx.Response(200, json=[{
                "authorized": True, "committed": True,
                "session_id": row["session_id"], "version": row["version"],
            }])
        return handle

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

    def test_paired_db_session_continues_across_server_clients_and_fails_closed(self) -> None:
        """A DB row, rather than FastAPI process memory, carries the next turn."""
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
               "OPENAI_API_KEY": "test-openai", "ELEVENLABS_API_KEY": "test-eleven"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "a" * 40}
        row = {"authorized": True, "encounter_id": "00000000-0000-4000-8000-000000000976",
               "session_id": None, "version": 0, "state": "IDLE",
               "last_activity": None, "proactive_paused": False}
        seen: list[str] = []
        last_client_turn_id: str | None = None
        race_next_commit = False
        withdraw_after_commit = False
        withdrawn = False

        def respond(request: httpx.Request) -> httpx.Response:
            nonlocal last_client_turn_id, race_next_commit, withdrawn
            route = request.url.path.rsplit("/", 1)[-1]
            seen.append(route)
            if route == "synthetic_conversation_session_read":
                if request.headers.get("authorization") != headers["Authorization"] or withdrawn:
                    return httpx.Response(200, json=[{
                        "authorized": False, "encounter_id": None, "session_id": None,
                        "version": None, "state": None, "last_activity": None,
                        "proactive_paused": False,
                    }])
                return httpx.Response(200, json=[dict(row)])
            if route == "synthetic_conversation_session_commit":
                body = json.loads(request.read())
                if race_next_commit:
                    race_next_commit = False
                    row["version"] += 1  # Another Vercel worker won CAS.
                if (body["p_expected_session_id"] != row["session_id"]
                        or body["p_expected_version"] != row["version"]
                        or body["p_client_turn_id"] == last_client_turn_id):
                    return httpx.Response(200, json=[{
                        "authorized": True, "committed": False,
                        "session_id": None, "version": None,
                    }])
                last_client_turn_id = body["p_client_turn_id"]
                row["session_id"] = row["session_id"] or "00000000-0000-4000-8000-000000000971"
                row["version"] += 1
                row["state"] = body["p_new_state"]
                row["last_activity"] = (datetime.now(timezone.utc).isoformat()
                                        if row["state"] == "ACTIVE_LISTENING" else None)
                if withdraw_after_commit:
                    withdrawn = True
                return httpx.Response(200, json=[{
                    "authorized": True, "committed": True,
                    "session_id": row["session_id"], "version": row["version"],
                }])
            if route == "patient_device_context":
                return httpx.Response(200, json=[{
                    "patient_id": SYNTHETIC_DB_PATIENT, "encounter_id": row["encounter_id"],
                }])
            if route == "synthetic_patient_tts_voice_ready":
                return httpx.Response(200, json=[READY_CLONE])
            if route == "record_synthetic_directed_turn":
                return httpx.Response(200, json=True)
            raise AssertionError(f"unexpected hosted route: {route}")

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(respond)),
        ), patch("kof5_tts.api._paired_semantic_memory", return_value="") as semantic, patch(
            "kof5_tts.api.run_synthetic_text_pipeline", return_value=("가상 응답", b"mp3"),
        ) as pipeline:
            first = {"transcript": "수민아", "label": "DIRECTED",
                     "client_turn_id": PAIRED_TURN_ID}
            self.assertEqual(self.client.post(path, json=first, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_count, 1)
            self.assertEqual(pipeline.call_args.kwargs["routed_event"], "turn")
            # A separate TestClient has no local conversation state, but the
            # task-local DB fixture still supplies ACTIVE_LISTENING.
            with TestClient(app) as another_instance:
                follow = {"transcript": "응", "label": "UNCERTAIN",
                          "client_turn_id": "00000000-0000-4000-8000-000000000998"}
                self.assertEqual(another_instance.post(path, json=follow, headers=headers).status_code, 200)
                self.assertEqual(pipeline.call_count, 2)
                self.assertEqual(pipeline.call_args.args[2], "UNCERTAIN")
                self.assertEqual(pipeline.call_args.kwargs["routed_event"], "turn")
                self.assertEqual(seen.count("record_synthetic_directed_turn"), 1,
                                 "uncertain follow-up never enters DIRECTED today transcript")
                self.assertEqual(another_instance.post(path, json=follow, headers=headers).status_code, 409)
                self.assertEqual(pipeline.call_count, 2, "duplicate cannot synthesize again")
                other = {**headers, "Authorization": "Bearer " + "b" * 40}
                self.assertEqual(another_instance.post(path, json={**follow,
                    "client_turn_id": "00000000-0000-4000-8000-000000000997"},
                    headers=other).status_code, 403)
                self.assertEqual(pipeline.call_count, 2, "other device cannot inherit conversation")
                race_next_commit = True
                self.assertEqual(another_instance.post(path, json={**first,
                    "client_turn_id": "00000000-0000-4000-8000-000000000993"},
                    headers=headers).status_code, 409)
                self.assertEqual(pipeline.call_count, 2,
                                 "concurrent worker CAS loss cannot synthesize")
                row["state"] = "IDLE"
                row["last_activity"] = None  # DB's 45-second expiry projection.
                self.assertEqual(another_instance.post(path, json={**follow,
                    "client_turn_id": "00000000-0000-4000-8000-000000000996"},
                    headers=headers).json()["reply"], None)
                self.assertEqual(pipeline.call_count, 2, "expired UNCERTAIN is discarded")
                withdraw_after_commit = True
                self.assertEqual(another_instance.post(path, json={**first,
                    "transcript": "수민아 제주도 기억나?",
                    "client_turn_id": "00000000-0000-4000-8000-000000000995"},
                    headers=headers).status_code, 403)
                self.assertEqual(pipeline.call_count, 2,
                                 "withdrawal after CAS and before TTS stops provider")
                self.assertEqual(semantic.call_count, 1,
                                 "withdrawal after CAS and before embedding stops provider")
        self.assertIn("synthetic_conversation_session_read", seen)
        self.assertIn("synthetic_conversation_session_commit", seen)

    def test_stale_patient_refusal_latches_after_normal_turn_wins_cas(self) -> None:
        """A newer normal turn must not cause an older explicit refusal to vanish."""
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
               "OPENAI_API_KEY": "test-openai", "ELEVENLABS_API_KEY": "test-eleven"}
        headers = {"X-Internal-Demo-Token": "t" * 32,
                   "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "a" * 40}
        initial = {"authorized": True,
                   "encounter_id": "00000000-0000-4000-8000-000000000976",
                   "session_id": None, "version": 0, "state": "IDLE",
                   "last_activity": None, "proactive_paused": False}
        current = dict(initial)
        reads = 0
        commits = 0
        strict_normal_advanced = False
        other_active_owner = False
        withdrawn = False

        def respond(request: httpx.Request) -> httpx.Response:
            nonlocal reads, commits
            route = request.url.path.rsplit("/", 1)[-1]
            if route == "synthetic_conversation_session_read":
                reads += 1
                if withdrawn or other_active_owner:
                    return httpx.Response(200, json=[{
                        "authorized": False, "encounter_id": None,
                        "session_id": None, "version": None, "state": None,
                        "last_activity": None, "proactive_paused": False,
                    }])
                return httpx.Response(200, json=[dict(current)])
            if route == "synthetic_conversation_session_commit":
                body = json.loads(request.read())
                commits += 1
                if withdrawn:
                    return httpx.Response(200, json=[{
                        "authorized": False, "committed": False,
                        "session_id": None, "version": None,
                    }])
                if body["p_proactive_paused"]:
                    self.assertEqual(body["p_expected_session_id"], None)
                    self.assertEqual(body["p_expected_version"], 0)
                    current.update({"version": current["version"] + 1,
                                    "state": "IDLE", "last_activity": None,
                                    "proactive_paused": True})
                    return httpx.Response(200, json=[{
                        "authorized": True, "committed": True,
                        "session_id": current["session_id"],
                        "version": current["version"],
                    }])
                if strict_normal_advanced:
                    return httpx.Response(200, json=[{
                        "authorized": True, "committed": True,
                        "session_id": current["session_id"], "version": 3,
                    }])
                current.update({"session_id": "00000000-0000-4000-8000-000000000971",
                                "version": 1, "state": "ACTIVE_LISTENING",
                                "last_activity": datetime.now(timezone.utc).isoformat()})
                return httpx.Response(200, json=[{
                    "authorized": True, "committed": True,
                    "session_id": current["session_id"], "version": 1,
                }])
            if route == "patient_device_context":
                return httpx.Response(200, json=[{
                    "patient_id": SYNTHETIC_DB_PATIENT,
                    "encounter_id": current["encounter_id"],
                }])
            if route == "synthetic_patient_tts_voice_ready":
                return httpx.Response(200, json=[READY_CLONE])
            if route == "record_synthetic_directed_turn":
                return httpx.Response(200, json=True)
            raise AssertionError(f"unexpected hosted route: {route}")

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(respond)),
        ), patch("kof5_tts.api.run_synthetic_text_pipeline",
                 return_value=("가상 응답", b"mp3")) as pipeline:
            first = {"transcript": "수민아", "label": "DIRECTED",
                     "client_turn_id": PAIRED_TURN_ID}
            self.assertEqual(self.client.post(path, json=first, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_count, 1)
            strict_normal_advanced = True
            self.assertEqual(self.client.post(path, json={**first,
                "client_turn_id": "00000000-0000-4000-8000-000000000998"},
                headers=headers).status_code, 503,
                "normal turn still requires exactly expected version+1")
            self.assertEqual(pipeline.call_count, 1)
            strict_normal_advanced = False
            other_active_owner = True
            reads_before_refusal = reads
            refusal = {"transcript": "그만해", "label": "DIRECTED",
                       "client_turn_id": "00000000-0000-4000-8000-000000000997"}
            response = self.client.post(path, json=refusal, headers=headers)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json(), {"transcript": "", "reply": None,
                                               "audio_mp3_base64": None})
            self.assertTrue(current["proactive_paused"])
            self.assertEqual(reads, reads_before_refusal,
                             "other active owner cannot suppress pre-read refusal latch")
            self.assertEqual(pipeline.call_count, 1,
                             "stale explicit refusal never reaches provider")
            before_ambient = commits
            self.assertEqual(self.client.post(path, json={**refusal,
                "label": "AMBIENT",
                "client_turn_id": "00000000-0000-4000-8000-000000000995"},
                headers=headers).status_code, 200)
            self.assertEqual(commits, before_ambient,
                             "AMBIENT refusal words never submit a latch")
            withdrawn = True
            self.assertEqual(self.client.post(path, json={**refusal,
                "client_turn_id": "00000000-0000-4000-8000-000000000996"},
                headers=headers).status_code, 403)
            self.assertEqual(commits, 4,
                             "withdrawn device refusal reaches DB but is not committed")
            self.assertEqual(pipeline.call_count, 1)

    def test_internal_audio_requires_auth_and_valid_synthetic_wav_before_provider(self) -> None:
        path = "/internal/synthetic/audio"
        with patch.dict(os.environ, {"KOF5_INTERNAL_DEMO_TOKEN": ""}):
            self.assertEqual(self.client.post(path, content=SYNTHETIC_WAV).status_code, 503)
        env = {
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
            "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
            "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
            "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
            if request.url.path.endswith("/synthetic_patient_tts_voice_ready"):
                self.assertEqual(request.headers["apikey"], SERVICE_KEY)
                return httpx.Response(200, json=[READY_CLONE])
            if request.url.path.endswith("/record_synthetic_directed_turn"):
                self.assertEqual(request.headers["apikey"], "sb_publishable_local")
                self.assertEqual(json.loads(request.read()), {
                    "p_patient_id": SYNTHETIC_DB_PATIENT, "p_client_turn_id": PAIRED_TURN_ID,
                    "p_transcript": "제주도 언제 갔었어?",
                })
                return httpx.Response(200, json=True)
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
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
        ), patch(
            "kof5_tts.api.run_synthetic_text_pipeline", return_value=("2024년 5월에 갔었어.", b"mp3")
        ) as pipeline:
            self.assertEqual(self.client.post(path.replace(SYNTHETIC_DB_PATIENT, "real_patient"),
                                              json={"transcript": "제주도 언제 갔었어?", "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID},
                                              headers=headers).status_code, 404)
            self.assertEqual(self.client.post(path, json={"transcript": "제주도 언제 갔었어?",
                                                          "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID},
                                              headers={k: v for k, v in headers.items()
                                                       if k != "Authorization"}).status_code, 401)
            pipeline.assert_not_called()
            turn = {"transcript": "제주도 언제 갔었어?", "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID}
            result = self.client.post(path, json=turn, headers=headers)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "2024년 5월 제주도에 함께 갔었다.")
            self.assertEqual(result.json()["audio_mp3_base64"], "bXAz")
            self.assertEqual([path.rsplit("/", 1)[-1] for path, _ in calls],
                             ["patient_device_context", "synthetic_patient_tts_voice_ready",
                              "record_synthetic_directed_turn", "embeddings",
                              "patient_family_semantic_turn_context"])
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
            "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
            if request.url.path.endswith("/synthetic_patient_tts_voice_ready"):
                self.assertEqual(request.headers["apikey"], SERVICE_KEY)
                return httpx.Response(200, json=[READY_CLONE])
            if request.url.path.endswith("/record_synthetic_directed_turn"):
                self.assertEqual(request.headers["apikey"], "sb_publishable_local")
                return httpx.Response(200, json=True)
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
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
        ), patch("kof5_tts.api.run_synthetic_text_pipeline", return_value=("합성 답", b"mp3")) as pipeline:
            hospital_turn = {"transcript": "수민아 CT 검사는 몇 시야?", "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID}
            self.assertEqual(self.client.post(path, json=hospital_turn, headers=headers).status_code, 200)
            self.assertEqual(pipeline.call_args.args[3], "CT 검사는 오늘 14시입니다.")
            self.assertEqual(pipeline.call_args.kwargs["namespace"], "hospital_context")
            family_turn = {"transcript": "수민아 제주도 언제 갔어?", "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID}
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
            "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
            if request.url.path.endswith("/patient_device_context"):
                return httpx.Response(200, json=[{"patient_id": SYNTHETIC_DB_PATIENT,
                                                  "encounter_id": "synthetic-encounter"}])
            if request.url.path.endswith("/synthetic_patient_tts_voice_ready"):
                return httpx.Response(200, json=[READY_CLONE])
            if request.url.path.endswith("/record_synthetic_directed_turn"):
                return httpx.Response(200, json=True)
            self.assertTrue(request.url.path.endswith("/patient_hospital_turn_context"))
            return httpx.Response(200, json=[{"authorized": True, "facts": [{
                "category": "visit_schedule", "content": approved,
                "verified_at": "2026-09-16T01:00:00Z", "valid_until": None,
            }]}])

        async_client_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
        ), patch("kof5_tts.cloud_prototype.synthesize_mp3", return_value=b"mp3"), patch(
            "kof5_tts.cloud_prototype.generate_short_reply",
            side_effect=AssertionError("approved hospital fact must not reach LLM"),
        ):
            result = self.client.post(path, json={
                "transcript": "수민아 면회 예약은 몇 시야?", "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID,
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
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
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

    def test_guardian_follow_up_checks_current_fact_and_rejects_unsafe_question(self) -> None:
        fact_id = "00000000-0000-4000-8000-000000000321"
        path = f"/internal/synthetic/guardian/{SYNTHETIC_DB_PATIENT}/fact/{fact_id}/follow-up"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "OPENAI_API_KEY": "test-openai"}
        headers = {"Authorization": "Bearer " + "g" * 40, "X-Synthetic-Material": "confirmed"}
        content = "2024년 5월 수민과 제주도 여행을 갔다."
        output_text = json.dumps({"source_quote": "제주도 여행", "focus": "scene"}, ensure_ascii=False)
        question = "말씀해주신 ‘제주도 여행’ 이야기에서 가장 기억에 남는 장면은 무엇인가요?"
        linked = True
        category = "travel"
        active = True
        provider_status = 200
        provider_calls: list[str] = []
        mutate_on_provider: str | None = None

        def guardian_db(request: httpx.Request) -> httpx.Response:
            self.assertEqual(request.headers["apikey"], "sb_publishable_local")
            if request.url.path.endswith("/guardian_links"):
                return httpx.Response(200, json=[{
                    "patient_id": SYNTHETIC_DB_PATIENT, "access_status": "verified",
                    "effective_at": "2026-09-14T00:00:00Z", "expires_at": None,
                }] if linked else [])
            if request.url.path.endswith("/family_context"):
                return httpx.Response(200, json=[{
                    "fact_id": fact_id, "patient_id": SYNTHETIC_DB_PATIENT,
                    "content": content, "sensitivity": "ordinary", "category": category,
                    "active": active, "valid_from": "2026-09-14T00:00:00Z", "valid_until": None,
                }])
            raise AssertionError("unexpected guardian DB route")

        def candidate(request: httpx.Request) -> httpx.Response:
            nonlocal content, linked
            provider_calls.append(request.url.path)
            self.assertTrue(request.url.path.endswith("/v1/responses"))
            body = json.loads(request.read())
            self.assertEqual(body["model"], "gpt-5.4-mini")
            self.assertIs(body["store"], False)
            self.assertLessEqual(body["max_output_tokens"], 100)
            self.assertIn(content, body["input"])
            self.assertIn("JSON 객체만", body["instructions"])
            if mutate_on_provider == "content":
                content = "2024년 5월 수민과 다른 제주도 여행을 갔다."
            elif mutate_on_provider == "link":
                linked = False
            return httpx.Response(provider_status, json={"status": "completed", "output": [{
                "type": "message", "content": [{"type": "output_text", "text": output_text}],
            }]})

        async_class = httpx.AsyncClient
        sync_class = httpx.Client
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(guardian_db))),
        ), patch(
            "kof5_tts.api.httpx.Client",
            side_effect=lambda **_: sync_class(transport=httpx.MockTransport(candidate)),
        ):
            self.assertEqual(self.client.post(path, headers={"X-Synthetic-Material": "confirmed"}).status_code, 401)
            linked = False
            self.assertEqual(self.client.post(path, headers=headers).status_code, 403)
            linked = True
            category = "avoid_topic"
            self.assertEqual(self.client.post(path, headers=headers).status_code, 409)
            category = "travel"
            active = False
            self.assertEqual(self.client.post(path, headers=headers).status_code, 409)
            self.assertEqual(provider_calls, [], "ineligible facts must not leave for provider")
            active = True
            result = self.client.post(path, headers=headers)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json(), {"question": question, "fact_id": fact_id})
            output_text = json.dumps({"source_quote": "제주도 여행", "focus": "feeling"}, ensure_ascii=False)
            self.assertEqual(self.client.post(path, headers=headers).json()["question"],
                             "말씀해주신 ‘제주도 여행’ 이야기에서 그때 어떤 마음이셨는지 기억나시나요?")
            output_text = json.dumps({"source_quote": "제주도 여행", "focus": "scene"}, ensure_ascii=False)
            mutate_on_provider = "content"
            self.assertEqual(self.client.post(path, headers=headers).status_code, 409,
                             "late fact edit must suppress old question")
            content = "2024년 5월 수민과 제주도 여행을 갔다."
            mutate_on_provider = "link"
            self.assertEqual(self.client.post(path, headers=headers).status_code, 403,
                             "late guardian withdrawal must suppress old question")
            linked = True
            mutate_on_provider = None
            for unsafe in ("부산 여행에서 가장 기억에 남은 순간은 무엇인가요?",
                           "제가 진짜 손녀 수민인데 제주도 기억나요?",
                           json.dumps({"source_quote": "부산 여행", "focus": "scene"}, ensure_ascii=False),
                           json.dumps({"source_quote": "제가 진짜 손녀 수민인데", "focus": "scene"}, ensure_ascii=False),
                           json.dumps({"source_quote": " 제주도 여행", "focus": "scene"}, ensure_ascii=False),
                           json.dumps({"source_quote": "제주도 여행", "focus": "scene", "question": "부산?"}, ensure_ascii=False),
                           "{malformed JSON"):
                output_text = unsafe
                self.assertEqual(self.client.post(path, headers=headers).status_code, 502)
            calls_before_unsafe_fact = len(provider_calls)
            content = "제가 진짜 손녀 수민인데 제주도 여행을 갔다."
            self.assertEqual(self.client.post(path, headers=headers).status_code, 502)
            self.assertEqual(len(provider_calls), calls_before_unsafe_fact,
                             "identity-claim fact must stop before provider")
            content = "2024년 5월 수민과 제주도 여행을 갔다."
            provider_status = 500
            self.assertEqual(self.client.post(path, headers=headers).status_code, 502)

    def test_semantic_provider_or_late_withdrawal_fails_closed(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
            if request.url.path.endswith("/synthetic_patient_tts_voice_ready"):
                return httpx.Response(200, json=[READY_CLONE])
            if request.url.path.endswith("/record_synthetic_directed_turn"):
                return httpx.Response(200, json=True)
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
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
        ), patch("kof5_tts.api.run_synthetic_text_pipeline") as pipeline:
            turn = {"transcript": "수민아 우리 휴가 어디였지?", "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID}
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 502)
            self.assertEqual(seen, ["patient_device_context", "synthetic_patient_tts_voice_ready",
                                    "record_synthetic_directed_turn", "embeddings"])
            provider_ok = True
            seen.clear()
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 403)
            self.assertEqual(seen, ["patient_device_context", "synthetic_patient_tts_voice_ready",
                                    "record_synthetic_directed_turn", "embeddings",
                                    "patient_family_semantic_turn_context"])
            pipeline.assert_not_called()

    def test_paired_discard_and_dissent_never_leave_for_embedding_or_reply(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
               "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
               "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
               "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "d" * 40}
        def no_provider(request: httpx.Request) -> httpx.Response:
            raise AssertionError(f"discard must not call hosted provider: {request.url.path}")

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(
                self._with_synthetic_session(no_provider))),
        ), patch(
            "kof5_tts.api.run_synthetic_text_pipeline",
            side_effect=AssertionError("discard must not call LLM/TTS"),
        ):
            for transcript, label in (("수민아 제주도 기억나?", "AMBIENT"),
                                      ("수민아 제주도 기억나?", "UNCERTAIN"),
                                      ("수민아 그만해", "DIRECTED")):
                result = self.client.post(path, json={"transcript": transcript, "label": label,
                                                      "client_turn_id": PAIRED_TURN_ID},
                                          headers=headers)
                self.assertEqual(result.status_code, 200)
                self.assertEqual(result.json()["transcript"], "", "discarded transcript must not echo")
                self.assertIsNone(result.json()["reply"])
                self.assertIsNone(result.json()["audio_mp3_base64"])
                unpaired = self.client.post("/internal/synthetic/text",
                                            json={"transcript": transcript, "label": label},
                                            headers={k: v for k, v in headers.items() if k != "Authorization"})
                self.assertEqual(unpaired.status_code, 200)
                self.assertEqual(unpaired.json()["transcript"], "")

    def test_paired_policy_medical_question_skips_embedding_and_llm(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
               "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-consent",
               "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
               "ELEVENLABS_API_KEY": "test-eleven", "ELEVENLABS_VOICE_ID": "test-voice"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "d" * 40}
        seen: list[str] = []

        def preflight(request: httpx.Request) -> httpx.Response:
            seen.append(request.url.path.rsplit("/", 1)[-1])
            if request.url.path.endswith("/synthetic_patient_tts_voice_ready"):
                return httpx.Response(200, json=[READY_CLONE])
            if request.url.path.endswith("/record_synthetic_directed_turn"):
                return httpx.Response(200, json=True)
            self.assertTrue(request.url.path.endswith("/patient_device_context"),
                            "policy-only speech must not call embeddings or family facts")
            return httpx.Response(200, json=[{"patient_id": SYNTHETIC_DB_PATIENT,
                                              "encounter_id": "synthetic-encounter"}])

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(preflight))),
        ), patch("kof5_tts.cloud_prototype.generate_short_reply",
                 side_effect=AssertionError("medical policy must not call LLM")), patch(
            "kof5_tts.cloud_prototype.synthesize_mp3", return_value=b"mp3",
        ):
            result = self.client.post(path, json={"transcript": "수민아 무슨 약을 먹어야 해?",
                                                  "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID}, headers=headers)
        self.assertEqual(result.status_code, 200)
        self.assertIn("의료진", result.json()["reply"])
        self.assertEqual(seen, ["patient_device_context", "synthetic_patient_tts_voice_ready",
                                "record_synthetic_directed_turn"])

    def test_semantic_fact_reaches_real_reply_pipeline_without_word_overlap(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
               "OPENAI_API_KEY": "test-openai", "ELEVENLABS_API_KEY": "test-eleven"}
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
            if request.url.path.endswith("/synthetic_patient_tts_voice_ready"):
                self.assertEqual(request.headers["apikey"], SERVICE_KEY)
                return httpx.Response(200, json=[READY_CLONE])
            if request.url.path.endswith("/record_synthetic_directed_turn"):
                self.assertEqual(request.headers["apikey"], "sb_publishable_local")
                return httpx.Response(200, json=True)
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
                self.assertTrue(request.url.path.endswith("/guardian-clone-975"),
                                "paired TTS must use DB-selected clone ID")
                self.assertEqual(json.loads(request.read())["text"], "흑돼지를 좋아했어.")
                return httpx.Response(200, content=b"synthetic-mp3")
            raise AssertionError("unexpected reply provider route")

        async_class = httpx.AsyncClient
        sync_class = httpx.Client
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(db_and_embedding))),
        ), patch(
            "kof5_tts.api.httpx.Client",
            side_effect=lambda **_: sync_class(transport=httpx.MockTransport(reply_and_voice)),
        ):
            result = self.client.post(path, json={"transcript": transcript, "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID},
                                      headers=headers)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["reply"], "흑돼지를 좋아했어.")
        self.assertEqual(result.json()["audio_mp3_base64"], "c3ludGhldGljLW1wMw==")
        self.assertEqual(hosted, ["patient_device_context", "synthetic_patient_tts_voice_ready",
                                  "record_synthetic_directed_turn", "embeddings",
                                  "patient_family_semantic_turn_context"])

    def test_due_hospital_message_voices_only_atomic_approved_original(self) -> None:
        message_id = "00000000-0000-4000-8000-000000000123"
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/message/{message_id}/audio"
        env = {
            "KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
            "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
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
        spoken: list[str] = []

        def respond(request: httpx.Request) -> httpx.Response:
            if request.url.path.endswith("/patient_device_context"):
                return httpx.Response(200, json=[{"patient_id": SYNTHETIC_DB_PATIENT,
                                                  "encounter_id": "synthetic-encounter"}])
            if request.url.path.endswith("/synthetic_patient_tts_voice_ready"):
                return httpx.Response(200, json=[READY_CLONE])
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
        sync_client_class = httpx.Client

        def provider(request: httpx.Request) -> httpx.Response:
            spoken.append(request.url.path)
            self.assertTrue(request.url.path.endswith("/guardian-clone-975"))
            self.assertEqual(json.loads(request.read())["text"], approved)
            return httpx.Response(200, content=b"mp3")

        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_client_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
        ), patch("kof5_tts.api.httpx.Client",
                 side_effect=lambda **_: sync_client_class(transport=httpx.MockTransport(provider))):
            self.assertEqual(self.client.post(path.replace(SYNTHETIC_DB_PATIENT, "real_patient"),
                                              headers=headers).status_code, 404)
            self.assertEqual(self.client.post(path, headers={k: v for k, v in headers.items()
                                                             if k != "Authorization"}).status_code, 401)
            self.assertEqual(spoken, [])
            result = self.client.post(path, headers=headers)
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json(), {"approved_text": approved, "audio_mp3_base64": "bXAz"})
            self.assertEqual(len(spoken), 1)
            authorized = False
            self.assertEqual(self.client.post(path, headers=headers).status_code, 403)
            self.assertEqual(len(spoken), 1, "withdrawn message must never reach TTS")

    def test_paired_voice_ready_denials_block_text_and_message_before_provider(self) -> None:
        message_id = "00000000-0000-4000-8000-000000000123"
        paths = (f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text",
                 f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/message/{message_id}/audio")
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "VOICE_OWNER_CONSENT_RECORD_ID": "", "ELEVENLABS_VOICE_ID": "",
               "DEEPGRAM_API_KEY": "test-deepgram", "OPENAI_API_KEY": "test-openai",
               "ELEVENLABS_API_KEY": "test-eleven"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "d" * 40}
        cases = (("no_clone", [{"authorized": False}], 403),
                 ("wrong_provider", [{**READY_CLONE, "provider": "other"}], 503),
                 ("invalid_voice", [{**READY_CLONE, "voice_id": "bad/id"}], 503),
                 ("ambiguous", [READY_CLONE, READY_CLONE], 503))
        selected: list[dict] = []
        seen: list[str] = []

        def respond(request: httpx.Request) -> httpx.Response:
            route = request.url.path.rsplit("/", 1)[-1]
            seen.append(route)
            if route == "patient_device_context":
                return httpx.Response(200, json=[{"patient_id": SYNTHETIC_DB_PATIENT,
                                                  "encounter_id": "synthetic-encounter"}])
            if route == "synthetic_patient_tts_voice_ready":
                self.assertEqual(request.headers["apikey"], SERVICE_KEY)
                return httpx.Response(200, json=selected)
            raise AssertionError("denied voice cannot reach embedding/facts/message")

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
        ), patch("kof5_tts.api.run_synthetic_text_pipeline") as reply, patch(
            "kof5_tts.api.synthesize_mp3",
        ) as speech:
            for name, rows, expected in cases:
                selected = rows
                for path in paths:
                    seen.clear()
                    request_json = {"transcript": "수민아 제주도 기억나?", "label": "DIRECTED", "client_turn_id": PAIRED_TURN_ID} if path.endswith("/text") else None
                    response = self.client.post(path, json=request_json, headers=headers)
                    self.assertEqual(response.status_code, expected, name)
                    self.assertEqual(seen, ["patient_device_context", "synthetic_patient_tts_voice_ready"], name)
            reply.assert_not_called()
            speech.assert_not_called()

    def test_directed_record_requires_v4_and_fails_closed_before_semantic_provider(self) -> None:
        path = f"/internal/synthetic/paired/{SYNTHETIC_DB_PATIENT}/text"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_SUPABASE_SECRET_KEY": SERVICE_KEY,
               "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
               "OPENAI_API_KEY": "test-openai", "ELEVENLABS_API_KEY": "test-eleven"}
        headers = {"X-Internal-Demo-Token": "t" * 32, "X-Synthetic-Material": "confirmed",
                   "Authorization": "Bearer " + "d" * 40}
        turn = {"transcript": " 수민아 제주도 기억나? ", "label": "DIRECTED",
                "client_turn_id": PAIRED_TURN_ID}
        record_status = 200
        record_result = False
        seen: list[str] = []

        def respond(request: httpx.Request) -> httpx.Response:
            route = request.url.path.rsplit("/", 1)[-1]
            seen.append(route)
            if route == "patient_device_context":
                return httpx.Response(200, json=[{"patient_id": SYNTHETIC_DB_PATIENT,
                                                  "encounter_id": "synthetic-encounter"}])
            if route == "synthetic_patient_tts_voice_ready":
                return httpx.Response(200, json=[READY_CLONE])
            if route == "record_synthetic_directed_turn":
                self.assertEqual(request.headers["apikey"], "sb_publishable_local")
                self.assertEqual(request.headers["content-profile"], "api")
                self.assertEqual(json.loads(request.read()), {
                    "p_patient_id": SYNTHETIC_DB_PATIENT, "p_client_turn_id": PAIRED_TURN_ID,
                    "p_transcript": "수민아 제주도 기억나?",
                })
                return httpx.Response(record_status, json=record_result)
            raise AssertionError("failed record must stop before embedding/facts/LLM/TTS")

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(respond))),
        ), patch("kof5_tts.api.run_synthetic_text_pipeline") as pipeline:
            self.assertEqual(self.client.post(path, json={k: v for k, v in turn.items()
                                                          if k != "client_turn_id"}, headers=headers).status_code, 422)
            self.assertEqual(self.client.post(path, json={**turn,
                                                          "client_turn_id": "00000000-0000-1000-8000-000000000999"},
                                              headers=headers).status_code, 422)
            self.assertEqual(seen, [], "invalid turn ID cannot reach DB")
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 403)
            self.assertEqual(seen, ["patient_device_context", "synthetic_patient_tts_voice_ready",
                                    "record_synthetic_directed_turn"])
            seen.clear()
            record_status = 500
            self.assertEqual(self.client.post(path, json=turn, headers=headers).status_code, 503)
            self.assertEqual(seen, ["patient_device_context", "synthetic_patient_tts_voice_ready",
                                    "record_synthetic_directed_turn"])
            pipeline.assert_not_called()

    def test_guardian_voice_pending_before_provider_and_absence_before_deleted(self) -> None:
        from base64 import b64encode
        from kof5_tts.cloud_prototype import EnrolledVoice

        patient = SYNTHETIC_DB_PATIENT
        clone_id = "00000000-0000-4000-8000-000000000412"
        guardian_id = "00000000-0000-4000-8000-000000000413"
        consent_id = "00000000-0000-4000-8000-000000000414"
        request_key = "00000000-0000-4000-8000-000000000415"
        name = "KoF5 internal self-voice test " + request_key.replace("-", "")
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_SUPABASE_SECRET_KEY": "sb_secret_" + "s" * 32,
               "KOF5_SYNTHETIC_GUARDIAN_VOICE_UPLOAD_ENABLED": "1",
               "ELEVENLABS_API_KEY": "test-eleven"}
        headers = {"Authorization": "Bearer " + "g" * 40, "X-Synthetic-Material": "confirmed"}
        state = "none"
        withdrawn_during_create = False
        calls: list[str] = []

        def hosted(request: httpx.Request) -> httpx.Response:
            nonlocal state
            route = request.url.path.rsplit("/", 1)[-1]
            calls.append(route)
            if route == "user":
                return httpx.Response(200, json={"id": guardian_id, "is_anonymous": False})
            if route == "synthetic_guardian_voice_status":
                return httpx.Response(200, json=[{"authorized": True, "clone_id": clone_id if state != "none" else None,
                                                  "ready": state == "none", "consent_id": consent_id,
                                                  "status": state, "provider": "elevenlabs" if state != "none" else None,
                                                  "provider_name": name if state != "none" else None}])
            if route == "synthetic_guardian_voice_begin":
                self.assertEqual(request.headers["apikey"], env["KOF5_SUPABASE_SECRET_KEY"])
                self.assertNotIn("authorization", request.headers)
                body = json.loads(request.read())
                self.assertEqual(body["p_guardian_user_id"], guardian_id)
                self.assertEqual(body["p_consent_id"], consent_id)
                self.assertEqual(body["p_sample_durations_ms"], [20000] * 3)
                state = "pending"
                return httpx.Response(200, json=[{"authorized": True, "clone_id": clone_id,
                                                  "status": "pending", "provider_name": name,
                                                  "newly_created": True}])
            if route == "synthetic_guardian_voice_provider_result":
                self.assertEqual(json.loads(request.read())["p_verification_confirmed"], False)
                state = "deletion_pending" if withdrawn_during_create else "verification_pending"
                return httpx.Response(200, json=[{"authorized": True, "clone_id": clone_id,
                                                  "status": state, "provider_name": name,
                                                  "voice_id": "voice123"}])
            if route == "synthetic_guardian_voice_request_deletion":
                state = "deletion_pending"
                return httpx.Response(200, json=[{"authorized": True, "clone_id": clone_id,
                                                  "status": state, "provider_name": name,
                                                  "voice_id": "voice123"}])
            if route == "synthetic_guardian_voice_confirm_remote_absence":
                self.assertEqual(json.loads(request.read())["p_method"], "voice_id_not_found")
                state = "deleted"
                return httpx.Response(200, json=[{"authorized": True, "clone_id": clone_id,
                                                  "status": state, "provider_name": name,
                                                  "voice_id": "voice123"}])
            raise AssertionError(f"unexpected hosted route: {route}")

        sample = b64encode(make_synthetic_wav(20)).decode("ascii")
        enrollment = {"consent_id": consent_id, "request_key": request_key,
                      "own_voice_confirmed": True, "samples_wav_base64": [sample] * 3}
        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(hosted))),
        ), patch("kof5_tts.api.enroll_test_voice", return_value=EnrolledVoice("voice123", True)) as create, patch(
            "kof5_tts.api.delete_test_voice", return_value=None,
        ) as remove:
            self.assertEqual(self.client.post(f"/internal/synthetic/guardian/{patient}/voice/enroll",
                                              json=enrollment, headers=headers).json(),
                             {"status": "verification_pending", "clone_id": clone_id})
            self.assertEqual(calls[:3], ["user", "synthetic_guardian_voice_status",
                                         "synthetic_guardian_voice_begin"])
            self.assertEqual(create.call_count, 1, "provider POST starts after pending DB row")
            self.assertEqual(self.client.post(f"/internal/synthetic/guardian/{patient}/voice/{clone_id}/delete",
                                              headers=headers).json(), {"status": "deleted", "clone_id": clone_id})
            self.assertEqual(remove.call_count, 1)
            self.assertEqual(calls[-2:], ["synthetic_guardian_voice_request_deletion",
                                          "synthetic_guardian_voice_confirm_remote_absence"])
            state = "verification_pending"  # Prior ack does not authorize skipping a retry DELETE.
            request = httpx.Request("DELETE", "https://api.elevenlabs.io/v1/voices/voice123")
            remove.side_effect = httpx.HTTPStatusError("not found", request=request,
                                                       response=httpx.Response(404, request=request))
            self.assertEqual(self.client.post(f"/internal/synthetic/guardian/{patient}/voice/{clone_id}/delete",
                                              headers=headers).json(),
                             {"status": "deletion_pending", "clone_id": clone_id})
            self.assertEqual(remove.call_count, 2, "404 cannot prove safe deletion")
            remove.side_effect = None
            self.assertEqual(self.client.post(f"/internal/synthetic/guardian/{patient}/voice/{clone_id}/delete",
                                              headers=headers).json(), {"status": "deleted", "clone_id": clone_id})
            self.assertEqual(remove.call_count, 3)
            state = "none"
            withdrawn_during_create = True
            self.assertEqual(self.client.post(f"/internal/synthetic/guardian/{patient}/voice/enroll",
                                              json=enrollment, headers=headers).json(),
                             {"status": "deleted", "clone_id": clone_id})
            self.assertEqual(remove.call_count, 4,
                             "late consent withdrawal must start remote deletion immediately")

    def test_guardian_voice_upload_gate_and_idempotent_retry_never_post_twice(self) -> None:
        from base64 import b64encode

        patient = SYNTHETIC_DB_PATIENT
        guardian = "00000000-0000-4000-8000-000000000513"
        consent = "00000000-0000-4000-8000-000000000514"
        request_key = "00000000-0000-4000-8000-000000000515"
        path = f"/internal/synthetic/guardian/{patient}/voice/enroll"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_SUPABASE_SECRET_KEY": "sb_secret_" + "s" * 32,
               "ELEVENLABS_API_KEY": "test-eleven"}
        headers = {"Authorization": "Bearer " + "g" * 40, "X-Synthetic-Material": "confirmed"}
        sample = b64encode(make_synthetic_wav(20)).decode("ascii")
        payload = {"consent_id": consent, "request_key": request_key,
                   "own_voice_confirmed": True, "samples_wav_base64": [sample] * 3}
        seen: list[str] = []

        def hosted(request: httpx.Request) -> httpx.Response:
            route = request.url.path.rsplit("/", 1)[-1]
            seen.append(route)
            if route == "user":
                return httpx.Response(200, json={"id": guardian, "is_anonymous": False})
            if route == "synthetic_guardian_voice_status":
                return httpx.Response(200, json=[{"authorized": True, "status": "none",
                                                  "ready": True, "consent_id": consent}])
            if route == "synthetic_guardian_voice_begin":
                return httpx.Response(200, json=[{"authorized": True,
                                                  "clone_id": "00000000-0000-4000-8000-000000000512",
                                                  "status": "pending",
                                                  "provider_name": "KoF5 internal self-voice test " + request_key.replace("-", ""),
                                                  "newly_created": False}])
            raise AssertionError("retry must not call provider")

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(hosted))),
        ), patch("kof5_tts.api.enroll_test_voice") as provider:
            self.assertEqual(self.client.post(path, json=payload, headers=headers).status_code, 503)
            self.assertEqual(seen, ["user", "synthetic_guardian_voice_status"],
                             "default-off gate blocks begin and provider")
            seen.clear()
            with patch.dict(os.environ, {"KOF5_SYNTHETIC_GUARDIAN_VOICE_UPLOAD_ENABLED": "1"}):
                self.assertEqual(self.client.post(path, json=payload, headers=headers).status_code, 409)
            self.assertEqual(seen, ["user", "synthetic_guardian_voice_status",
                                    "synthetic_guardian_voice_begin"])
            provider.assert_not_called()

    def test_pending_create_delete_waits_for_late_exact_id_then_cleans_up(self) -> None:
        patient = SYNTHETIC_DB_PATIENT
        clone_id = "00000000-0000-4000-8000-000000000612"
        guardian = "00000000-0000-4000-8000-000000000613"
        name = "KoF5 internal self-voice test " + "a" * 32
        path = f"/internal/synthetic/guardian/{patient}/voice/{clone_id}/delete"
        env = {"KOF5_SUPABASE_URL": "http://127.0.0.1:54341",
               "KOF5_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local",
               "KOF5_SUPABASE_SECRET_KEY": "sb_secret_" + "s" * 32,
               "ELEVENLABS_API_KEY": "test-eleven"}
        headers = {"Authorization": "Bearer " + "g" * 40, "X-Synthetic-Material": "confirmed"}
        calls: list[str] = []
        db_status = "pending"
        attached_id: str | None = None

        def hosted(request: httpx.Request) -> httpx.Response:
            nonlocal db_status, attached_id
            route = request.url.path.rsplit("/", 1)[-1]
            calls.append(route)
            if route == "user":
                return httpx.Response(200, json={"id": guardian, "is_anonymous": False})
            if route == "synthetic_guardian_voice_status":
                return httpx.Response(200, json=[{"authorized": True, "ready": False,
                                                  "consent_id": None, "clone_id": clone_id,
                                                  "status": db_status, "provider": "elevenlabs",
                                                  "provider_name": name}])
            if route == "synthetic_guardian_voice_request_deletion":
                db_status = "deletion_pending"
                return httpx.Response(200, json=[{"authorized": True, "status": db_status,
                                                  "clone_id": clone_id, "provider_name": name,
                                                  "voice_id": attached_id}])
            if route == "synthetic_guardian_voice_provider_result":
                self.assertEqual(json.loads(request.read()), {
                    "p_clone_id": clone_id, "p_voice_id": "voice-late",
                    "p_verification_confirmed": False,
                })
                attached_id = "voice-late"
                return httpx.Response(200, json=[{"authorized": True, "status": "deletion_pending",
                                                  "clone_id": clone_id, "provider_name": name,
                                                  "voice_id": attached_id}])
            if route == "synthetic_guardian_voice_confirm_remote_absence":
                self.assertEqual(json.loads(request.read())["p_method"], "voice_id_not_found")
                db_status = "deleted"
                return httpx.Response(200, json=[{"authorized": True, "status": "deleted",
                                                  "clone_id": clone_id, "provider_name": name,
                                                  "voice_id": attached_id}])
            raise AssertionError("unexpected hosted route")

        async_class = httpx.AsyncClient
        with patch.dict(os.environ, env), patch(
            "kof5_tts.api.httpx.AsyncClient",
            side_effect=lambda **_: async_class(transport=httpx.MockTransport(self._with_synthetic_session(hosted))),
        ), patch("kof5_tts.api.find_test_voice", side_effect=[None, "voice-late"]) as find, patch(
            "kof5_tts.api.delete_test_voice", return_value=None,
        ) as remove, patch(
            "kof5_tts.api.enroll_test_voice",
            side_effect=AssertionError("deletion retry must never repeat provider POST"),
        ):
            first = self.client.post(path, headers=headers)
            self.assertEqual(first.json(), {"status": "deletion_pending", "clone_id": clone_id})
            self.assertNotIn("synthetic_guardian_voice_confirm_remote_absence", calls,
                             "empty name search cannot prove a slow create absent")
            remove.assert_not_called()
            second = self.client.post(path, headers=headers)
            self.assertEqual(second.json(), {"status": "deleted", "clone_id": clone_id})
            self.assertEqual(find.call_count, 2)
            remove.assert_called_once()
            self.assertEqual(calls[-2:], ["synthetic_guardian_voice_provider_result",
                                          "synthetic_guardian_voice_confirm_remote_absence"])

    def test_exact_id_delete_requires_ack_even_if_provider_list_is_empty(self) -> None:
        from kof5_tts.api import _remove_test_clone

        seen: list[str] = []
        rejected = True

        def provider(request: httpx.Request) -> httpx.Response:
            nonlocal rejected
            seen.append(request.method)
            if request.method == "DELETE":
                if rejected:
                    rejected = False
                    return httpx.Response(404)
                return httpx.Response(200, json={"status": "ok"})
            if request.method == "GET":
                return httpx.Response(200, json={"voices": [], "has_more": False})
            raise AssertionError("unexpected provider method")

        sync_class = httpx.Client
        with patch("kof5_tts.api.httpx.Client",
                   side_effect=lambda **_: sync_class(transport=httpx.MockTransport(provider))):
            with self.assertRaises(httpx.HTTPStatusError):
                _remove_test_clone("voice-late", "test-key")
            self.assertEqual(seen, ["DELETE"], "empty list cannot replace a DELETE ack")
            self.assertEqual(_remove_test_clone("voice-late", "test-key"), "voice_id_not_found")
        self.assertEqual(seen, ["DELETE", "DELETE", "GET"],
                         "acknowledged DELETE must precede exact-ID absence check")


if __name__ == "__main__":
    unittest.main()
