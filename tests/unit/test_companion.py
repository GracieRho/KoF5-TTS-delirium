from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.companion import ConversationSession  # noqa: E402


class ConversationSessionTests(unittest.TestCase):
    def test_synthetic_patient_ambient_barge_in_timeout_and_dissent(self) -> None:
        now = datetime(2026, 9, 15, 15, 20, tzinfo=timezone.utc)
        session = ConversationSession()
        self.assertEqual(session.hear("오늘 오후 뉴스입니다", "AMBIENT", now), "discarded")
        self.assertEqual(session.state, "IDLE")
        self.assertEqual(session.hear("오늘 몇 시지", "UNCERTAIN", now), "discarded")
        self.assertEqual(session.hear("이거 꺼", "UNCERTAIN", now), "discarded")
        self.assertFalse(session.proactive_paused)
        self.assertEqual(session.hear("수민아?", "DIRECTED", now), "turn")
        session.speaking()
        self.assertEqual(session.hear("오늘이 며칠이야?", "UNCERTAIN", now), "barge_in")
        self.assertEqual(session.hear("응", "UNCERTAIN", now), "turn")
        self.assertFalse(session.expire(now + timedelta(seconds=44)))
        self.assertTrue(session.expire(now + timedelta(seconds=45)))
        self.assertTrue(session.start_scheduled(now))
        self.assertEqual(session.hear("이거 꺼", "DIRECTED", now), "patient_dissent")
        self.assertEqual(session.state, "IDLE")
        self.assertFalse(session.start_scheduled(now))
        self.assertEqual(session.hear("수민아?", "DIRECTED", now), "discarded")


if __name__ == "__main__":
    unittest.main()
