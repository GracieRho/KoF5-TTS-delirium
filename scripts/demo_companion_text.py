"""Run the PRD's first dialogue with synthetic text only; no audio or cloud calls."""

from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import _bootstrap  # noqa: F401
from kof5_tts.companion import ConversationSession, Fact, orientation_date, relevant_facts


def main() -> None:
    now = datetime(2026, 9, 15, 15, 20, tzinfo=ZoneInfo("Asia/Seoul"))
    patient_id = "synthetic_patient"
    family = Fact(
        patient_id, "family_context", "travel",
        "2024년 5월에 수민과 제주도 여행을 갔고 흑돼지를 좋아했다.",
        "guardian", now - timedelta(days=1),
    )
    session = ConversationSession()
    assert session.hear("TV: 오늘 오후 뉴스입니다", "AMBIENT", now) == "discarded"
    assert session.hear("수민아?", "DIRECTED", now) == "turn"
    print("환자: 수민아?")
    print("합성 응답: 응, 왜?")
    session.speaking()
    session.finished_speaking(now)

    assert session.hear("오늘이 며칠이야?", "UNCERTAIN", now) == "turn"
    print("환자: 오늘이 며칠이야?")
    print("합성 응답:", orientation_date(now))
    session.speaking()
    session.finished_speaking(now)

    question = "우리 제주도 언제 갔었지?"
    assert session.hear(question, "UNCERTAIN", now) == "turn"
    known = relevant_facts([family], patient_id, "family_context", question, now)
    assert known == [family]
    print("환자:", question)
    print("합성 응답:", known[0].content)
    assert session.expire(now + timedelta(seconds=45))
    assert session.state == "IDLE"


if __name__ == "__main__":
    main()
