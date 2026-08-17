#!/usr/bin/env python3
"""WAV 파일 트리를 24 kHz mono 16-bit FLAC으로 변환한다."""

from __future__ import annotations

import argparse
from pathlib import Path

from _bootstrap import REPOSITORY_ROOT
from kof5_tts.preprocessing.audio import AudioConversionError, ConversionResult, convert_wav_tree


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        type=Path,
        default=REPOSITORY_ROOT / "data" / "raw" / "wav",
        help="WAV 파일 또는 WAV를 재귀 탐색할 디렉터리",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=REPOSITORY_ROOT / "data" / "interim" / "flac",
        help="원본 상대 경로를 보존할 FLAC 루트",
    )
    parser.add_argument("--jobs", type=int, default=1, help="동시에 실행할 ffmpeg 수")
    parser.add_argument("--overwrite", action="store_true", help="기존 FLAC을 다시 생성")
    return parser.parse_args()


def show_result(result: ConversionResult) -> None:
    status = "변환" if result.converted else "건너뜀"
    print(f"[{status}] {result.source} -> {result.destination}")


def main() -> int:
    args = parse_args()
    try:
        summary = convert_wav_tree(
            args.input,
            args.output,
            overwrite=args.overwrite,
            jobs=args.jobs,
            on_result=show_result,
        )
    except AudioConversionError as error:
        print(f"오류: {error}")
        return 1
    print(f"완료: 변환 {summary.converted}개, 건너뜀 {summary.skipped}개")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
