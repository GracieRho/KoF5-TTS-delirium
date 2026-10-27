"""합성 연구 경로의 opt-in·출처·입력·비용 경계를 검사한다."""

import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from kof5_tts.api import app


class ResearchApiTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {"KOF5_RESEARCH_ENABLED": "1"}, clear=True)
        env.start()
        self.addCleanup(env.stop)
        network = patch("socket.socket.connect", side_effect=AssertionError("No network allowed"))
        network.start()
        self.addCleanup(network.stop)
        self.client = TestClient(app, base_url="http://127.0.0.1:8767")
        self.addCleanup(self.client.close)

    def test_offline_catalog_and_interview_without_login_or_provider(self):
        catalog = self.client.get("/research-api/catalog")
        self.assertEqual(catalog.status_code, 200)
        self.assertEqual(catalog.headers["Cache-Control"], "no-store")
        self.assertTrue(catalog.json()["cases"])
        response = self.client.post("/research-api/interview", json={"budget": 1})
        self.assertEqual(response.status_code, 200)
        question = response.json()["next_question"]
        result = self.client.post("/research-api/interview", json={"budget": 1, "answers": [{
            "question_id": question["id"], "option_id": question["options"][0]["id"],
        }]})
        self.assertEqual(result.status_code, 200)
        self.assertTrue(result.json()["done"])
        self.assertTrue(result.json()["heldout_predictions"])

    def test_preview_accepts_only_bundled_cases_and_typed_style(self):
        case = self.client.get("/research-api/catalog").json()["cases"][0]
        response = self.client.post("/research-api/preview", json={"case_id": case["id"]})
        self.assertEqual(response.status_code, 200)
        self.assertIn("evidence_ids", response.json())
        self.assertNotIn("expected", response.json())
        self.assertEqual(self.client.post("/research-api/preview", json={"case_id": "unknown"}).status_code, 404)
        for body in [
            {"case_id": case["id"], "evidence": []},
            {"case_id": case["id"], "style": {"address": "arbitrary patient name"}},
        ]:
            self.assertEqual(self.client.post("/research-api/preview", json=body).status_code, 422)

    def test_default_off_vercel_remote_client_host_and_cross_origin_blocked(self):
        for env in [{"KOF5_RESEARCH_ENABLED": "0"}, {"VERCEL": "1"}]:
            with patch.dict(os.environ, env):
                for path in ["/research", "/research-api/catalog"]:
                    self.assertEqual(self.client.get(path).status_code, 403)
        for headers in [{"Host": "external.example"}, {"Origin": "https://external.example"}]:
            self.assertEqual(self.client.get("/research-api/catalog", headers=headers).status_code, 403)
        with TestClient(app, base_url="http://127.0.0.1", client=("192.0.2.1", 1234)) as remote:
            self.assertEqual(remote.get("/research-api/catalog").status_code, 403)

    def test_invalid_replays_bounds_and_oversized_body_fail_closed(self):
        for body in [
            {"budget": 0}, {"budget": 9}, {"budget": True}, {"seed": -1},
            {"strategy": "other"}, {"answers": [{"question_id": "unknown", "option_id": "a"}]},
        ]:
            self.assertEqual(self.client.post("/research-api/interview", json=body).status_code, 422)
        response = self.client.post("/research-api/interview", content=b" " * 16_385,
                                    headers={"Content-Type": "application/json"})
        self.assertEqual(response.status_code, 413)


if __name__ == "__main__":
    unittest.main()
