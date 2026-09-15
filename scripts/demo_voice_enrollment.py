"""Internal own-voice IVC upload/delete trial; never accepts patient recordings."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import tempfile
from uuid import uuid4

import httpx

import _bootstrap  # noqa: F401
from kof5_tts.cloud_prototype import (
    delete_test_voice, enroll_test_voice, find_test_voice, test_voice_present,
    validate_test_voice_samples,
)

MANIFEST = Path(__file__).resolve().parents[1] / "runs" / "internal-test-voice.json"


@contextmanager
def ownership_lock():
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with (MANIFEST.parent / "internal-test-voice.lock").open("a+") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError("another own-voice operation is in progress") from exc
        try:
            yield
        finally:
            fcntl.flock(guard, fcntl.LOCK_UN)


def save_manifest(data: dict[str, object]) -> None:
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=MANIFEST.parent,
                                         prefix="voice-test-", suffix=".json", delete=False) as record:
            temporary = Path(record.name)
            json.dump(data, record)
        temporary.replace(MANIFEST)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="내 음성만 사용하는 내부 IVC 등록·삭제 시험")
    actions = parser.add_subparsers(dest="action", required=True)
    enroll = actions.add_parser("enroll")
    enroll.add_argument("samples", nargs=3, type=Path, help="각 20~30초 PCM16 WAV")
    enroll.add_argument("--own-voice", action="store_true", help="세 파일이 시험자 자신의 목소리임을 확인")
    enroll.add_argument("--upload", action="store_true", help="세 파일을 ElevenLabs에 전송하고 시험 clone 생성")
    actions.add_parser("reconcile", help="불확실한 생성 응답을 공급자 이름 검색으로 복구")
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
        if any(not sample.is_file() or sample.stat().st_size > 2_000_000
               for sample in args.samples):
            parser.error("각각 2 MB 이하의 자기 음성 WAV 세 파일이 필요합니다")
        audio = [sample.read_bytes() for sample in args.samples]
        try:
            validate_test_voice_samples(audio)
        except (OSError, ValueError) as exc:
            parser.error(str(exc))
        try:
            with ownership_lock():
                if MANIFEST.exists():
                    parser.error("기존 시험 clone 또는 불확실한 pending 생성이 있습니다. 재등록하지 마세요")
                name = f"KoF5 internal self-voice test {uuid4().hex}"
                save_manifest({"status": "pending", "name": name, "voice_id": None})
                with httpx.Client(timeout=30) as client:
                    try:
                        result = enroll_test_voice(client, audio, key, True, name)
                    except (httpx.HTTPError, ValueError):
                        parser.error("생성 결과가 불확실합니다. pending 기록을 유지하고 reconcile을 실행하세요")
                save_manifest({"status": "created", "name": name, "voice_id": result.voice_id,
                               "requires_verification": result.requires_verification})
        except (OSError, ValueError) as exc:
            parser.error(str(exc))
        print(f"시험 voice ID: {result.voice_id}")
        if result.requires_verification is not False:
            print("공급자 화자 검증 상태가 확인되지 않았습니다. 검증 전에는 TTS에 사용하지 마세요")
        return 0

    if args.action == "delete" and not args.confirm_delete:
        parser.error("공급자 시험 clone 삭제 전 --confirm-delete가 필요합니다")
    if not key:
        parser.error("ELEVENLABS_API_KEY가 필요합니다")
    try:
        with ownership_lock():
            if not MANIFEST.is_file():
                parser.error("이 CLI가 만든 시험 clone 기록이 필요합니다")
            record = json.loads(MANIFEST.read_text(encoding="utf-8"))
            if not isinstance(record, dict) or not isinstance(record.get("name"), str) or not re.fullmatch(
                r"KoF5 internal self-voice test [0-9a-f]{32}", record["name"]
            ) or record.get("status") not in ("pending", "created", "recovered", "deletion_pending"):
                parser.error("시험 clone 기록이 손상됐습니다")
            voice_id = record.get("voice_id")
            if voice_id is not None and (
                not isinstance(voice_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", voice_id)
            ):
                parser.error("시험 clone ID 기록이 손상됐습니다")
            if record["status"] == "deletion_pending" and voice_id is None:
                parser.error("삭제 확인 중인 시험 clone ID 기록이 필요합니다")
            with httpx.Client(timeout=30) as client:
                if voice_id is None:
                    voice_id = find_test_voice(client, record["name"], key)
                    if voice_id is None:
                        parser.error("공급자에서 pending clone을 찾지 못했습니다. 재등록하지 말고 계정을 확인하세요")
                    save_manifest({"status": "recovered", "name": record["name"],
                                   "voice_id": voice_id, "requires_verification": None})
                if args.action == "reconcile":
                    if record["status"] == "deletion_pending":
                        parser.error("삭제 확인 중입니다. delete --confirm-delete를 다시 실행하세요")
                    print(f"시험 voice ID 복구: {voice_id} · 검증 상태 미확인")
                    return 0
                if record["status"] == "deletion_pending":
                    if not test_voice_present(client, voice_id, key):
                        MANIFEST.unlink()
                        print("시험 clone 공급자 삭제 확인")
                        return 0
                else:
                    save_manifest({**record, "status": "deletion_pending", "voice_id": voice_id})
                delete_test_voice(client, voice_id, key)
            MANIFEST.unlink()
    except httpx.HTTPError:
        parser.error("공급자 응답을 확인하지 못했습니다. 로컬 기록을 유지하고 다시 확인하세요")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    print("시험 clone 공급자 삭제 확인")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
