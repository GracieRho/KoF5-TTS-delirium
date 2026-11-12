"""음성 스튜디오와 연구자 페이지가 공유하는 요청 검증."""
import os
from fastapi import HTTPException


def fail(status, message):
    raise HTTPException(status_code=status, detail=message)



def check_origin(request):
    # Fetch sends Origin on same-origin POST/DELETE requests. Local Vite proxies
    # preserve Host. Vercel may terminate HTTPS ahead of the ASGI application.
    scheme = "https" if os.getenv("VERCEL") else request.url.scheme
    if scheme != "https" and request.url.hostname not in ("localhost", "127.0.0.1", "::1"):
        fail(403, "HTTPS 연결로 연구 공간을 열어 주세요.")
    origin = f"{scheme}://{request.url.netloc}"
    if request.headers.get("origin") != origin or request.headers.get("sec-fetch-site") == "cross-site":
        fail(403, "같은 Favilium 화면에서 다시 시도해 주세요.")



async def bounded_body(request, limit):
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > limit:
            fail(413, "입력 크기가 허용 범위를 넘었습니다.")
        body.extend(chunk)
    return bytes(body)
