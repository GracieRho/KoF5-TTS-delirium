"""WAV 파일을 학습용 FLAC 규격으로 변환한다."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

TARGET_SAMPLE_RATE = 24_000
TARGET_CHANNELS = 1
TARGET_SAMPLE_FORMAT = "s16"
TARGET_CODEC = "flac"


class AudioConversionError(RuntimeError):
    """오디오 변환 또는 결과 검증이 실패했을 때 발생한다."""


@dataclass(frozen=True)
class ConversionResult:
    source: Path
    destination: Path
    converted: bool


@dataclass(frozen=True)
class ConversionSummary:
    converted: int
    skipped: int
    results: tuple[ConversionResult, ...]


def _resolve_executable(name: str, override: str | None) -> str:
    executable = override or shutil.which(name)
    if not executable:
        raise AudioConversionError(
            f"{name} 실행 파일을 찾지 못했습니다. macOS에서는 `brew install ffmpeg`로 설치하세요."
        )
    return executable


def find_wav_files(input_path: Path) -> list[Path]:
    """입력 파일 또는 디렉터리 아래 WAV 파일을 결정적인 순서로 찾는다."""

    if not input_path.exists():
        raise AudioConversionError(f"입력 경로가 없습니다: {input_path}")
    if input_path.is_file():
        if input_path.suffix.lower() != ".wav":
            raise AudioConversionError(f"WAV 파일이 아닙니다: {input_path}")
        return [input_path]
    return sorted(
        (path for path in input_path.rglob("*") if path.is_file() and path.suffix.lower() == ".wav"),
        key=lambda path: path.as_posix().casefold(),
    )


def destination_for(source: Path, input_path: Path, output_root: Path) -> Path:
    base = input_path.parent if input_path.is_file() else input_path
    relative = source.relative_to(base)
    return output_root / relative.with_suffix(".flac")


def probe_flac(path: Path, ffprobe: str) -> dict[str, object]:
    command = [
        ffprobe,
        "-v",
        "error",
        "-select_streams",
        "a:0",
        "-show_entries",
        "stream=codec_name,sample_rate,channels,sample_fmt,bits_per_raw_sample",
        "-of",
        "json",
        str(path),
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "ffprobe가 결과를 읽지 못했습니다."
        raise AudioConversionError(f"FLAC 검증 실패 ({path}): {detail}")
    try:
        streams = json.loads(completed.stdout).get("streams", [])
        stream = streams[0]
    except (IndexError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise AudioConversionError(f"FLAC 오디오 스트림을 확인할 수 없습니다: {path}") from error
    if not isinstance(stream, dict):
        raise AudioConversionError(f"FLAC 오디오 스트림 형식이 잘못되었습니다: {path}")
    return stream


def validate_flac(path: Path, ffprobe: str) -> None:
    stream = probe_flac(path, ffprobe)
    expected = {
        "codec_name": TARGET_CODEC,
        "sample_rate": str(TARGET_SAMPLE_RATE),
        "channels": TARGET_CHANNELS,
        "sample_fmt": TARGET_SAMPLE_FORMAT,
        "bits_per_raw_sample": "16",
    }
    mismatches = [
        f"{key}={stream.get(key)!r} (expected {value!r})"
        for key, value in expected.items()
        if stream.get(key) != value
    ]
    if mismatches:
        raise AudioConversionError(f"출력 규격 불일치 ({path}): " + ", ".join(mismatches))


def _convert_one(
    source: Path,
    destination: Path,
    *,
    ffmpeg: str,
    ffprobe: str,
    overwrite: bool,
) -> ConversionResult:
    if destination.exists() and not overwrite:
        validate_flac(destination, ffprobe)
        if destination.stat().st_mtime_ns < source.stat().st_mtime_ns:
            raise AudioConversionError(
                f"기존 출력보다 원본이 최신입니다: {destination}. 다시 만들려면 --overwrite를 사용하세요."
            )
        return ConversionResult(source, destination, converted=False)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.stem}.{uuid.uuid4().hex}.tmp.flac")
    command = [
        ffmpeg,
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(source),
        "-map",
        "0:a:0",
        "-vn",
        "-ac",
        str(TARGET_CHANNELS),
        "-ar",
        str(TARGET_SAMPLE_RATE),
        "-sample_fmt",
        TARGET_SAMPLE_FORMAT,
        "-c:a",
        TARGET_CODEC,
        "-compression_level",
        "8",
        "-map_metadata",
        "-1",
        str(temporary),
    ]
    try:
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or "ffmpeg가 오류 메시지 없이 종료되었습니다."
            raise AudioConversionError(f"WAV 변환 실패 ({source}): {detail}")
        validate_flac(temporary, ffprobe)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    return ConversionResult(source, destination, converted=True)


def convert_wav_tree(
    input_path: Path,
    output_root: Path,
    *,
    overwrite: bool = False,
    jobs: int = 1,
    ffmpeg: str | None = None,
    ffprobe: str | None = None,
    on_result: Callable[[ConversionResult], None] | None = None,
) -> ConversionSummary:
    """WAV 트리를 24 kHz mono 16-bit FLAC 트리로 변환한다."""

    if jobs < 1:
        raise AudioConversionError("jobs는 1 이상이어야 합니다.")
    input_path = input_path.resolve()
    output_root = output_root.resolve()
    wav_files = find_wav_files(input_path)
    if not wav_files:
        raise AudioConversionError(f"변환할 WAV 파일이 없습니다: {input_path}")

    ffmpeg_path = _resolve_executable("ffmpeg", ffmpeg)
    ffprobe_path = _resolve_executable("ffprobe", ffprobe)
    tasks = [(source, destination_for(source, input_path, output_root)) for source in wav_files]

    def run(task: tuple[Path, Path]) -> ConversionResult:
        source, destination = task
        return _convert_one(
            source,
            destination,
            ffmpeg=ffmpeg_path,
            ffprobe=ffprobe_path,
            overwrite=overwrite,
        )

    results: list[ConversionResult] = []
    if jobs == 1:
        for task in tasks:
            result = run(task)
            results.append(result)
            if on_result:
                on_result(result)
    else:
        worker_count = min(jobs, len(tasks), os.cpu_count() or 1)
        with ThreadPoolExecutor(max_workers=worker_count) as executor:
            futures = {executor.submit(run, task): task for task in tasks}
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                if on_result:
                    on_result(result)

    ordered = tuple(sorted(results, key=lambda item: item.source.as_posix().casefold()))
    converted = sum(result.converted for result in ordered)
    return ConversionSummary(converted=converted, skipped=len(ordered) - converted, results=ordered)
