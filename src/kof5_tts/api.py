"""Loopback-only synthetic text API for the first companion flow."""

from __future__ import annotations

from base64 import b64encode
from datetime import datetime, timezone
from hashlib import md5
from hmac import compare_digest
import math
import os
from pathlib import Path
import re
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, ValidationError

from kof5_tts.cloud_prototype import (
    CloudCredentials, hospital_fact_question, run_synthetic_pipeline, run_synthetic_text_pipeline, synthesize_mp3,
    validate_short_wav,
)
from kof5_tts.companion import ConversationSession, Fact, policy_reply, relevant_facts

SYNTHETIC_PATIENT = "synthetic_patient"
SYNTHETIC_DB_PATIENT = "00000000-0000-4000-8000-000000000975"
EMBEDDING_MODEL = "text-embedding-3-small"  # Provisional synthetic fixture only.
FAMILY_CATEGORIES = frozenset({
    "family", "relationship", "hometown", "occupation", "travel", "food", "hobby", "friend",
    "pet", "daily_routine", "family_event", "favorite_story", "recent_event", "comfort_topic",
})
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


def _internal_demo_credentials(request: Request) -> CloudCredentials:
    token = os.environ.get("KOF5_INTERNAL_DEMO_TOKEN", "")
    if len(token) < 32 or not token.isascii():
        raise HTTPException(status_code=503, detail="내부 오디오 시험이 설정되지 않았습니다")
    supplied_token = request.headers.get("x-internal-demo-token", "")
    if not supplied_token.isascii() or not compare_digest(supplied_token, token):
        raise HTTPException(status_code=401, detail="내부 시험 인증이 필요합니다")
    if request.headers.get("x-synthetic-material") != "confirmed":
        raise HTTPException(status_code=400, detail="합성·자가 시험 자료만 허용합니다")
    if not os.environ.get("VOICE_OWNER_CONSENT_RECORD_ID", "").strip():
        raise HTTPException(status_code=503, detail="시험용 음성 소유자 동의 기록이 필요합니다")
    try:
        return CloudCredentials(
            os.environ.get("DEEPGRAM_API_KEY", ""),
            os.environ.get("OPENAI_API_KEY", ""),
            os.environ.get("ELEVENLABS_API_KEY", ""),
            os.environ.get("ELEVENLABS_VOICE_ID", ""),
            True,
        )
    except ValueError as exc:
        raise HTTPException(status_code=503, detail="Hosted 공급자 설정이 필요합니다") from exc


def _device_bearer(request: Request) -> str:
    supplied = request.headers.get("authorization", "")
    if not re.fullmatch(r"Bearer [A-Za-z0-9._-]{40,8192}", supplied):
        raise HTTPException(status_code=401, detail="기기 로그인이 필요합니다")
    return supplied


def _api_headers(config: dict[str, str], bearer: str) -> dict[str, str]:
    return {"apikey": config["publishable_key"], "Authorization": bearer,
            "Accept-Profile": "api", "Content-Profile": "api"}


def _bounded_json(response: httpx.Response, limit: int) -> object:
    if len(response.content) > limit:
        raise ValueError("hosted response is too large")
    return response.json()


def _current_window(start: object, end: object) -> bool:
    try:
        now = datetime.now(timezone.utc)
        beginning = datetime.fromisoformat(start) if isinstance(start, str) else None
        ending = datetime.fromisoformat(end) if isinstance(end, str) else None
        return bool(beginning and beginning <= now and (ending is None or ending > now))
    except (ValueError, TypeError):
        return False


