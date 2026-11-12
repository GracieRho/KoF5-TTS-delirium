"""연구팀 링크에 지정된 권한으로 자료를 열람하거나 관리한다."""
import hashlib
import hmac
import os
import re
import secrets
import time
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import JSONResponse, Response

from .http_utils import check_origin, fail
from .research_store import PAGE_SIZE
from .voice_store import get_store

research = APIRouter(prefix="/api/research")
COOKIE = "favilium_research"
COOKIE_PATH = "/api/research"
SESSION_SECONDS = 3600
LINK_SETTINGS = {"view": "FAVILIUM_RESEARCH_VIEW_HASH", "manage": "FAVILIUM_RESEARCH_MANAGE_HASH"}


def link_digest(scope):
    value = os.getenv(LINK_SETTINGS[scope], "").strip().lower()
    return value if re.fullmatch(r"[0-9a-f]{64}", value) else ""


def session_mac(scope, digest, expires, nonce):
    secret = os.getenv("FAVILIUM_SESSION_SECRET", "").strip()
    if len(secret) < 32:
        fail(503, "연구 보관함의 서버 설정을 확인해 주세요.")
    message = f"research-link-v2:{scope}:{digest}:{expires}:{nonce}".encode()
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def require_researcher(request: Request):
    raw = request.cookies.get(COOKIE, "")
    # Former Supabase login cookies and studio cookies do not authorize link access.
    parts = raw.split(".") if len(raw) <= 160 else []
    if len(parts) == 4:
        scope, expires, nonce, signature = parts
        if (scope in LINK_SETTINGS and re.fullmatch(r"[0-9]{1,12}", expires)
                and 0 < int(expires) - time.time() <= SESSION_SECONDS + 1
                and re.fullmatch(r"[0-9a-f]{24}", nonce) and re.fullmatch(r"[0-9a-f]{64}", signature)):
            digest = link_digest(scope)
            if digest and hmac.compare_digest(signature, session_mac(scope, digest, expires, nonce)):
                return scope
    fail(401, "연구팀에서 공유한 링크로 열어 주세요.")


def require_manager(scope: str = Depends(require_researcher)):
    if scope != "manage":
        fail(403, "음성 합성과 삭제는 연구팀의 관리 링크에서 이용할 수 있습니다.")


@research.post("/session")
def open_link(request: Request):
    check_origin(request)
    header = request.headers.get("authorization", "")
    match = re.fullmatch(r"Bearer ([A-Za-z0-9_-]{43})", header)
    if not match:
        fail(403, "연구팀 링크가 올바르지 않습니다.")
    candidate = hashlib.sha256(match[1].encode("ascii")).hexdigest()
    scopes = [scope for scope in LINK_SETTINGS if hmac.compare_digest(candidate, link_digest(scope))]
    if len(scopes) != 1:
        fail(403, "유효한 연구팀 링크를 다시 열어 주세요.")
    scope = scopes[0]
    expires = str(int(time.time()) + SESSION_SECONDS)
    nonce = secrets.token_hex(12)
    signature = session_mac(scope, candidate, expires, nonce)
    response = JSONResponse({"scope": scope})
    response.set_cookie(COOKIE, f"{scope}.{expires}.{nonce}.{signature}", max_age=SESSION_SECONDS,
                        httponly=True, secure=request.url.scheme == "https" or bool(os.getenv("VERCEL")),
                        samesite="strict", path=COOKIE_PATH)
    return response


@research.get("/session")
def session(scope: str = Depends(require_researcher)):
    return {"scope": scope}


@research.post("/logout")
def close_link(request: Request):
    check_origin(request)
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
