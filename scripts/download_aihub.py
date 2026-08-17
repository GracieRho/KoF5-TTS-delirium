#!/usr/bin/env python3
"""AI Hub 데이터셋 목록을 조회하거나 승인된 파일을 다운로드한다."""

from __future__ import annotations

import argparse
from pathlib import Path

from _bootstrap import REPOSITORY_ROOT, env_search_roots
from kof5_tts.preprocessing.aihub import (
    AihubError,
    download_dataset,
    environment_with_api_key,
    list_datasets,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aihubshell", help="aihubshell 실행 파일 경로")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="데이터셋 또는 파일 목록 조회")
    list_parser.add_argument("--dataset-key", help="파일 목록을 조회할 데이터셋 key")

    download_parser = subparsers.add_parser("download", help="승인된 데이터셋 다운로드")
    download_parser.add_argument("--dataset-key", required=True)
    download_parser.add_argument(
        "--file-key", action="append", default=[], help="선택 파일 key. 여러 번 쓰거나 쉼표로 구분"
    )
    download_parser.add_argument(
        "--output-dir",
        type=Path,
        help="다운로드 경로. 기본값: data/raw/aihub/<dataset-key>",
    )
    download_parser.add_argument("--env-file", type=Path, help="AIHUB_APIKEY가 있는 로컬 .env")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "list":
            print(list_datasets(args.dataset_key, cli=args.aihubshell), end="")
            return 0

        output_dir = args.output_dir or (
            REPOSITORY_ROOT / "data" / "raw" / "aihub" / args.dataset_key
        )
        environment = environment_with_api_key(
            env_file=args.env_file,
            search_roots=env_search_roots(),
        )
        result = download_dataset(
            args.dataset_key,
            output_dir,
            file_keys=args.file_key,
            cli=args.aihubshell,
            environ=environment,
            on_output=lambda line: print(line, end=""),
        )
        selected = ",".join(result.file_keys) if result.file_keys else "전체"
        print(f"완료: dataset={result.dataset_key}, files={selected}, path={result.output_dir}")
        return 0
    except AihubError as error:
        print(f"오류: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
