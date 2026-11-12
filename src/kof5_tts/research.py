"""Supabase Auth의 검증된 연구자 계정으로 보호되는 자료 열람 API."""
import hashlib
import hmac
import json
import os
import re
from urllib.parse import parse_qs, urlsplit
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from fastapi.concurrency import run_in_threadpool

from .http_utils import bounded_body, check_origin, fail
from .research_store import PAGE_SIZE
from .voice_store import get_store

research = APIRouter(prefix="/api/research")
COOKIE = "favilium_research"
COOKIE_PATH = "/api/research"
DENIED = "연구팀에 등록한 이메일을 확인해 주세요."


def allowed(email):
    entries = os.getenv("FAVILIUM_RESEARCHER_EMAILS", "").lower().split(",")
    return bool(email) and email.lower() in {entry.strip() for entry in entries if entry.strip()}


def auth_request(method, path, *, token=None, body=None):
    url = os.getenv("FAVILIUM_SUPABASE_URL", "").strip().rstrip("/")
    key = os.getenv("FAVILIUM_SUPABASE_PUBLISHABLE_KEY", "").strip()
    if not url.startswith("https://") or not key or not os.getenv("FAVILIUM_RESEARCHER_EMAILS", "").strip():
        fail(503, "연구자 계정 연결 설정을 확인해 주세요.")
    headers = {"apikey": key}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        response = httpx.request(method, f"{url}/auth/v1/{path}", headers=headers, json=body, timeout=8)
    except httpx.RequestError:
        fail(503, "연구자 인증 서비스에 연결할 수 없습니다.")
    if response.status_code == 429:
        fail(429, "로그인 요청이 많습니다. 잠시 뒤 다시 시도해 주세요.")
    if response.status_code >= 500:
        fail(503, "연구자 인증 서비스에 연결할 수 없습니다.")
    return response


def verified(user):
    return isinstance(user, dict) and bool(user.get("email_confirmed_at")) and allowed(user.get("email", ""))


def cookie_mac(token):
    key = os.getenv("FAVILIUM_SESSION_SECRET", "").strip()
    if len(key) < 32:
        fail(503, "연구자 세션 서명 설정을 확인해 주세요.")
    return hmac.new(key.encode(), ("research-v1:" + token).encode(), hashlib.sha256).hexdigest()


def cookie_token(request):
    raw = request.cookies.get(COOKIE, "")
    mac, _, token = raw.partition(".")
    if (not token or len(raw) > 4000 or not re.fullmatch(r"[A-Za-z0-9._-]+", token)
            or not re.fullmatch(r"[a-f0-9]{64}", mac) or not hmac.compare_digest(mac, cookie_mac(token))):
        return None
    return token


def require_researcher(request: Request):
    token = cookie_token(request)
    if not token:
        fail(401, "연구자 로그인이 필요합니다.")
    response = auth_request("GET", "user", token=token)
    user = response.json() if response.is_success else None
    if not verified(user):
        fail(401, "로그인 시간이 만료되었거나 접근 권한이 없습니다. 다시 로그인해 주세요.")
    return user["email"]


async def login_fields(request):
    check_origin(request)
    if request.headers.get("content-type", "").partition(";")[0] != "application/json":
        fail(415, "로그인 입력 형식을 확인해 주세요.")
    try:
        body = json.loads(await bounded_body(request, 6000))
    except (ValueError, UnicodeDecodeError, RecursionError):
        fail(400, "로그인 입력 형식을 확인해 주세요.")
    if not isinstance(body, dict) or not isinstance(body.get("email"), str):
        fail(400, "이메일을 입력해 주세요.")
    email = body["email"].strip().lower()
    if not allowed(email):
        fail(403, DENIED)
    return email, body


@research.post("/login/email")
async def email_login(request: Request):
    email, _ = await login_fields(request)
    auth = await run_in_threadpool(auth_request, "POST", "otp", body={"email": email, "create_user": True})
    if not auth.is_success:
        fail(400, "인증 메일을 보내지 못했습니다. 연구팀 등록 주소와 메일 발송 설정을 확인해 주세요.")
    return Response(status_code=204)


def email_proof(email, proof):
    proof = proof.strip()
    if re.fullmatch(r"[0-9]{6,10}", proof):
        return {"type": "email", "email": email, "token": proof}
    try:
        link = urlsplit(proof)
        project = urlsplit(os.getenv("FAVILIUM_SUPABASE_URL", ""))
        query = parse_qs(link.query, max_num_fields=12)
    except ValueError:
        fail(422, "인증 메일의 버튼 주소나 인증 코드를 확인해 주세요.")
    kinds = query.get("type", [])
    hashes = query.get("token", [])
    if (link.scheme != "https" or link.netloc != project.netloc or link.path != "/auth/v1/verify"
            or len(kinds) != 1 or kinds[0] not in ("email", "signup", "magiclink") or len(hashes) != 1
            or not re.fullmatch(r"[A-Za-z0-9_-]{20,256}", hashes[0])):
        fail(422, "인증 메일에 있는 버튼의 링크 주소 전체를 복사하거나 숫자 코드를 입력해 주세요.")
    # Supabase's 'email' verification handles signup and returning magic-link users.
    # Only the proof goes to our configured Auth endpoint. The supplied URL is never fetched.
    return {"type": "email", "token_hash": hashes[0]}


