#!/usr/bin/env python3
"""AI Hub 다운로드 후 WAV를 24 kHz mono 16-bit FLAC으로 일괄 변환한다."""

from __future__ import annotations

import argparse
from pathlib import Path

from _bootstrap import REPOSITORY_ROOT, env_search_roots
from kof5_tts.preprocessing.aihub import AihubError, download_dataset, environment_with_api_key
from kof5_tts.preprocessing.audio import AudioConversionError, ConversionResult, convert_wav_tree


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-key", required=True)
    parser.add_argument(
        "--file-key", action="append", default=[], help="선택 파일 key. 여러 번 쓰거나 쉼표로 구분"
    )
    parser.add_argument("--raw-dir", type=Path, help="AI Hub 원본 다운로드 경로")
    parser.add_argument("--output-dir", type=Path, help="변환 FLAC 출력 경로")
    parser.add_argument("--env-file", type=Path, help="AIHUB_APIKEY가 있는 로컬 .env")
    parser.add_argument("--aihubshell", help="aihubshell 실행 파일 경로")
    parser.add_argument("--skip-download", action="store_true", help="이미 받은 원본으로 변환만 실행")
    parser.add_argument("--overwrite", action="store_true", help="기존 FLAC을 다시 생성")
    parser.add_argument("--jobs", type=int, default=1, help="동시에 실행할 ffmpeg 수")
    return parser.parse_args()


def show_conversion(result: ConversionResult) -> None:
    status = "변환" if result.converted else "건너뜀"
    print(f"[{status}] {result.source} -> {result.destination}")


def main() -> int:
    args = parse_args()
    raw_dir = args.raw_dir or (
        REPOSITORY_ROOT / "data" / "raw" / "aihub" / args.dataset_key
    )
    output_dir = args.output_dir or (
        REPOSITORY_ROOT / "data" / "interim" / "flac" / args.dataset_key
    )
    try:
        if not args.skip_download:
            environment = environment_with_api_key(
                env_file=args.env_file,
                search_roots=env_search_roots(),
            )
            download_dataset(
                args.dataset_key,
                raw_dir,
                file_keys=args.file_key,
                cli=args.aihubshell,
                environ=environment,
                on_output=lambda line: print(line, end=""),
            )
        summary = convert_wav_tree(
            raw_dir,
            output_dir,
            overwrite=args.overwrite,
            jobs=args.jobs,
            on_result=show_conversion,
        )
    except (AihubError, AudioConversionError) as error:
        print(f"오류: {error}")
        return 1

    print(f"파이프라인 완료: 변환 {summary.converted}개, 건너뜀 {summary.skipped}개")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