async def _embedding(text: str) -> list[float]:
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key or not 1 <= len(text) <= 1000:
        raise HTTPException(status_code=503, detail="합성 임베딩 공급자 설정이 필요합니다")
    try:
        async with httpx.AsyncClient(timeout=12) as client:
            response = await client.post(
                "https://api.openai.com/v1/embeddings",
                json={"model": EMBEDDING_MODEL, "input": text},
                headers={"Authorization": f"Bearer {key}"},
            )
            response.raise_for_status()
            body = _bounded_json(response, 100_000)
            if not isinstance(body, dict) or body.get("model") != EMBEDDING_MODEL:
                raise ValueError("unexpected embedding model")
            data = body.get("data")
            if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
                raise ValueError("unexpected embedding data")
            vector = data[0].get("embedding")
            if (data[0].get("index") != 0 or not isinstance(vector, list) or len(vector) != 1536
                    or any(type(value) not in (int, float) or not math.isfinite(value) for value in vector)
                    or not any(value != 0 for value in vector)):
                raise ValueError("invalid embedding vector")
            return [float(value) for value in vector]
    except (httpx.HTTPError, ValueError, TypeError):
        raise HTTPException(status_code=502, detail="합성 임베딩 공급자 처리가 실패했습니다") from None


async def _device_preflight(request: Request, patient_id: str) -> None:
    config = guardian_config()
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.get(
                f'{config["url"]}/rest/v1/patient_device_context',
                params={"select": "patient_id,encounter_id", "patient_id": f"eq.{patient_id}"},
                headers=_api_headers(config, _device_bearer(request)),
            )
            if response.status_code in (401, 403):
                raise HTTPException(status_code=403, detail="입원 기기 배정이 필요합니다")
            response.raise_for_status()
            rows = _bounded_json(response, 4096)
            if (not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict)
                    or rows[0].get("patient_id") != patient_id
                    or not isinstance(rows[0].get("encounter_id"), str)):
                raise HTTPException(status_code=403, detail="입원 기기 배정·동의가 중단됐습니다")
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError):
        raise HTTPException(status_code=503, detail="기기 배정·동의 사전 확인이 실패했습니다") from None


async def _paired_turn_rows(
    request: Request, patient_id: str, term: str,
    rpc_name: Literal["patient_family_turn_context", "patient_hospital_turn_context"],
) -> list[dict]:
    config = guardian_config()
    bearer = _device_bearer(request)
    headers = {
        "apikey": config["publishable_key"], "Authorization": bearer,
        "Accept-Profile": "api", "Content-Profile": "api",
    }
    url = config["url"]
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            turn = await client.post(
                f"{url}/rest/v1/rpc/{rpc_name}",
                json={"p_patient_id": patient_id, "p_term": term}, headers=headers,
            )
            if turn.status_code in (401, 403):
                raise HTTPException(status_code=403, detail="입원 기기 배정이 필요합니다")
            turn.raise_for_status()
            rows = turn.json()
            if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
                raise ValueError("paired turn context is invalid")
            if rows[0].get("authorized") is not True:
                raise HTTPException(status_code=403, detail="입원 기기 배정이 중단됐습니다")
            facts = rows[0].get("facts")
            if not isinstance(facts, list) or len(facts) > 3 or any(not isinstance(row, dict) for row in facts):
                raise ValueError("paired fact response is invalid")
            return facts
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError, KeyError):
        raise HTTPException(status_code=503, detail="기기 권한·승인 사실 조회가 실패했습니다") from None


async def _paired_memory(request: Request, patient_id: str, term: str) -> str:
    facts = await _paired_turn_rows(request, patient_id, term, "patient_family_turn_context")
    if any(not isinstance(row.get("content"), str) or not 1 <= len(row["content"]) <= 1000
           for row in facts):
        raise HTTPException(status_code=503, detail="가족 기억 응답을 확인하지 못했습니다")
    return "\n".join(row["content"] for row in facts)


