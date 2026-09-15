#!/usr/bin/env python3
"""사전학습 vocab에 한국어 문자를 더하고 체크포인트 텍스트 임베딩을 확장한다."""

from __future__ import annotations

import argparse
from pathlib import Path

from _bootstrap import REPOSITORY_ROOT  # noqa: F401

from kof5_tts.training.vocab import VocabError, extend


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_vocab", type=Path, help="사전학습 모델의 vocab.txt")
    parser.add_argument("manifest", type=Path, help="audio_file|text 형식의 metadata.csv")
    parser.add_argument("checkpoint", type=Path, help="사전학습 체크포인트")
    parser.add_argument("output_dir", type=Path, help="확장 결과를 저장할 경로")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = extend(args.base_vocab, args.manifest, args.checkpoint, args.output_dir)
    except VocabError as error:
        print(f"오류: {error}")
        return 1

    print(f"vocab: {result.base_size} -> {result.new_size} (추가 {len(result.added)}자)")
    print(f"확장한 임베딩 텐서: {result.expanded_tensors}개")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
