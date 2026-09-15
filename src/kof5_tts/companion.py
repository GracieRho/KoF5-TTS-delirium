"""Synthetic conversation-state core; audio and provider integration come later."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta


VALID_LABELS = {"DIRECTED", "AMBIENT", "UNCERTAIN"}
# ponytail: labels come from a later activation layer; add scored STT/context signals after measured false activations.
DISSENT_PHRASES = ("이거 꺼", "말 걸지 마", "대화 그만")
END_PHRASES = ("나 좀 잘게", "이제 됐다", "나중에 얘기하자")


@dataclass
class ConversationSession:
    state: str = "IDLE"
    last_activity: datetime | None = None
    proactive_paused: bool = False

    def hear(self, transcript: str, label: str, now: datetime) -> str:
        """Return a routing event without retaining discarded ambient speech."""
        if label not in VALID_LABELS:
            raise ValueError(f"unknown activation label: {label}")
        if label == "AMBIENT" or not transcript.strip() or self.proactive_paused:
            return "discarded"
        if self.state == "IDLE" and label != "DIRECTED":
            return "discarded"

        speech = transcript.strip()
        if any(phrase in speech for phrase in DISSENT_PHRASES):
            self.proactive_paused = True
            self.stop()
            return "patient_dissent"
        if any(phrase in speech for phrase in END_PHRASES):
            self.stop()
            return "closed"
        was_speaking = self.state == "SPEAKING"
        self.state = "ACTIVE_LISTENING"
        self.last_activity = now
        return "barge_in" if was_speaking else "turn"

    def start_scheduled(self, now: datetime) -> bool:
        if self.proactive_paused or self.state != "IDLE":
            return False
        self.state = "ACTIVE_LISTENING"
        self.last_activity = now
        return True

    def speaking(self) -> None:
        if self.state != "ACTIVE_LISTENING":
            raise ValueError("cannot speak outside an active conversation")
        self.state = "SPEAKING"

    def expire(self, now: datetime, silence_seconds: int = 45) -> bool:
        if self.last_activity is None or self.state == "IDLE":
            return False
        if now - self.last_activity < timedelta(seconds=silence_seconds):
            return False
        self.stop()
        return True

    def stop(self) -> None:
        self.state = "IDLE"
        self.last_activity = None
