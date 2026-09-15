"""Run the provisional hosted pipeline with synthetic audio only."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import tempfile
from time import perf_counter

import httpx

import _bootstrap  # noqa: F401
from kof5_tts.cloud_prototype import CloudCredentials, run_synthetic_pipeline


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="합성 자료 전용 hosted STT→LLM→TTS 개발 시험")
    parser.add_argument("wav", type=Path, help="환자·임상 자료가 아닌 합성/자기 음성 WAV")
    parser.add_argument("--synthetic-only", action="store_true", help="입력 자료가 합성/자기 시험 자료임을 확인")
    args = parser.parse_args(argv)
    if not args.synthetic_only:
        parser.error("외부 공급자 전송 전 --synthetic-only를 지정해야 합니다")
    consent_record = os.environ.get("VOICE_OWNER_CONSENT_RECORD_ID", "").strip()
    if not consent_record:
        parser.error("동의된 음성 소유자의 VOICE_OWNER_CONSENT_RECORD_ID가 필요합니다")
    credentials = CloudCredentials(
        os.environ.get("DEEPGRAM_API_KEY", ""),
        os.environ.get("OPENAI_API_KEY", ""),
        os.environ.get("ELEVENLABS_API_KEY", ""),
        os.environ.get("ELEVENLABS_VOICE_ID", ""),
        True,
    )
    if not args.wav.is_file() or args.wav.stat().st_size > 2_000_000:
        parser.error("2 MB 이하의 합성 WAV 파일이 필요합니다")
    wav = args.wav.read_bytes()
    started = perf_counter()
    with httpx.Client(timeout=20) as client:
        _, _, audio = run_synthetic_pipeline(
            client, wav, "2024년 5월에 수민과 제주도 여행을 갔고 흑돼지를 좋아했다.",
            credentials,
        )
    if audio is None:
        print("환자 거부 또는 대화 종료로 생성 음성이 없습니다")
        return 0
    output_dir = Path(__file__).resolve().parents[1] / "runs"
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=output_dir, prefix="synthetic-preview-", suffix=".mp3", delete=False
    ) as result:
        result.write(audio)
        output = Path(result.name)
    print(f"합성 시험 MP3: {output}")
    print(f"전체 왕복: {perf_counter() - started:.2f}초")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
