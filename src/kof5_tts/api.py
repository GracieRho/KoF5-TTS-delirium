"""Loopback-only synthetic text API for the first companion flow."""

from __future__ import annotations

from base64 import b64encode
from datetime import datetime, timezone
from hmac import compare_digest
import os
from pathlib import Path
import re
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from kof5_tts.cloud_prototype import CloudCredentials, run_synthetic_pipeline, validate_short_wav
from kof5_tts.companion import ConversationSession, Fact, policy_reply, relevant_facts

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


@app.get("/demo", include_in_schema=False)
def demo() -> FileResponse:
    return FileResponse(Path(__file__).with_name("synthetic_demo.html"))


@app.get("/demo/hospital", include_in_schema=False)
def hospital_demo() -> FileResponse:
    return FileResponse(Path(__file__).with_name("synthetic_hospital_demo.html"))


@app.get("/demo/guardian", include_in_schema=False)
def guardian_demo() -> FileResponse:
    return FileResponse(Path(__file__).with_name("synthetic_guardian_demo.html"))


@app.get("/guardian", include_in_schema=False)
def guardian_portal() -> FileResponse:
    return FileResponse(Path(__file__).with_name("guardian_portal.html"))


@app.get("/hospital", include_in_schema=False)
def hospital_portal() -> FileResponse:
    return FileResponse(Path(__file__).with_name("hospital_portal.html"))


@app.get("/portal/config", include_in_schema=False)
@app.get("/guardian/config", include_in_schema=False)
def guardian_config() -> dict[str, str]:
    """Public browser configuration; never expose a Supabase secret key."""
    url = os.environ.get("KOF5_SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("KOF5_SUPABASE_PUBLISHABLE_KEY", "")
    project_ref = os.environ.get("KOF5_SUPABASE_PROJECT_REF", "")
    local = url == "http://127.0.0.1:54341" and not os.environ.get("VERCEL")
    remote = (bool(re.fullmatch(r"[a-z0-9]+", project_ref))
              and project_ref != "dqjplezbvtjbsunabxbg"
              and url == f"https://{project_ref}.supabase.co")
    if not (local or remote) or not key.startswith("sb_publishable_"):
        raise HTTPException(status_code=503, detail="전용 Supabase 로그인 연결이 아직 준비되지 않았습니다")
    return {"url": url, "publishable_key": key}


class SpeechTurn(BaseModel):
    transcript: str = Field(min_length=1, max_length=500)
    label: Literal["DIRECTED", "AMBIENT", "UNCERTAIN"]


def _patient(patient_id: str) -> None:
    if patient_id != SYNTHETIC_PATIENT:
        raise HTTPException(status_code=404, detail="합성 환자 ID만 사용할 수 있습니다")


def _reply(event: str, transcript: str, now: datetime) -> str | None:
    if event in {"discarded", "closed", "patient_dissent"}:
        return None
    override = policy_reply(transcript, event, now)
    if override is not None:
        return override
    facts = relevant_facts([FAMILY_FACT], SYNTHETIC_PATIENT, "family_context", transcript, now)
    return facts[0].content if facts else "지금 확인된 정보가 없어서 모르겠어."


def _route(session: ConversationSession, speech: SpeechTurn, now: datetime) -> dict[str, str | None]:
    event = session.hear(speech.transcript, speech.label, now)
    return {"event": event, "state": session.state, "text": _reply(event, speech.transcript, now)}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "synthetic_demo_only"}


@app.post("/internal/synthetic/audio", include_in_schema=False)
async def synthetic_audio(request: Request) -> dict[str, str | None]:
    """Internal Phase-0 WAV→STT→reply→TTS; no real-patient route or storage."""
    token = os.environ.get("KOF5_INTERNAL_DEMO_TOKEN", "")
    if len(token) < 32 or not token.isascii():
        raise HTTPException(status_code=503, detail="내부 오디오 시험이 설정되지 않았습니다")
    supplied_token = request.headers.get("x-internal-demo-token", "")
    if not supplied_token.isascii() or not compare_digest(supplied_token, token):
        raise HTTPException(status_code=401, detail="내부 시험 인증이 필요합니다")
    if request.headers.get("x-synthetic-material") != "confirmed":
        raise HTTPException(status_code=400, detail="합성·자가 시험 자료만 허용합니다")
    if request.headers.get("content-type", "").split(";", 1)[0].lower() != "audio/wav":
        raise HTTPException(status_code=415, detail="WAV 오디오만 허용합니다")
    if not os.environ.get("VOICE_OWNER_CONSENT_RECORD_ID", "").strip():
        raise HTTPException(status_code=503, detail="시험용 음성 소유자 동의 기록이 필요합니다")
    try:
        credentials = CloudCredentials(
            os.environ.get("DEEPGRAM_API_KEY", ""),
            os.environ.get("OPENAI_API_KEY", ""),
            os.environ.get("ELEVENLABS_API_KEY", ""),
            os.environ.get("ELEVENLABS_VOICE_ID", ""),
            True,
        )
    except ValueError as exc:
        raise HTTPException(status_code=503, detail="Hosted 공급자 설정이 필요합니다") from exc
    wav = bytearray()
    async for chunk in request.stream():
        if len(wav) + len(chunk) > 2_000_000:
            raise HTTPException(status_code=413, detail="2 MB 이하의 짧은 WAV만 허용합니다")
        wav.extend(chunk)
    try:
        validate_short_wav(wav)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="짧은 PCM16 WAV가 필요합니다") from exc

    def run() -> tuple[str, str | None, bytes | None]:
        with httpx.Client(timeout=20) as client:
            return run_synthetic_pipeline(client, bytes(wav), FAMILY_FACT.content, credentials)

    try:
        transcript, reply, audio = await run_in_threadpool(run)
    except (httpx.HTTPError, ValueError):
        raise HTTPException(status_code=502, detail="음성 공급자 처리가 실패했습니다") from None
    return {
        "transcript": transcript,
        "reply": reply,
        "audio_mp3_base64": b64encode(audio).decode("ascii") if audio else None,
    }


@app.post("/patients/{patient_id}/conversation/start")
def start(patient_id: str, speech: SpeechTurn) -> dict[str, str | None]:
    _patient(patient_id)
    now = datetime.now(timezone.utc)
    existing = app.state.sessions.get(patient_id)
    if existing is not None and existing.proactive_paused:
        raise HTTPException(status_code=409, detail="환자 거부 상태가 유지되어 재시작할 수 없습니다")
    if existing is not None:
        existing.expire(now)
    if existing is not None and existing.state != "IDLE":
        raise HTTPException(status_code=409, detail="대화가 이미 진행 중입니다")
    session = ConversationSession()
    app.state.sessions[patient_id] = session
    return _route(session, speech, now)


@app.post("/patients/{patient_id}/conversation/turn")
def turn(patient_id: str, speech: SpeechTurn) -> dict[str, str | None]:
    _patient(patient_id)
    session = app.state.sessions.get(patient_id)
    if session is None:
        raise HTTPException(status_code=404, detail="시작된 대화가 없습니다")
    now = datetime.now(timezone.utc)
    session.expire(now)
    return _route(session, speech, now)


@app.post("/patients/{patient_id}/conversation/end")
def end(patient_id: str) -> dict[str, str]:
    _patient(patient_id)
    session = app.state.sessions.get(patient_id)
    if session is None:
        raise HTTPException(status_code=404, detail="시작된 대화가 없습니다")
    session.stop()
    return {"event": "closed", "state": session.state}
