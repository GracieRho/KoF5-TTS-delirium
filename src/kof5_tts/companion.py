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
RISK_PHRASES = ("숨을 못 쉬", "숨이 너무 차", "가슴이 아파", "넘어졌", "너무 어지러워", "살려줘")
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


def orientation_time(now: datetime, zone: str = "Asia/Seoul") -> str:
    """Use the same trusted clock for a short Korean time answer."""
    _require_aware(now)
    local = now.astimezone(ZoneInfo(zone))
    period = "오전" if local.hour < 12 else "오후"
    return f"지금은 {period} {local.hour % 12 or 12}시 {local.minute}분이야."


def policy_reply(transcript: str, event: str, now: datetime) -> str | None:
    """Shared deterministic replies that must precede any free-form generation."""
    _require_aware(now)
    if event in {"auxiliary_alert_candidate", "barge_in_risk_candidate"}:
        return "의료진의 도움이 필요한 상황일 수 있어요. 기존 호출 버튼을 이용해주세요."
    if any(word in transcript for word in ("진단", "처방", "무슨 약", "약을 먹", "약 먹어야")) or re.search(
        r"(?:약|퇴원|수술|검사|치료).{0,24}(?:먹어도|해도|받아도|받아야|해야|괜찮아|필요해|좋아)",
        transcript,
    ):
        return "의료 판단은 제가 할 수 없어요. 의료진에게 확인해주세요."
    if any(word in transcript for word in ("너 진짜", "너 수민이야", "실제 수민", "전화한 거", "AI야")):
        return "나는 실제 가족과 통화하는 사람이 아니라 AI 음성 대화 도우미야."
    if re.fullmatch(
        r"(?:수민아[, ]*)?(?:(?:지금|현재)\s*)?(?:시간이?\s*)?몇\s*시(?:야|지|니|예요|인가요|입니까)?[?.! ]*",
        transcript.strip(),
    ):
        return orientation_time(now)
    if re.search(r"몇\s*시에?", transcript):
        return "그 시간은 확인된 정보가 없어서 모르겠어. 의료진이나 보호자에게 확인해주세요."
    if any(word in transcript for word in ("며칠", "날짜")):
        return orientation_date(now)
    if transcript.strip().rstrip(".,!? ") == "수민아":
        return "응, 왜?"
    # ponytail: keyword policy covers only internal synthetic cases; clinical review and measured safety eval precede patient use.
    return None


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