async def _paired_semantic_memory(request: Request, patient_id: str, transcript: str) -> str:
    await _device_preflight(request, patient_id)  # No transcript leaves this server before current consent.
    vector = await _embedding(transcript)
    config = guardian_config()
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.post(
                f'{config["url"]}/rest/v1/rpc/patient_family_semantic_turn_context',
                json={"p_patient_id": patient_id, "p_query_embedding": vector},
                headers=_api_headers(config, _device_bearer(request)),
            )
            if response.status_code in (401, 403):
                raise HTTPException(status_code=403, detail="입원 기기 배정이 필요합니다")
            response.raise_for_status()
            rows = _bounded_json(response, 8192)
            if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
                raise ValueError("semantic turn context is invalid")
            if rows[0].get("authorized") is not True:
                raise HTTPException(status_code=403, detail="입원 기기 배정·동의가 중단됐습니다")
            facts = rows[0].get("facts")
            if (not isinstance(facts, list) or len(facts) > 3
                    or any(not isinstance(row, dict) or not isinstance(row.get("content"), str)
                           or not 1 <= len(row["content"]) <= 1000
                           or row.get("category") not in FAMILY_CATEGORIES for row in facts)):
                raise ValueError("semantic facts are invalid")
            return "\n".join(row["content"] for row in facts)
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError):
        raise HTTPException(status_code=503, detail="기기 권한·의미 검색 조회가 실패했습니다") from None


@app.post("/internal/synthetic/guardian/{patient_id}/fact/{fact_id}/embedding", include_in_schema=False)
async def index_synthetic_family_fact(patient_id: str, fact_id: str, request: Request) -> dict[str, str]:
    """Read one current guardian fact under JWT/RLS, then index the fixed synthetic fixture."""
    if patient_id != SYNTHETIC_DB_PATIENT or not re.fullmatch(
        r"[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}", fact_id
    ):
        raise HTTPException(status_code=404, detail="합성 시험 사실만 사용할 수 있습니다")
    if request.headers.get("x-synthetic-material") != "confirmed":
        raise HTTPException(status_code=400, detail="합성·자가 시험 자료만 허용합니다")
    async for chunk in request.stream():
        if chunk:
            raise HTTPException(status_code=413, detail="색인 요청 본문은 비워주세요")
    bearer = _device_bearer(request)
    config = guardian_config()
    secret_key = os.environ.get("KOF5_SUPABASE_SECRET_KEY", "")
    legacy_key = os.environ.get("KOF5_SUPABASE_SERVICE_ROLE_KEY", "")
    if secret_key.startswith("sb_secret_") and len(secret_key) >= 32:
        service_headers = {"apikey": secret_key}
    elif legacy_key.startswith("eyJ") and len(legacy_key) >= 40:
        service_headers = {"apikey": legacy_key, "Authorization": f"Bearer {legacy_key}"}
    else:
        raise HTTPException(status_code=503, detail="서버 색인 권한이 준비되지 않았습니다")
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            link = await client.get(
                f'{config["url"]}/rest/v1/guardian_links',
                params={"select": "patient_id,access_status,effective_at,expires_at",
                        "patient_id": f"eq.{patient_id}", "access_status": "eq.verified"},
                headers=_api_headers(config, bearer),
            )
            if link.status_code in (401, 403):
                raise HTTPException(status_code=403, detail="검증된 보호자 연결이 필요합니다")
            link.raise_for_status()
            links = _bounded_json(link, 4096)
            if (not isinstance(links, list) or len(links) != 1 or not isinstance(links[0], dict)
                    or links[0].get("patient_id") != patient_id
                    or links[0].get("access_status") != "verified"
                    or not _current_window(links[0].get("effective_at"), links[0].get("expires_at"))):
                raise HTTPException(status_code=403, detail="검증된 보호자 연결이 필요합니다")
            fact = await client.get(
                f'{config["url"]}/rest/v1/family_context',
                params={"select": "fact_id,patient_id,content,sensitivity,category,active,valid_from,valid_until",
                        "fact_id": f"eq.{fact_id}", "patient_id": f"eq.{patient_id}"},
                headers=_api_headers(config, bearer),
            )
            if fact.status_code in (401, 403):
                raise HTTPException(status_code=403, detail="보호자 사실 조회 권한이 필요합니다")
            fact.raise_for_status()
            rows = _bounded_json(fact, 8192)
            if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
                raise HTTPException(status_code=404, detail="현재 보호자 사실이 없습니다")
            row = rows[0]
            content = row.get("content")
            if (row.get("fact_id") != fact_id or row.get("patient_id") != patient_id
                    or row.get("sensitivity") != "ordinary"
                    or row.get("category") not in FAMILY_CATEGORIES
                    or row.get("active") is not True
                    or not _current_window(row.get("valid_from"), row.get("valid_until"))
                    or not isinstance(content, str)
                    or not 1 <= len(content) <= 1000):
                raise HTTPException(status_code=409, detail="현재 색인 가능한 일반 기억이 아닙니다")
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError):
        raise HTTPException(status_code=503, detail="보호자 사실 조회가 실패했습니다") from None

    vector = await _embedding(content)
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.post(
                f'{config["url"]}/rest/v1/rpc/upsert_synthetic_family_fact_embedding',
                json={"p_fact_id": fact_id, "p_embedding": vector, "p_model": EMBEDDING_MODEL,
                      "p_content_md5": md5(content.encode("utf-8")).hexdigest()},
                headers={**service_headers, "Accept-Profile": "api", "Content-Profile": "api"},
            )
            response.raise_for_status()
            if _bounded_json(response, 4096) is not True:
                raise HTTPException(status_code=409, detail="사실·연결이 변경되어 색인을 거절했습니다")
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError):
        raise HTTPException(status_code=503, detail="서버 색인이 실패했습니다") from None
    return {"status": "ready", "fact_id": fact_id}


