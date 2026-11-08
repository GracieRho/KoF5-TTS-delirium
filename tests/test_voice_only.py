"""Voice workspace integration tests. No network, credentials or human recordings."""
import io
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch
import wave

import httpx
from fastapi.testclient import TestClient

from app import app
from kof5_tts import voice_only as api

ORIGIN = "https://favilium.test"
CODE = "synthetic-test-access-code"


def recording(seconds=10):
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        wav.writeframes(b"\0\0" * (16000 * seconds))
    return output.getvalue()


class Provider:
    def __init__(self):
        self.voices = {}
        self.calls = []
        self.verify = False
        self.timeout_after_create = False
        self.reject_sample = False
        self.fail_delete = False
        self.audio = b"\xff\xfb\x90\x00test"
        self.audio_type = "audio/mpeg"

    def handle(self, request):
        method, path = request.method, request.url.path
        self.calls.append((method, path))
        if request.headers.get("xi-api-key") != "synthetic-key":
            raise AssertionError("provider request has no server key")
        if path == "/v1/voices/add" and method == "POST":
            if self.reject_sample:
                return httpx.Response(422)
            self.sample_content = request.read()
            name = re.search(rb'name="name"\r\n\r\n([^\r]+)', self.sample_content).group(1).decode()
            self.voices["mockVoiceId"] = {"name": name, "voice_id": "mockVoiceId",
                                          "voice_verification": {"requires_verification": self.verify}}
            if self.timeout_after_create:
                raise httpx.ReadTimeout("mock timeout")
            return httpx.Response(200, json={"voice_id": "mockVoiceId", "requires_verification": self.verify})
        if path == "/v2/voices" and method == "GET":
            return httpx.Response(200, json={"voices": list(self.voices.values()), "has_more": False})
        if path == "/v1/voices/mockVoiceId" and method == "GET":
            return httpx.Response(200, json=self.voices["mockVoiceId"])
        if path == "/v1/voices/mockVoiceId" and method == "DELETE":
            if self.fail_delete:
                return httpx.Response(503)
            if self.voices.pop("mockVoiceId", None) is None:
                return httpx.Response(404)
            return httpx.Response(200, json={"status": "ok"})
        if path == "/v1/text-to-speech/mockVoiceId" and method == "POST":
            self.speech_payload = json.loads(request.read())
            return httpx.Response(200, content=self.audio, headers={"Content-Type": self.audio_type})
        raise AssertionError(f"unexpected call {method} {path}")


