"""Loopback-only synthetic text API for the first companion flow."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from kof5_tts.companion import ConversationSession, Fact, orientation_date, relevant_facts

SYNTHETIC_PATIENT = "synthetic_patient"
FAMILY_FACT = Fact(
    SYNTHETIC_PATIENT,
    "family_context",
    "travel",
    "2024년 5월에 수민과 제주도 여행을 갔고 흑돼지를 좋아했다.",
    "guardian",
    datetime(2026, 9, 14, tzinfo=timezone.utc),
)

app = FastAPI(title="Synthetic Familiar Voice MVP", docs_url=None, redoc_url=None)
# ponytail: one in-memory synthetic patient; add authenticated persistence and per-patient serialization before real data.
app.state.sessions = {}


class SpeechTurn(BaseModel):
    transcript: str = Field(min_length=1, max_length=500)
    label: Literal["DIRECTED", "AMBIENT", "UNCERTAIN"]


def _patient(patient_id: str) -> None:
    if patient_id != SYNTHETIC_PATIENT:
        raise HTTPException(status_code=404, detail="synthetic patient only")


def _reply(event: str, transcript: str, now: datetime) -> str | None:
    if event in {"discarded", "closed", "patient_dissent"}:
        return None
    if event in {"auxiliary_alert_candidate", "barge_in_risk_candidate"}:
        return "의료진의 도움이 필요한 상황일 수 있어요. 기존 호출 버튼을 이용해주세요."
    if transcript.strip().startswith("수민아"):
        return "응, 왜?"
    if any(word in transcript for word in ("며칠", "날짜")):
        return orientation_date(now)
    facts = relevant_facts([FAMILY_FACT], SYNTHETIC_PATIENT, "family_context", transcript, now)
    return facts[0].content if facts else "지금 확인된 정보가 없어서 모르겠어."


def _route(session: ConversationSession, speech: SpeechTurn, now: datetime) -> dict[str, str | None]:
    event = session.hear(speech.transcript, speech.label, now)
    return {"event": event, "state": session.state, "text": _reply(event, speech.transcript, now)}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "synthetic_text_only"}


@app.post("/patients/{patient_id}/conversation/start")
def start(patient_id: str, speech: SpeechTurn) -> dict[str, str | None]:
    _patient(patient_id)
    now = datetime.now(timezone.utc)
    existing = app.state.sessions.get(patient_id)
    if existing is not None and existing.proactive_paused:
        raise HTTPException(status_code=409, detail="patient dissent remains active")
    if existing is not None:
        existing.expire(now)
    if existing is not None and existing.state != "IDLE":
        raise HTTPException(status_code=409, detail="conversation already active")
    session = ConversationSession()
    app.state.sessions[patient_id] = session
    return _route(session, speech, now)


@app.post("/patients/{patient_id}/conversation/turn")
def turn(patient_id: str, speech: SpeechTurn) -> dict[str, str | None]:
    _patient(patient_id)
    session = app.state.sessions.get(patient_id)
    if session is None:
        raise HTTPException(status_code=404, detail="conversation not started")
    now = datetime.now(timezone.utc)
    session.expire(now)
    return _route(session, speech, now)


@app.post("/patients/{patient_id}/conversation/end")
def end(patient_id: str) -> dict[str, str]:
    _patient(patient_id)
    session = app.state.sessions.get(patient_id)
    if session is None:
        raise HTTPException(status_code=404, detail="conversation not started")
    session.stop()
    return {"event": "closed", "state": session.state}