async def _paired_hospital_fact(request: Request, patient_id: str, term: str) -> str:
    facts = await _paired_turn_rows(request, patient_id, term, "patient_hospital_turn_context")
    allowed = {"hospital", "ward", "room", "test_schedule", "visit_schedule"}
    if any(row.get("category") not in allowed or not isinstance(row.get("content"), str)
           or not 1 <= len(row["content"]) <= 200 or not row["content"].strip()
           or not isinstance(row.get("verified_at"), str) for row in facts):
        raise HTTPException(status_code=503, detail="병원 승인 사실 응답을 확인하지 못했습니다")
    # An ambiguous question must never select an arbitrary exam or visit time.
    return facts[0]["content"] if len(facts) == 1 else ""


async def _paired_due_message(request: Request, patient_id: str, message_id: str) -> str:
    config = guardian_config()
    headers = {
        "apikey": config["publishable_key"], "Authorization": _device_bearer(request),
        "Accept-Profile": "api", "Content-Profile": "api",
    }
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.post(
                f'{config["url"]}/rest/v1/rpc/synthetic_due_hospital_message',
                json={"_patient_id": patient_id, "_message_id": message_id}, headers=headers,
            )
            if response.status_code in (401, 403):
                raise HTTPException(status_code=403, detail="입원 기기 배정이 필요합니다")
            response.raise_for_status()
            rows = response.json()
            if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
                raise ValueError("due message response is invalid")
            row = rows[0]
            if row.get("authorized") is not True:
                raise HTTPException(status_code=403, detail="승인된 예약 메시지를 사용할 수 없습니다")
            text = row.get("approved_text")
            if row.get("message_id") != message_id or not isinstance(text, str) or not 1 <= len(text) <= 200:
                raise ValueError("approved message response is invalid")
            return text
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError, KeyError):
        raise HTTPException(status_code=503, detail="기기 권한·병원 메시지 조회가 실패했습니다") from None


@app.post("/internal/synthetic/audio", include_in_schema=False)
async def synthetic_audio(request: Request) -> dict[str, str | None]:
    """Internal Phase-0 WAV→STT→reply→TTS; no real-patient route or storage."""
    credentials = _internal_demo_credentials(request)
    if request.headers.get("content-type", "").split(";", 1)[0].lower() != "audio/wav":
        raise HTTPException(status_code=415, detail="WAV 오디오만 허용합니다")
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


