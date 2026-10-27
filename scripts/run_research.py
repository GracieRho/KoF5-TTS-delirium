"""공급자 호출 없이 가상 개인화 연구 화면을 loopback에서 실행한다."""

import argparse
import os

import _bootstrap  # noqa: F401
import uvicorn


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args()
    if not 1 <= args.port <= 65_535:
        parser.error("port는 1–65535 범위여야 합니다")
    if os.environ.get("VERCEL"):
        parser.error("연구 화면은 개인 컴퓨터에서만 실행합니다")
    os.environ["KOF5_RESEARCH_ENABLED"] = "1"
    uvicorn.run("kof5_tts.api:app", host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
