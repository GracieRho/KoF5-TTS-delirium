"""Favilium's single-speaker research workspace. Audio and text stay out of storage."""

import hashlib
import hmac
import io
import json
import os
from pathlib import Path
import re
import secrets
import time
import wave

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from .voice_store import StoreUnavailable, get_store

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
DIST = Path(__file__).resolve().parents[2] / "apps/portal_web/dist"
API = "https://api.elevenlabs.io"
MAX_WAV = 4 * 1024 * 1024
MAX_TEXT = 1000
LOGIN = "favilium_access"
WORKSPACE = "favilium_workspace"
LOGIN_TTL = 12 * 3600
OWNER_TTL = 30 * 24 * 3600
SETTLE_TIME = 600  # Never clear an in-flight creation after an inconclusive lookup.
VOICE_ID = re.compile(r"[A-Za-z0-9_-]{1,100}")
OWNER_ID = re.compile(r"[0-9a-f]{48}")


def fail(status, message):
    raise HTTPException(status_code=status, detail=message)


@app.exception_handler(StoreUnavailable)
async def store_unavailable(_request, _exc):
    return JSONResponse({"detail": "목소리 저장소에 연결할 수 없습니다. 연구 담당자가 설정을 확인해 주세요."},
                        status_code=503)


@app.middleware("http")
async def protect_responses(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Permissions-Policy"] = "microphone=(self), camera=()"
    return response


def access_code():
    value = os.getenv("FAVILIUM_ACCESS_CODE", "").strip()
    return value if len(value) >= 16 else ""


def provider_key():
    return os.getenv("ELEVENLABS_API_KEY", "").strip()


def session_key():
    # The shared login code is known to researchers; it cannot sign ownership.
    explicit = os.getenv("FAVILIUM_SESSION_SECRET", "").strip()
    if explicit:
        return explicit if len(explicit) >= 32 else ""
    return provider_key()


def check_origin(request):
    # Fetch sends Origin on same-origin POST/DELETE requests. Local Vite proxies
    # preserve Host. Vercel may terminate HTTPS ahead of the ASGI application.
    scheme = "https" if os.getenv("VERCEL") else request.url.scheme
    if scheme != "https" and request.url.hostname not in ("localhost", "127.0.0.1", "::1"):
        fail(403, "HTTPS 연결로 연구 공간을 열어 주세요.")
    origin = f"{scheme}://{request.url.netloc}"
    if request.headers.get("origin") != origin or request.headers.get("sec-fetch-site") == "cross-site":
        fail(403, "같은 Favilium 화면에서 다시 시도해 주세요.")


def signature(kind, owner, expires):
    # Changing the shared code revokes logins without losing voice ownership.
    login_version = access_code() if kind == LOGIN else ""
    msg = f"{kind}:{owner}:{expires}:{login_version}".encode()
    return hmac.new(session_key().encode(), msg, hashlib.sha256).hexdigest()


def signed_cookie(kind, owner, ttl):
    expires = int(time.time()) + ttl
    return f"{owner}.{expires}.{signature(kind, owner, expires)}"


def cookie_owner(request, kind):
    parts = request.cookies.get(kind, "").split(".")
    if not access_code() or not session_key() or len(parts) != 3:
        return None
    owner, expires, mac = parts
    if not OWNER_ID.fullmatch(owner) or not re.fullmatch(r"[0-9]{1,12}", expires):
        return None
    if int(expires) <= time.time() or not re.fullmatch(r"[0-9a-f]{64}", mac):
        return None
    return owner if hmac.compare_digest(signature(kind, owner, expires), mac) else None


def authenticated(request):
    owner = cookie_owner(request, WORKSPACE)
    return owner if owner and cookie_owner(request, LOGIN) == owner else None


def require_owner(request):
    check_origin(request)
    owner = authenticated(request)
    if not owner:
        fail(401, "연구 접근 코드를 입력해 주세요.")
    return owner


def status_for(owner, *, reconcile=False):
    configured = bool(access_code() and provider_key() and session_key())
    try:
        store = get_store()
    except StoreUnavailable:
        if owner:
            raise
        configured = False
    record = store.get(owner) if owner else None
    if record and reconcile and provider_key() and record.state in ("creating", "verification"):
        with provider() as client:
            recover(store, record, client)
        record = store.get(owner)
    return {"authenticated": bool(owner), "configured": configured,
            "voice_state": record.state if record else "empty",
            "reference": record.reference if record else None}


async def bounded_body(request, limit):
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > limit:
            fail(413, "입력 크기가 허용 범위를 넘었습니다.")
        body.extend(chunk)
    return bytes(body)


async def string_field(request, field, limit):
    if request.headers.get("content-type", "").split(";")[0].strip() != "application/json":
        fail(415, "JSON 형식으로 입력해 주세요.")
    try:
        payload = json.loads(await bounded_body(request, limit))
    except (UnicodeDecodeError, ValueError, RecursionError):
        fail(400, "요청 형식을 확인해 주세요.")
    if not isinstance(payload, dict) or set(payload) != {field} or not isinstance(payload[field], str):
        fail(400, "입력 항목을 확인해 주세요.")
    try:
        payload[field].encode("utf-8")
    except UnicodeEncodeError:
        fail(400, "입력에 올바르지 않은 문자가 있습니다.")
    return payload[field]


@app.get("/api/status")
def status(request: Request):
    return status_for(authenticated(request), reconcile=True)


@app.post("/api/login")
async def login(request: Request):
    check_origin(request)
    if not access_code() or not session_key():
        fail(503, "연구 접근 코드와 서버 키 설정을 확인해 주세요.")
    code = await string_field(request, "code", 2048)
    if not hmac.compare_digest(code.encode(), access_code().encode()):
        fail(401, "연구 접근 코드가 일치하지 않습니다.")
    owner = cookie_owner(request, WORKSPACE) or secrets.token_hex(24)
    response = JSONResponse(await run_in_threadpool(status_for, owner))
    for kind, ttl in ((WORKSPACE, OWNER_TTL), (LOGIN, LOGIN_TTL)):
        response.set_cookie(kind, signed_cookie(kind, owner, ttl), max_age=ttl,
                            httponly=True, samesite="strict", path="/",
                            secure=request.url.scheme == "https" or bool(os.getenv("VERCEL")))
    return response


@app.post("/api/logout")
def logout(request: Request):
    check_origin(request)
    response = JSONResponse(status_for(None))
    response.delete_cookie(LOGIN, path="/")
    return response


def provider():
    key = provider_key()
    if not key:
        fail(503, "ElevenLabs API 키가 설정되지 않았습니다.")
    return httpx.Client(base_url=API, headers={"xi-api-key": key}, timeout=40)


def provider_failure(response=None):
    if response is not None and response.status_code in (401, 402, 403):
        fail(502, "ElevenLabs 키 권한, 요금제와 잔여 크레딧을 확인해 주세요.")
    if response is not None and response.status_code == 429:
        fail(503, "ElevenLabs 요청이 많습니다. 잠시 뒤 다시 시도해 주세요.")
    fail(502, "ElevenLabs 응답을 확인할 수 없습니다. 상태를 확인한 뒤 다시 시도해 주세요.")


def checked_json(response):
    if not response.is_success:
        provider_failure(response)
    try:
        data = response.json()
    except ValueError:
        provider_failure()
    if not isinstance(data, dict):
        provider_failure()
    return data


@app.exception_handler(httpx.RequestError)
async def provider_connection_error(_request, _exc):
    return JSONResponse({"detail": "외부 서비스에 연결할 수 없습니다. 등록 상태를 다시 확인해 주세요."},
                        status_code=502)


def voice_name(reference):
    return f"Favilium {reference}"


def valid_voice_id(value):
    return isinstance(value, str) and VOICE_ID.fullmatch(value) is not None


def lookup(client, reference):
    name = voice_name(reference)
    params = {"search": name, "category": "cloned", "page_size": 100,
              "include_total_count": "false"}
    matches = []
    for _ in range(10):
        body = checked_json(client.get("/v2/voices", params=params))
        if not isinstance(body.get("voices"), list):
            provider_failure()
        for voice in body["voices"]:
            if not isinstance(voice, dict):
                provider_failure()
            if voice.get("name") == name:
                if not valid_voice_id(voice.get("voice_id")):
                    provider_failure()
                matches.append(voice["voice_id"])
        if body.get("has_more") is False:
            if len(matches) > 1:
                fail(409, "같은 등록 번호의 목소리가 여러 개입니다. 연구 담당자가 ElevenLabs에서 확인해 주세요.")
            return matches[0] if matches else None
        token = body.get("next_page_token")
        if body.get("has_more") is not True or not isinstance(token, str) or not token:
            provider_failure()
        params["next_page_token"] = token
    provider_failure()


def recover(store, record, client):
    voice_id = record.voice_id or lookup(client, record.reference)
    if not voice_id:
        return
    data = checked_json(client.get(f"/v1/voices/{voice_id}"))
    if data.get("voice_id") != voice_id or data.get("name") != voice_name(record.reference):
        provider_failure()
    verification = data.get("voice_verification") or {}
    ready = isinstance(verification, dict) and (
        verification.get("requires_verification") is False or verification.get("is_verified") is True)
    store.transition(record.session_id, record.reference, (record.state,),
                     "ready" if ready else "verification", voice_id)


def validated_wav(raw):
    # Re-pack the frames to strip metadata and trailing chunks before upload.
    try:
        with wave.open(io.BytesIO(raw), "rb") as source:
            count, rate = source.getnframes(), source.getframerate()
            if (source.getnchannels() != 1 or source.getsampwidth() != 2
                    or not 8000 <= rate <= 48000 or not 10 * rate <= count <= 120 * rate):
                fail(422, "10~120초의 모노 PCM WAV 녹음이 필요합니다.")
            pcm = source.readframes(count)
    except (wave.Error, EOFError, ValueError, OSError):
        fail(422, "읽을 수 있는 PCM WAV 녹음이 필요합니다.")
    if len(pcm) != 2 * count:
        fail(422, "녹음 파일이 완전하지 않습니다. 다시 녹음해 주세요.")
    output = io.BytesIO()
    with wave.open(output, "wb") as target:
        target.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        target.writeframes(pcm)
    return output.getvalue()


def create_voice(owner, raw):
    wav = validated_wav(raw)
    store = get_store()
    reference = secrets.token_hex(12)
    with provider() as client:
        if not store.create(owner, reference):
            fail(409, "이미 목소리를 등록 중이거나 등록했습니다. 현재 상태를 확인해 주세요.")
        # Reserve before sending. A lost response never triggers a second upload.
        response = client.post("/v1/voices/add", data={"name": voice_name(reference)},
                               files=[("files", ("sample.wav", wav, "audio/wav"))])
        if 400 <= response.status_code < 500 and response.status_code not in (408, 409):
            store.clear(owner, reference, ("creating",))
            if response.status_code in (400, 422):
                fail(422, "ElevenLabs가 녹음을 받아들이지 않았습니다. 조용한 곳에서 다시 녹음해 주세요.")
            provider_failure(response)
        body = checked_json(response)
        voice_id = body.get("voice_id")
        if not valid_voice_id(voice_id):
            provider_failure()
        state = "ready" if body.get("requires_verification") is False else "verification"
        store.transition(owner, reference, ("creating",), state, voice_id)
    return status_for(owner)


@app.post("/api/voice")
async def enroll(request: Request):
    owner = require_owner(request)
    if request.headers.get("x-voice-consent") != "yes":
        fail(403, "녹음한 본인의 목소리 등록 및 외부 전송에 동의해 주세요.")
    if request.headers.get("content-type", "").split(";")[0].strip() != "audio/wav":
        fail(415, "WAV 음성 녹음이 필요합니다.")
    return await run_in_threadpool(create_voice, owner, await bounded_body(request, MAX_WAV))


@app.delete("/api/voice")
def delete_voice(request: Request):
    owner = require_owner(request)
    store = get_store()
    record = store.get(owner)
    if not record:
        return status_for(owner)
    if request.headers.get("x-voice-reference") != record.reference:
        fail(409, "현재 등록된 목소리가 바뀌었습니다. 상태를 다시 확인해 주세요.")
    with provider() as client:
        voice_id = record.voice_id
        if not voice_id:
            voice_id = lookup(client, record.reference)
            if not voice_id:
                if time.time() - record.updated_at.timestamp() < SETTLE_TIME:
                    fail(409, "등록 결과를 확인 중입니다. 잠시 뒤 다시 확인해 주세요.")
                store.clear(owner, record.reference, (record.state,))
                return status_for(owner)
        if record.state != "deleting" and not store.transition(
                owner, record.reference, (record.state,), "deleting", voice_id):
            fail(409, "목소리 상태가 변경되었습니다. 새로 확인해 주세요.")
        response = client.delete(f"/v1/voices/{voice_id}")
        if response.status_code == 404:
            if lookup(client, record.reference) is not None:
                provider_failure(response)
        elif checked_json(response).get("status") != "ok":
            provider_failure()
        store.clear(owner, record.reference, ("deleting",))
    return status_for(owner)


def synthesize(owner, text, reference):
    store = get_store()
    record = store.get(owner)
    if not record or record.state != "ready" or not valid_voice_id(record.voice_id):
        fail(409, "사용할 수 있는 목소리를 먼저 등록해 주세요.")
    if reference != record.reference:
        fail(409, "현재 등록된 목소리가 바뀌었습니다. 상태를 다시 확인해 주세요.")
    with provider() as client, client.stream(
        "POST", f"/v1/text-to-speech/{record.voice_id}", params={"output_format": "mp3_44100_128"},
        headers={"Accept": "audio/mpeg"}, json={"text": text, "model_id": "eleven_multilingual_v2"},
    ) as response:
        media_type = response.headers.get("content-type", "").partition(";")[0].strip().lower()
        if not response.is_success or media_type not in {"audio/mpeg", "audio/mp3", "application/octet-stream"}:
            provider_failure(response)
        audio = bytearray()
        for chunk in response.iter_bytes():
            if len(audio) + len(chunk) > 4 * 1024 * 1024:
                provider_failure()
            audio.extend(chunk)
        # MP3 streams start with either an ID3 tag or an MPEG frame. A proxy
        # returning an empty page or JSON must not create a ready-to-play result.
        if len(audio) < 4 or not (audio.startswith(b"ID3") or
                                  (audio[0] == 0xFF and audio[1] & 0xE0 == 0xE0)):
            provider_failure()
    current = store.get(owner)
    if not current or current.reference != record.reference or current.state != "ready":
        fail(409, "목소리가 삭제되거나 변경되어 재생을 중단했습니다.")
    return Response(bytes(audio), media_type="audio/mpeg")


@app.post("/api/speech")
async def speech(request: Request):
    owner = require_owner(request)
    text = await string_field(request, "text", 16 * 1024)
    if not text.strip() or len(text) > MAX_TEXT:
        fail(422, f"재생할 문장을 1~{MAX_TEXT}자 이내로 입력해 주세요.")
    return await run_in_threadpool(synthesize, owner, text, request.headers.get("x-voice-reference"))


@app.get("/")
@app.get("/studio")
@app.get("/studio/")
def studio():
    path = DIST / "index.html"
    if not path.is_file() or not (DIST / "assets").is_dir():
        fail(503, "Favilium 웹 화면을 먼저 빌드해 주세요.")
    return FileResponse(path, media_type="text/html")


if (DIST / "assets").is_dir():
    app.mount("/assets", StaticFiles(directory=DIST / "assets"), name="assets")
