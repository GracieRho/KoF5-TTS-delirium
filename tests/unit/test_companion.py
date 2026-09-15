from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.companion import (  # noqa: E402
    ConversationSession,
    Fact,
    orientation_date,
    relevant_facts,
)


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
        session.speaking()
        session.finished_speaking(now)
        self.assertEqual(session.state, "ACTIVE_LISTENING")
        self.assertEqual(session.hear("응", "UNCERTAIN", now), "turn")
        self.assertFalse(session.expire(now + timedelta(seconds=44)))
        self.assertTrue(session.expire(now + timedelta(seconds=45)))
        self.assertTrue(session.start_scheduled(now))
        self.assertEqual(session.hear("이거 꺼", "DIRECTED", now), "patient_dissent")
        self.assertEqual(session.state, "IDLE")
        self.assertFalse(session.start_scheduled(now))
        self.assertEqual(session.hear("수민아?", "DIRECTED", now), "discarded")

    def test_synthetic_family_fact_is_separate_current_and_source_verified(self) -> None:
        now = datetime(2026, 9, 15, 15, 20, tzinfo=timezone.utc)
        family = Fact(
            "synthetic_patient", "family_context", "travel",
            "2024년 5월에 수민과 제주도 여행을 갔고 흑돼지를 좋아했다.",
            "guardian", now - timedelta(days=1),
        )
        stale = Fact(
            "synthetic_patient", "family_context", "recent_event",
            "수민은 어제 제주도에 있었다.", "guardian", now - timedelta(days=3),
            now - timedelta(days=2),
        )
        hospital = Fact(
            "synthetic_patient", "hospital_context", "scheduled_exam",
            "오늘 오후 4시에 CT 촬영 예정입니다.", "hospital_staff", now,
        )
        facts = [family, stale, hospital]
        self.assertEqual(
            relevant_facts(facts, "synthetic_patient", "family_context", "제주도 언제 갔었지?", now),
            [family],
        )
        self.assertEqual(
            relevant_facts(facts, "synthetic_patient", "hospital_context", "CT는 언제야?", now),
            [hospital],
        )
        self.assertEqual(
            relevant_facts(facts, "other_patient", "family_context", "제주도", now), [],
        )
        self.assertEqual(
            relevant_facts(facts, "synthetic_patient", "family_context", "좋아하는 음악", now), [],
        )
        with self.assertRaises(ValueError):
            Fact("synthetic_patient", "hospital_context", "room", "301호", "guardian", now)
        with self.assertRaises(ValueError):
            Fact("synthetic_patient", "family_context", "travel", "제주도", "guardian",
                 datetime(2026, 9, 15))
        self.assertEqual(orientation_date(datetime(2026, 9, 15, tzinfo=timezone.utc)),
                         "오늘은 9월 15일 화요일이야.")
        self.assertEqual(orientation_date(datetime(2026, 9, 14, 16, tzinfo=timezone.utc)),
                         "오늘은 9월 15일 화요일이야.")


if __name__ == "__main__":
    unittest.main()