@research.post("/login/verify")
async def verify_login(request: Request):
    email, body = await login_fields(request)
    if not isinstance(body.get("proof"), str):
        fail(400, "인증 메일의 링크 주소나 코드를 입력해 주세요.")
    auth = await run_in_threadpool(auth_request, "POST", "verify", body=email_proof(email, body["proof"]))
    data = auth.json() if auth.is_success else {}
    user = data.get("user")
    if not verified(user) or user["email"].lower() != email or not data.get("access_token"):
        fail(401, "인증 정보를 확인하지 못했습니다. 같은 이메일로 받은 최신 링크나 코드를 입력해 주세요.")
    token = data["access_token"]
    response = JSONResponse({"email": user["email"]})
    response.set_cookie(COOKIE, f"{cookie_mac(token)}.{token}", max_age=min(3600, int(data["expires_in"])),
                        httponly=True, secure=request.url.scheme == "https" or bool(os.getenv("VERCEL")),
                        samesite="strict", path=COOKIE_PATH)
    return response


@research.get("/session")
def session(email: str = Depends(require_researcher)):
    return {"email": email}


@research.post("/logout")
def logout(request: Request):
    check_origin(request)
    token = cookie_token(request)
    if token:
        # Always clear the browser cookie when upstream sign-out is unavailable.
        try:
            auth_request("POST", "logout?scope=local", token=token)
        except HTTPException:
            pass
    response = Response(status_code=204)
    response.delete_cookie(COOKIE, path=COOKIE_PATH, httponly=True, samesite="strict",
                           secure=request.url.scheme == "https" or bool(os.getenv("VERCEL")))
    return response


def page(rows):
    return {"items": rows[:PAGE_SIZE], "has_more": len(rows) > PAGE_SIZE}


@research.get("/voices", dependencies=[Depends(require_researcher)])
def voices(offset: int = Query(0, ge=0), search: str = Query("", max_length=24, pattern="^[0-9a-fA-F]*$")):
    return page(get_store().archive.voices(offset, search.lower()))


def readable_archive(reference):
    archive = get_store().archive
    row = archive.by_reference(reference)
    if not row:
        fail(404, "해당 목소리를 찾을 수 없습니다.")
    if row["state"] == "deleting":
        fail(409, "삭제를 확인 중인 목소리의 자료는 열 수 없습니다.")
    return archive


@research.get("/voices/{reference}/speech", dependencies=[Depends(require_researcher)])
def messages(reference: str, offset: int = Query(0, ge=0)):
    return page(readable_archive(reference).messages(reference, offset))


def audio_file(reference, speech_id, download, byte_range):
    data = readable_archive(reference).audio(reference, speech_id)
    if not data:
        fail(404, "보관된 음성 파일이 없습니다.")
    ext, mime = ("mp3", "audio/mpeg") if speech_id else ("wav", "audio/wav")
    code = re.sub(r"[^a-zA-Z0-9_-]", "", reference)[:48]
    filename = f"favilium-{code}-{speech_id or 'sample'}.{ext}"
    disposition = "attachment" if download else "inline"
    headers = {"Content-Disposition": f'{disposition}; filename="{filename}"', "Accept-Ranges": "bytes"}
    if not byte_range:
        return Response(data, media_type=mime, headers=headers)
    size = len(data)
    match = re.fullmatch(r"bytes=(\d{0,16})-(\d{0,16})", byte_range)
    if match and any(match.groups()):
        first, last = match.groups()
        start = int(first) if first else max(0, size - int(last))
        end = min(int(last), size - 1) if first and last else size - 1
        if start <= end:
            headers["Content-Range"] = f"bytes {start}-{end}/{size}"
            return Response(data[start:end+1], status_code=206, media_type=mime, headers=headers)
    return Response(status_code=416, headers={"Content-Range": f"bytes */{size}"})


@research.get("/voices/{reference}/sample", dependencies=[Depends(require_researcher)])
def sample(reference: str, request: Request, download: bool = False):
    return audio_file(reference, None, download, request.headers.get("range"))


@research.get("/voices/{reference}/speech/{speech_id}", dependencies=[Depends(require_researcher)])
def speech_file(reference: str, speech_id: UUID, request: Request, download: bool = False):
    return audio_file(reference, str(speech_id), download, request.headers.get("range"))
