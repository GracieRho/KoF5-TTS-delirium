"""Internal own-voice IVC upload/delete trial; never accepts patient recordings."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile

import httpx

import _bootstrap  # noqa: F401
from kof5_tts.cloud_prototype import delete_test_voice, enroll_test_voice

MANIFEST = Path(__file__).resolve().parents[1] / "runs" / "internal-test-voice.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="내 음성만 사용하는 내부 IVC 등록·삭제 시험")
    actions = parser.add_subparsers(dest="action", required=True)
    enroll = actions.add_parser("enroll")
    enroll.add_argument("samples", nargs=3, type=Path, help="각 20~30초 PCM16 WAV")
    enroll.add_argument("--own-voice", action="store_true", help="세 파일이 시험자 자신의 목소리임을 확인")
    enroll.add_argument("--upload", action="store_true", help="세 파일을 ElevenLabs에 전송하고 시험 clone 생성")
    delete = actions.add_parser("delete")
    delete.add_argument("--confirm-delete", action="store_true", help="이 CLI가 만든 시험 clone을 공급자에서 삭제")
    args = parser.parse_args(argv)

    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if args.action == "enroll":
        if not args.own_voice or not args.upload:
            parser.error("외부 전송 전 --own-voice와 --upload가 모두 필요합니다")
        if not os.environ.get("VOICE_OWNER_CONSENT_RECORD_ID", "").strip():
            parser.error("시험용 음성 소유자 동의 기록 ID가 필요합니다")
        if not key:
            parser.error("ELEVENLABS_API_KEY가 필요합니다")
        if MANIFEST.exists():
            parser.error("기존 시험 clone을 먼저 삭제해야 합니다")
        if any(not sample.is_file() or sample.stat().st_size > 2_000_000
               for sample in args.samples):
            parser.error("각각 2 MB 이하의 자기 음성 WAV 세 파일이 필요합니다")
        audio = [sample.read_bytes() for sample in args.samples]
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=30) as client:
            result = enroll_test_voice(client, audio, key, True)
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=MANIFEST.parent,
                                                 prefix="voice-test-", suffix=".json", delete=False) as record:
                    temporary = Path(record.name)
                    json.dump({"voice_id": result.voice_id,
                               "requires_verification": result.requires_verification}, record)
                temporary.replace(MANIFEST)
            except OSError:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
                try:
                    delete_test_voice(client, result.voice_id, key)
                except (httpx.HTTPError, ValueError):
                    parser.error(f"로컬 기록이 실패했습니다. 공급자에서 voice ID {result.voice_id}를 삭제하세요")
                raise
        print(f"시험 voice ID: {result.voice_id}")
        if result.requires_verification:
            print("공급자 화자 검증 대기: 확인되기 전에는 TTS에 사용하지 마세요")
        return 0

    if not args.confirm_delete:
        parser.error("공급자 시험 clone 삭제 전 --confirm-delete가 필요합니다")
    if not key or not MANIFEST.is_file():
        parser.error("API key와 이 CLI가 만든 시험 clone 기록이 필요합니다")
    voice_id = json.loads(MANIFEST.read_text(encoding="utf-8"))["voice_id"]
    with httpx.Client(timeout=30) as client:
        delete_test_voice(client, voice_id, key)
    MANIFEST.unlink()
    print("시험 clone 공급자 삭제 확인")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
