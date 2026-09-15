from __future__ import annotations

import sys
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.api import app  # noqa: E402


class SyntheticApiTests(unittest.TestCase):
    def setUp(self) -> None:
        app.state.sessions.clear()
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()

    def test_synthetic_first_flow_and_untrusted_requests(self) -> None:
        root = "/patients/synthetic_patient/conversation"
        self.assertEqual(self.client.get("/health").json(), {"status": "synthetic_text_only"})
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
        memory = self.client.post(f"{root}/turn", json={
            "transcript": "제주도 언제 갔었지?", "label": "UNCERTAIN",
        }).json()
        self.assertIn("2024년 5월", memory["text"])
        dissent = self.client.post(f"{root}/turn", json={
            "transcript": "그만해.", "label": "UNCERTAIN",
        }).json()
        self.assertEqual((dissent["event"], dissent["text"]), ("patient_dissent", None))
        self.assertEqual(self.client.post(f"{root}/end").json()["state"], "IDLE")


if __name__ == "__main__":
    unittest.main()
