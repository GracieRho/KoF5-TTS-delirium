"""연구 보관 동의, 복구, 관리자 인증, 매체 재생, 철회 경로에 대한 통합 테스트."""
import os
import unittest
from unittest.mock import patch

import httpx
from tests import test_voice_only as studio
from kof5_tts import research, voice_only
from kof5_tts.research_store import PAGE_SIZE
from kof5_tts.voice_store import StoreUnavailable


class ResearchTests(unittest.TestCase):
    def setUp(self):
        studio.VoiceAPITest.setUp(self)
        env = patch.dict(os.environ, {"FAVILIUM_RESEARCHER_EMAILS": "researcher@example.invalid"})
        env.start()
        self.addCleanup(env.stop)
        self.staff = self.new_browser()
        self.auth_calls = []
        self.allowed_user = {"email": "researcher@example.invalid", "email_confirmed_at": "2026-01-01T00:00:00Z"}
        self.auth_response_user = self.allowed_user
        def auth(method, path, *, token=None, body=None):
            self.auth_calls.append((method, path, body))
            if path == "otp" or path.startswith("logout"):
                return httpx.Response(200, json={})
            if path == "verify" and body.get("token") == "123456":
                return httpx.Response(200, json={"access_token": "test-otp-session", "expires_in": 3600, "user": self.auth_response_user})
            if path == "user" and token == "test-otp-session":
                return httpx.Response(200, json=self.auth_response_user)
            return httpx.Response(403, json={})
        mock = patch.object(research, "auth_request", side_effect=auth)
        mock.start()
        self.addCleanup(mock.stop)

    new_browser = studio.VoiceAPITest.new_browser
    open_workspace = studio.VoiceAPITest.open_workspace

    def login(self):
        response = self.staff.post("/api/research/login/verify", json={"email": self.allowed_user["email"], "proof":"123456"})
        self.assertEqual(response.status_code, 200, response.text)
        return response

    def enroll(self, opt_in):
        self.open_workspace()
        headers = {"Content-Type": "audio/wav", "X-Voice-Consent":"yes"}
        if opt_in:
            headers["X-Research-Consent"] = "archive-v1"
        response = self.browser.post("/api/voice", headers=headers, content=studio.recording() + b"private-trailer")
        self.assertEqual(response.status_code, 200, response.text)
        self.ref = response.json()["reference"]
        self.root = "/api/research/voices/" + self.ref
        self.studio_headers = {"X-Voice-Reference": self.ref}

    def synth(self):
        response = self.browser.post("/api/speech", json={"text": "연구용 점검 문장."}, headers=self.studio_headers)
        self.assertEqual(response.status_code, 200, response.text)
        return response

    def test_gate_and_otp_session(self):
        self.enroll(True)
        for url in ("/api/research/session", "/api/research/voices", self.root + "/sample", self.root + "/speech"):
            self.assertEqual(self.browser.get(url).status_code, 401)
        self.assertEqual(self.browser.delete(self.root).status_code, 401)
        self.assertEqual(self.browser.post(self.root + "/speech", json={"text":"테스트"}).status_code, 401)
        self.staff.cookies.set(research.COOKIE, "test-otp-session", path=research.COOKIE_PATH)
        self.assertEqual(self.staff.get("/api/research/session").status_code, 401)
        self.staff.cookies.clear()
        send = "/api/research/login/email"
        for email, origin, status in (("outsider@example.invalid", studio.ORIGIN, 403),
                                      (self.allowed_user["email"], "https://foreign.example", 403)):
            self.assertEqual(self.staff.post(send, json={"email":email}, headers={"Origin":origin}).status_code,status)
        self.assertFalse(self.auth_calls)
        self.assertEqual(self.staff.post(send, json={"email":self.allowed_user["email"]}).status_code,204)
        self.auth_response_user = {**self.allowed_user, "email_confirmed_at": None}
        self.assertEqual(self.staff.post("/api/research/login/verify",json={"email":self.allowed_user["email"],"proof":"123456"}).status_code,401)
        self.auth_response_user = self.allowed_user
        cookie = self.login().headers["set-cookie"]
        for term in ("HttpOnly","Secure","SameSite=strict","Path=/api/research"):
            self.assertIn(term, cookie)
        self.assertEqual(self.staff.get("/api/research/session").json(), {"email":self.allowed_user["email"]})
        self.assertEqual(self.staff.post("/api/research/logout").status_code,204)
        self.assertEqual(self.staff.get(self.root + "/sample").status_code,401)

    def test_storage_off_by_default_and_prospective_for_existing_voices(self):
        self.enroll(False)
        self.login()
        self.assertEqual(self.synth().headers["X-Favilium-Archive"],"off")
        self.assertEqual(self.staff.get(self.root + "/sample").status_code,404)
        self.assertEqual(self.staff.get(self.root + "/speech").json()["items"],[])
        self.assertEqual(self.staff.post(self.root + "/speech",json={"text":"음성 합성"}).status_code,403)
        self.assertEqual(self.browser.post("/api/workspace/next",headers=self.studio_headers).status_code,409)
        self.assertEqual(self.browser.post("/api/voice/archive-consent",headers=self.studio_headers).status_code,403)
        response=self.browser.post("/api/voice/archive-consent",headers={**self.studio_headers,"X-Research-Consent":"archive-v1"})
        self.assertEqual(response.status_code,204)
        self.assertEqual(self.synth().headers["X-Favilium-Archive"],"saved")
        self.assertEqual(self.staff.get(self.root + "/sample").status_code,404)
        self.assertEqual(len(self.staff.get(self.root + "/speech").json()["items"]),1)

    def test_archive_cross_device_and_delete(self):
        self.enroll(True)
        self.login()
        self.assertEqual(self.synth().headers["X-Favilium-Archive"],"saved")
        sample = self.staff.get(self.root + "/sample")
        self.assertEqual(sample.content,studio.recording())
        partial = self.staff.get(self.root + "/sample", headers={"Range":"bytes=0-1"})
        self.assertEqual((partial.status_code,partial.content),(206,b"RI"))
        self.assertEqual(self.staff.get(self.root + "/sample",headers={"Range":"bytes=99000000-"}).status_code,416)
        self.assertEqual(self.browser.post("/api/workspace/next",headers=self.studio_headers).status_code,204)
        self.assertEqual(self.open_workspace()["voice_state"],"empty")
        self.assertEqual(self.staff.post(self.root + "/speech",json={"text":"연구자가 다른 기기에서 만든 문장."}).headers["X-Favilium-Archive"],"saved")
        row, = self.staff.get("/api/research/voices").json()["items"]
        self.assertTrue(row["has_sample"]); self.assertEqual(row["speech_count"],2)
        self.assertNotIn("session_id",row); self.assertNotIn("voice_id",row)
        item = self.staff.get(self.root + "/speech").json()["items"][0]
        self.assertEqual(item["text_content"], "연구자가 다른 기기에서 만든 문장.")
        file = self.root + "/speech/" + item["id"]
        audio = self.staff.get(file + "?download=true")
        self.assertEqual(audio.content, self.upstream.audio)
        self.assertIn("attachment", audio.headers["Content-Disposition"])
        self.assertEqual(self.browser.get(file).status_code,401)
        self.assertEqual(self.staff.get("/api/research/voices/another/speech/" + item["id"]).status_code,404)
        self.upstream.fail_delete = True
        self.assertEqual(self.staff.delete(self.root).status_code,502)
        self.assertEqual(self.staff.get("/api/research/voices").json()["items"][0]["state"],"deleting")
        self.assertEqual(self.staff.get(file).status_code, 409)
        self.upstream.fail_delete = False
        self.assertEqual(self.staff.delete(self.root).status_code,204)
        self.assertFalse(self.upstream.voices)
        self.assertEqual(self.staff.get(file).status_code,404)
        self.assertEqual(self.staff.get(self.root + "/sample").status_code,404)
        self.assertEqual(self.staff.get("/api/research/voices").json()["items"],[])

    def test_studio_deletion_and_archive_failure_preserve_consistency(self):
        self.enroll(True)
        self.login()
        with patch("kof5_tts.research_store.SQLiteArchive.save_speech",side_effect=StoreUnavailable()):
            audio = self.synth()
            self.assertEqual(audio.headers["X-Favilium-Archive"],"failed")
            self.assertEqual(audio.content,self.upstream.audio)
        self.assertEqual(self.browser.delete("/api/voice",headers=self.studio_headers).status_code,200)
        self.assertEqual(self.staff.get(self.root + "/sample").status_code,404)
        self.assertEqual(self.staff.get("/api/research/voices").json()["items"],[])

    def test_pagination_search_and_proof_link(self):
        self.login()
        store=voice_only.get_store()
        for i in range(PAGE_SIZE+2):
            store.create(str(i), f"{i:024x}")
        first=self.staff.get("/api/research/voices").json()
        self.assertTrue(first["has_more"]); self.assertEqual(len(first["items"]),PAGE_SIZE)
        self.assertEqual(len(self.staff.get(f"/api/research/voices?offset={PAGE_SIZE}").json()["items"]),2)
        self.assertEqual(len(self.staff.get("/api/research/voices?search=0f").json()["items"]),1)
        with patch.dict(os.environ,{"FAVILIUM_SUPABASE_URL":"https://trial.supabase.co"}):
            target="https://trial.supabase.co/auth/v1/verify?token="+"a"*56+"&type=magiclink"
            self.assertEqual(research.email_proof("a",target),{"token_hash":"a"*56,"type":"email"})
            for url in (target.replace("trial.supabase.co","example.invalid"),target.replace("magiclink","recovery")):
                with self.assertRaises(research.HTTPException):
                    research.email_proof("a",url)
