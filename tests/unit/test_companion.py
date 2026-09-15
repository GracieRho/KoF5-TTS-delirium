from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from kof5_tts.companion import (  # noqa: E402
    ConversationSession,
    Fact,
    HospitalMessage,
    due_hospital_message,
    orientation_date,
    orientation_time,
    policy_reply,
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
        self.assertEqual(orientation_time(datetime(2026, 9, 15, 6, 20, tzinfo=timezone.utc)),
                         "지금은 오후 3시 20분이야.")
        self.assertEqual(policy_reply("수민아 지금 몇 시야?", "turn",
                                      datetime(2026, 9, 15, 6, 20, tzinfo=timezone.utc)),
                         "지금은 오후 3시 20분이야.")
        for unknown_time in (
            "CT 검사는 몇 시야?", "수민이는 몇 시에 와?", "내일 몇 시에 퇴원해?",
            "지금 몇 시에 검사하러 가야 해?", "간호사가 지금 몇 시에 검사한다고 했지?",
        ):
            self.assertNotIn(
                "지금은 오후", policy_reply(unknown_time, "turn",
                                           datetime(2026, 9, 15, 6, 20, tzinfo=timezone.utc)) or "",
            )

    def test_approved_hospital_text_and_risk_event_never_claim_staff_ack(self) -> None:
        now = datetime(2026, 9, 15, 15, 20, tzinfo=ZoneInfo("Asia/Seoul"))
        session = ConversationSession()
        message = HospitalMessage(
            "synthetic_patient", "오늘 오후 4시에 CT 촬영 예정입니다.\n준비해주세요.",
            "synthetic_staff", now + timedelta(minutes=1),
        )
        self.assertIsNone(due_hospital_message(session, message, "synthetic_patient", now))
        with self.assertRaises(ValueError):
            due_hospital_message(session, message, "other_patient", now + timedelta(minutes=1))
        self.assertEqual(
            due_hospital_message(session, message, "synthetic_patient", now + timedelta(minutes=1)),
            message.text,
        )
        self.assertEqual(session.state, "ACTIVE_LISTENING")
        session.speaking()
        self.assertEqual(
            session.hear("숨을 못 쉬겠어", "UNCERTAIN", now + timedelta(minutes=1)),
            "barge_in_risk_candidate",
        )
        self.assertEqual(
            session.hear("너무 어지러워", "UNCERTAIN", now + timedelta(minutes=1)),
            "auxiliary_alert_candidate",
        )
        self.assertFalse(session.proactive_paused)
        with self.assertRaises(ValueError):
            HospitalMessage("synthetic_patient", "CT 일정", "", now)

    def test_risk_synonyms_preempt_other_replies_without_claiming_staff_alert(self) -> None:
        now = datetime(2026, 9, 15, tzinfo=timezone.utc)
        expected = "의료진의 도움이 필요한 상황일 수 있어요. 기존 호출 버튼을 이용해주세요."
        for speech in ("숨이 안 쉬어져", "가슴 통증이 있어, 지금 몇 시야?", "낙상했어"):
            with self.subTest(speech=speech):
                session = ConversationSession()
                self.assertEqual(session.hear(speech, "AMBIENT", now), "discarded")
                event = session.hear(speech, "DIRECTED", now)
                self.assertEqual(event, "auxiliary_alert_candidate")
                self.assertEqual(policy_reply(speech, event, now), expected)
                session.speaking()
                barge_event = session.hear(speech, "UNCERTAIN", now)
                self.assertEqual(barge_event, "barge_in_risk_candidate")
                self.assertEqual(policy_reply(speech, barge_event, now), expected)
                self.assertNotIn("의료진에게 알렸", expected)
                self.assertNotIn("의료진에게 전달", expected)

    def test_clear_dissent_stops_proactive_conversation_but_short_no_does_not(self) -> None:
        now = datetime(2026, 9, 15, tzinfo=timezone.utc)
        for dissent in ("그만해.", "싫어."):
            session = ConversationSession()
            self.assertEqual(session.hear("수민아?", "DIRECTED", now), "turn")
            session.speaking()
            self.assertEqual(session.hear(dissent, "DIRECTED", now), "patient_dissent")
            self.assertEqual(session.state, "IDLE")
            self.assertTrue(session.proactive_paused)
            self.assertFalse(session.start_scheduled(now))

        session = ConversationSession()
        self.assertEqual(session.hear("수민아?", "DIRECTED", now), "turn")
        self.assertEqual(session.hear("아니", "UNCERTAIN", now), "turn")
        self.assertEqual(session.hear("싫어하는 음식은 뭐야?", "UNCERTAIN", now), "turn")
        self.assertFalse(session.proactive_paused)

    def test_medical_decisions_are_blocked_before_hosted_reply(self) -> None:
        now = datetime(2026, 9, 15, tzinfo=timezone.utc)
        for request in ("이 약 먹어도 돼?", "나 지금 퇴원해도 괜찮아?", "수술 받아야 하나?"):
            self.assertEqual(
                policy_reply(request, "turn", now),
                "의료 판단은 제가 할 수 없어요. 의료진에게 확인해주세요.",
            )
        self.assertEqual(policy_reply("수민아", "turn", now), "응, 왜?")

    def test_silence_timeout_starts_after_speech_finishes(self) -> None:
        now = datetime(2026, 9, 15, tzinfo=timezone.utc)
        session = ConversationSession()
        session.hear("수민아?", "DIRECTED", now)
        session.speaking()
        self.assertFalse(session.expire(now + timedelta(seconds=45)))
        self.assertEqual(session.state, "SPEAKING")
        session.finished_speaking(now + timedelta(seconds=46))
        with self.assertRaises(ValueError):
            session.expire(now + timedelta(seconds=46), silence_seconds=0)
        self.assertFalse(session.expire(now + timedelta(seconds=90)))
        self.assertTrue(session.expire(now + timedelta(seconds=91)))

    def test_naive_time_is_rejected_before_session_state_changes(self) -> None:
        aware = datetime(2026, 9, 15, tzinfo=timezone.utc)
        naive = datetime(2026, 9, 15)
        session = ConversationSession()
        with self.assertRaises(ValueError):
            session.hear("수민아?", "DIRECTED", naive)
        with self.assertRaises(ValueError):
            session.start_scheduled(naive)
        self.assertEqual((session.state, session.last_activity), ("IDLE", None))

        session.start_scheduled(aware)
        session.speaking()
        with self.assertRaises(ValueError):
            session.finished_speaking(naive)
        with self.assertRaises(ValueError):
            session.expire(naive)
        self.assertEqual((session.state, session.last_activity), ("SPEAKING", aware))


if __name__ == "__main__":
    unittest.main()