class VoiceAPITest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        env = patch.dict(os.environ, {"FAVILIUM_ACCESS_CODE": CODE, "ELEVENLABS_API_KEY": "synthetic-key",
                                      "FAVILIUM_DB_PATH": str(Path(directory.name) / "store.db"),
                                      "FAVILIUM_SESSION_SECRET": "a" * 36,
                                      "FAVILIUM_SUPABASE_URL": "", "FAVILIUM_SUPABASE_SERVICE_KEY": "",
                                      "VERCEL": ""})
        env.start()
        self.addCleanup(env.stop)
        self.upstream = Provider()
        client_factory = patch.object(api, "provider", lambda: httpx.Client(
            base_url=api.API, headers={"xi-api-key": "synthetic-key"},
            transport=httpx.MockTransport(self.upstream.handle)))
        client_factory.start()
        self.addCleanup(client_factory.stop)
        self.browser = self.new_browser()

    def new_browser(self):
        browser = TestClient(app, base_url=ORIGIN, headers={"Origin": ORIGIN})
        self.addCleanup(browser.close)
        return browser

    def login(self, browser=None):
        response = (browser or self.browser).post("/api/login", json={"code": CODE})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def enroll(self, sample=None, consent="yes"):
        return self.browser.post("/api/voice", content=recording() if sample is None else sample,
                                 headers={"Content-Type": "audio/wav", "X-Voice-Consent": consent})

    def test_full_flow_isolated_sessions_verbatim_text_delete_and_logout(self):
        self.assertFalse(self.browser.get("/api/status").json()["authenticated"])
        self.assertEqual(self.enroll().status_code, 401)
        self.login()
        dirty = recording() + b"private trailing metadata"
        created = self.enroll(dirty)
        self.assertEqual(created.status_code, 200, created.text)
        self.assertEqual(created.json()["voice_state"], "ready")
        self.assertNotIn("voice_id", created.json())
        reference = created.json()["reference"]
        headers = {"X-Voice-Reference": reference}
        self.assertNotIn(b"private trailing metadata", self.upstream.sample_content)
        self.assertIn(b'name="files"', self.upstream.sample_content)
        self.assertEqual(self.enroll().status_code, 409)
        text = "  보호자 목소리로 전하는 한 문장.  "
        audio = self.browser.post("/api/speech", json={"text": text}, headers=headers)
        self.assertEqual(audio.content, self.upstream.audio)
        self.assertEqual(audio.headers["Content-Type"], "audio/mpeg")
        self.assertIn("no-store", audio.headers["Cache-Control"])
        self.assertEqual(self.upstream.speech_payload, {"text": text, "model_id": "eleven_multilingual_v2"})
        other = self.new_browser()
        self.assertEqual(self.login(other)["voice_state"], "empty")
        self.assertEqual(other.post("/api/speech", json={"text": text}, headers=headers).status_code, 409)
        self.assertEqual(self.browser.delete("/api/voice", headers={"X-Voice-Reference": "old"}).status_code, 409)
        self.assertEqual(self.browser.post("/api/speech", json={"text": text}).status_code, 409)
        self.browser.post("/api/logout")
        self.assertEqual(self.browser.post("/api/speech", json={"text": text}, headers=headers).status_code, 401)
        self.assertEqual(self.login()["reference"], reference)
        self.assertEqual(self.browser.delete("/api/voice", headers=headers).json()["voice_state"], "empty")
        self.assertFalse(self.upstream.voices)

    def test_bounds_consent_csrf_and_removed_routes(self):
        self.assertEqual(self.browser.post("/api/login", json={"code": CODE}, headers={"Origin": "https://other"}).status_code, 403)
        self.assertEqual(self.browser.post("/api/login", json={"code": "wrong"}).status_code, 401)
        self.login()
        self.assertEqual(self.enroll(consent="no").status_code, 403)
        self.assertEqual(self.enroll(sample=recording(9)).status_code, 422)
        self.assertEqual(self.enroll(sample=recording()[:-2]).status_code, 422)
        self.assertEqual(self.enroll(sample=b"plain").status_code, 422)
        self.assertEqual(self.enroll(sample=b"X" * (api.MAX_WAV + 1)).status_code, 413)
        for text in ("  ", "가" * 1001):
            self.assertEqual(self.browser.post("/api/speech", json={"text": text}).status_code, 422)
        for path in ("/hospital", "/guardian", "/local-studio/state", "/docs", "/openapi.json"):
            self.assertEqual(self.browser.get(path).status_code, 404)
        self.assertFalse(self.upstream.calls)

    def test_provider_rejection_permits_corrected_sample(self):
        self.login()
        self.upstream.reject_sample = True
        self.assertEqual(self.enroll().status_code, 422)
        self.assertEqual(self.browser.get("/api/status").json()["voice_state"], "empty")
        self.upstream.reject_sample = False
        self.assertEqual(self.enroll().json()["voice_state"], "ready")

    def test_uncertain_create_recovery_and_delete_retry(self):
        self.login()
        self.upstream.timeout_after_create = True
        self.assertEqual(self.enroll().status_code, 502)
        self.assertEqual(self.enroll().status_code, 409)
        result = self.browser.get("/api/status").json()
        self.assertEqual(result["voice_state"], "ready")
        self.assertEqual(self.upstream.calls.count(("POST", "/v1/voices/add")), 1)
        headers = {"X-Voice-Reference": result["reference"]}
        self.upstream.fail_delete = True
        self.assertEqual(self.browser.delete("/api/voice", headers=headers).status_code, 502)
        self.assertEqual(self.browser.get("/api/status").json()["voice_state"], "deleting")
        self.assertEqual(self.browser.post("/api/speech", json={"text": "글"}, headers=headers).status_code, 409)
        self.upstream.fail_delete = False
        self.upstream.voices.clear()  # Provider accepted the DELETE but its response was lost.
        self.assertEqual(self.browser.delete("/api/voice", headers=headers).json()["voice_state"], "empty")

    def test_speech_rejects_unexpected_media_and_supports_binary_mp3(self):
        self.login()
        ref = self.enroll().json()["reference"]
        def speech():
            return self.browser.post("/api/speech", json={"text": "안녕하세요."},
                                     headers={"X-Voice-Reference": ref})

        self.upstream.audio_type = "application/octet-stream"
        self.assertEqual(speech().content, self.upstream.audio)
        self.upstream.audio_type = "Audio/Mpeg; charset=utf-8"
        self.assertEqual(speech().content, self.upstream.audio)
        self.upstream.audio_type = "application/json"
        self.assertEqual(speech().status_code, 502)
        self.upstream.audio_type = "audio/mpeg"
        self.upstream.audio = b'{"error": "oops"}'
        self.assertEqual(speech().status_code, 502)

    def test_verification_stays_blocked_until_verified(self):
        self.login()
        self.upstream.verify = True
        result = self.enroll().json()
        self.assertEqual(result["voice_state"], "verification")
        headers = {"X-Voice-Reference": result["reference"]}
        self.assertEqual(self.browser.post("/api/speech", json={"text": "글"}, headers=headers).status_code, 409)
        self.assertEqual(self.browser.get("/api/status").json()["voice_state"], "verification")
        self.upstream.voices["mockVoiceId"]["voice_verification"]["is_verified"] = True
        self.assertEqual(self.browser.get("/api/status").json()["voice_state"], "ready")

    def test_missing_access_code_and_cookie_tampering(self):
        with patch.dict(os.environ, {"FAVILIUM_ACCESS_CODE": "bad"}):
            self.assertFalse(self.browser.get("/api/status").json()["configured"])
            self.assertEqual(self.browser.post("/api/login", json={"code": "bad"}).status_code, 503)
        self.login()
        cookie = self.browser.cookies.get(api.LOGIN)
        self.browser.cookies.clear()
        self.browser.cookies.set(api.LOGIN, cookie[:-1] + ("1" if cookie[-1] != "1" else "2"))
        self.assertFalse(self.browser.get("/api/status").json()["authenticated"])
        self.assertEqual(self.enroll().status_code, 401)


if __name__ == "__main__":
    unittest.main()
