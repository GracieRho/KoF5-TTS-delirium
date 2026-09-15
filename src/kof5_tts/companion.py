"""Synthetic conversation-state core; audio and provider integration come later."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
import re
from zoneinfo import ZoneInfo


VALID_LABELS = {"DIRECTED", "AMBIENT", "UNCERTAIN"}
# ponytail: labels come from a later activation layer; add scored STT/context signals after measured false activations.
DISSENT_PHRASES = ("이거 꺼", "말 걸지 마", "대화 그만", "그만해")
END_PHRASES = ("나 좀 잘게", "이제 됐다", "나중에 얘기하자")
RISK_PHRASES = ("숨을 못 쉬", "숨이 너무 차", "가슴이 아파", "넘어졌", "살려줘")
WEEKDAYS = ("월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일")


def _require_aware(now: datetime) -> None:
    if now.utcoffset() is None:
        raise ValueError("time must include a timezone")


@dataclass(frozen=True)
class Fact:
    patient_id: str
    namespace: str
    category: str
    content: str
    source_type: str
    verified_at: datetime
    valid_until: datetime | None = None

    def __post_init__(self) -> None:
        sources = {"family_context": "guardian", "hospital_context": "hospital_staff"}
        if self.namespace not in sources or self.source_type != sources[self.namespace]:
            raise ValueError("fact namespace and source must match")
        if not self.patient_id or not self.category or not self.content.strip():
            raise ValueError("fact patient, category and content are required")
        if self.verified_at.utcoffset() is None or (
            self.valid_until is not None and self.valid_until.utcoffset() is None
        ):
            raise ValueError("fact timestamps must include a timezone")
        if self.valid_until is not None and self.valid_until < self.verified_at:
            raise ValueError("fact validity cannot end before verification")


def relevant_facts(
    facts: list[Fact], patient_id: str, namespace: str, question: str, now: datetime
) -> list[Fact]:
    """Return verified, current facts from one namespace only."""
    if namespace not in {"family_context", "hospital_context"}:
        raise ValueError("unknown fact namespace")
    _require_aware(now)
    tokens = [
        token[:-1] if len(token) > 2 and token[-1] in "은는이가을를" else token
        for token in re.findall(r"[가-힣A-Za-z0-9]{2,}", question)
    ]
    ranked = []
    for fact in facts:
        if (
            fact.patient_id != patient_id
            or fact.namespace != namespace
            or fact.category == "avoid_topic"
            or fact.verified_at > now
            or (fact.valid_until is not None and fact.valid_until < now)
        ):
            continue
        score = sum(token in fact.content for token in tokens)
        if score:
            ranked.append((score, fact.verified_at, fact))
    # ponytail: substring search suits a few synthetic facts; use measured retrieval quality before adding vectors.
    return [fact for _, _, fact in sorted(ranked, key=lambda row: (row[0], row[1]), reverse=True)]


def orientation_date(now: datetime, zone: str = "Asia/Seoul") -> str:
    """Use a trusted local clock instead of asking an LLM for today's date."""
    _require_aware(now)
    local = now.astimezone(ZoneInfo(zone))
    return f"오늘은 {local.month}월 {local.day}일 {WEEKDAYS[local.weekday()]}이야."


@dataclass(frozen=True)
class HospitalMessage:
    patient_id: str
    text: str
    approved_by_staff_id: str
    due_at: datetime

    def __post_init__(self) -> None:
        if not self.patient_id or not self.text.strip() or not self.approved_by_staff_id:
            raise ValueError("hospital message requires patient, text and staff approval")
        if self.due_at.utcoffset() is None:
            raise ValueError("hospital message due time must include a timezone")


def due_hospital_message(
    session: ConversationSession, message: HospitalMessage, patient_id: str, now: datetime
) -> str | None:
    """Start delivery only when due and return the approved source text unchanged."""
    _require_aware(now)
    if message.patient_id != patient_id:
        raise ValueError("hospital message belongs to another patient")
    if now < message.due_at or not session.start_scheduled(now):
        return None
    return message.text


@dataclass
class ConversationSession:
    state: str = "IDLE"
    last_activity: datetime | None = None
    proactive_paused: bool = False

    def hear(self, transcript: str, label: str, now: datetime) -> str:
        """Return a routing event without retaining discarded ambient speech."""
        _require_aware(now)
        if label not in VALID_LABELS:
            raise ValueError(f"unknown activation label: {label}")
        if label == "AMBIENT" or not transcript.strip() or self.proactive_paused:
            return "discarded"
        if self.state == "IDLE" and label != "DIRECTED":
            return "discarded"

        speech = transcript.strip()
        if any(phrase in speech for phrase in DISSENT_PHRASES) or speech.rstrip(".!? ") == "싫어":
            self.proactive_paused = True
            self.stop()
            return "patient_dissent"
        if any(phrase in speech for phrase in END_PHRASES):
            self.stop()
            return "closed"
        was_speaking = self.state == "SPEAKING"
        self.state = "ACTIVE_LISTENING"
        self.last_activity = now
        # ponytail: keywords only flag an auxiliary candidate; add clinical review of recall before any alert pathway.
        if any(phrase in speech for phrase in RISK_PHRASES):
            return "barge_in_risk_candidate" if was_speaking else "auxiliary_alert_candidate"
        return "barge_in" if was_speaking else "turn"

    def start_scheduled(self, now: datetime) -> bool:
        _require_aware(now)
        if self.proactive_paused or self.state != "IDLE":
            return False
        self.state = "ACTIVE_LISTENING"
        self.last_activity = now
        return True

    def speaking(self) -> None:
        if self.state != "ACTIVE_LISTENING":
            raise ValueError("cannot speak outside an active conversation")
        self.state = "SPEAKING"

    def finished_speaking(self, now: datetime) -> None:
        _require_aware(now)
        if self.state != "SPEAKING":
            raise ValueError("cannot finish speech that is not playing")
        self.state = "ACTIVE_LISTENING"
        self.last_activity = now

    def expire(self, now: datetime, silence_seconds: int = 45) -> bool:
        _require_aware(now)
        if silence_seconds <= 0:
            raise ValueError("silence timeout must be positive")
        if self.last_activity is None or self.state != "ACTIVE_LISTENING":
            return False
        if now - self.last_activity < timedelta(seconds=silence_seconds):
            return False
        self.stop()
        return True

    def stop(self) -> None:
        self.state = "IDLE"
        self.last_activity = None