async def _read_text_turn(request: Request) -> SpeechTurn:
    if request.headers.get("content-type", "").split(";", 1)[0].lower() != "application/json":
        raise HTTPException(status_code=415, detail="JSON 전사만 허용합니다")
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > 4096:
            raise HTTPException(status_code=413, detail="짧은 전사만 허용합니다")
        body.extend(chunk)
    try:
        speech = SpeechTurn.model_validate_json(bytes(body))
    except ValidationError:
        raise HTTPException(status_code=422, detail="짧은 한국어 전사와 활성화 판정이 필요합니다") from None
    if not speech.transcript.strip():
        raise HTTPException(status_code=422, detail="빈 전사는 처리하지 않습니다")
    return speech


@app.post("/internal/synthetic/text", include_in_schema=False)
async def synthetic_text(request: Request) -> dict[str, str | None]:
    """Internal text-only iPad path; candidate PCM stays on the device."""
    credentials = _internal_demo_credentials(request)
    speech = await _read_text_turn(request)

    def run() -> tuple[str | None, bytes | None]:
        with httpx.Client(timeout=20) as client:
            return run_synthetic_text_pipeline(client, speech.transcript, speech.label, FAMILY_FACT.content,
                                               credentials)

    try:
        reply, audio = await run_in_threadpool(run)
    except (httpx.HTTPError, ValueError):
        raise HTTPException(status_code=502, detail="글·음성 공급자 처리가 실패했습니다") from None
    return {
        "transcript": speech.transcript,
        "reply": reply,
        "audio_mp3_base64": b64encode(audio).decode("ascii") if audio else None,
    }


@app.post("/internal/synthetic/paired/{patient_id}/text", include_in_schema=False)
async def paired_synthetic_text(patient_id: str, request: Request) -> dict[str, str | None]:
    """Paired device JWT/RLS, refreshed family facts and text-only synthetic turn."""
    if patient_id != SYNTHETIC_DB_PATIENT:
        raise HTTPException(status_code=404, detail="합성 시험 환자만 사용할 수 있습니다")
    credentials = _internal_demo_credentials(request)
    speech = await _read_text_turn(request)
    hospital = hospital_fact_question(speech.transcript)
    # One invoker RPC checks authorization and exactly one fact namespace each turn.
    known_fact = (await _paired_hospital_fact(request, patient_id, speech.transcript) if hospital
                  else await _paired_semantic_memory(request, patient_id, speech.transcript))

    def run() -> tuple[str | None, bytes | None]:
        with httpx.Client(timeout=20) as client:
            return run_synthetic_text_pipeline(
                client, speech.transcript, speech.label, known_fact, credentials,
                namespace="hospital_context" if hospital else "family_context",
                semantic_match=bool(known_fact) and not hospital,
            )

    try:
        reply, audio = await run_in_threadpool(run)
    except (httpx.HTTPError, ValueError):
        raise HTTPException(status_code=502, detail="글·음성 공급자 처리가 실패했습니다") from None
    return {
        "transcript": speech.transcript,
        "reply": reply,
        "audio_mp3_base64": b64encode(audio).decode("ascii") if audio else None,
    }


@app.post("/internal/synthetic/paired/{patient_id}/message/{message_id}/audio", include_in_schema=False)
async def paired_synthetic_message_audio(patient_id: str, message_id: str, request: Request) -> dict[str, str]:
    """Read one due approved synthetic message under device RLS, then voice its exact text."""
    if patient_id != SYNTHETIC_DB_PATIENT or not re.fullmatch(r"[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}", message_id):
        raise HTTPException(status_code=404, detail="합성 시험 메시지만 사용할 수 있습니다")
    credentials = _internal_demo_credentials(request)
    approved_text = await _paired_due_message(request, patient_id, message_id)

    def run() -> bytes:
        with httpx.Client(timeout=20) as client:
            return synthesize_mp3(client, approved_text, credentials)

    try:
        audio = await run_in_threadpool(run)
    except (httpx.HTTPError, ValueError):
        raise HTTPException(status_code=502, detail="승인 메시지 음성 생성이 실패했습니다") from None
    return {"approved_text": approved_text, "audio_mp3_base64": b64encode(audio).decode("ascii")}


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
