from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
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
        demo = self.client.get("/demo")
        self.assertEqual(demo.status_code, 200)
        self.assertIn("합성 데이터 전용", demo.text)
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


if __name__ == "__main__":
    unittest.main()
