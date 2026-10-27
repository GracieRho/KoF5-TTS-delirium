"""완료한 성인 연구 주석 또는 합성 예시를 오프라인 집계한다."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import _bootstrap  # noqa: F401
from kof5_tts.research.experiment import analyze_audio, analyze_critical, analyze_pairwise, analyze_preferences, analyze_voice, read_csv

FIELDS = {
    "preferences": ("participant_id", "strategy", "scenario_id", "correct", "question_count", "elapsed_seconds", "timing_kind"),
    "pairwise": ("participant_id", "scenario_id", "left_id", "right_id", "choice"),
    "audio": ("recording_id", "clock_id", "output_route", "speech_end_seconds", "first_audible_seconds", "playback_command_seconds"),
    "voice": ("participant_id", "item_id", "condition", "outcome", "rating"),
    "critical": ("sample_id", "category", "reference", "heard", "assessed"),
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("analysis", choices=FIELDS)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--key", type=Path, help="pairwise 전용 배정 담당자 블라인드 키")
    parser.add_argument("--target", choices=("fixed", "random", "adaptive"), default="adaptive")
    parser.add_argument("--baseline", choices=("fixed", "random", "adaptive"), default="fixed")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--bootstrap", type=int, default=2000)
    parser.add_argument("--data-kind", choices=("unspecified", "synthetic", "consenting-adult"), default="unspecified")
    args = parser.parse_args()
    try:
        if args.output.exists():
            raise ValueError("기존 보고서를 덮어쓰지 않습니다")
        rows = read_csv(args.input, FIELDS[args.analysis])
        if args.analysis == "preferences":
            report = analyze_preferences(rows, seed=args.seed, repetitions=args.bootstrap)
        elif args.analysis == "pairwise":
            if args.key is None:
                raise ValueError("pairwise에는 --key가 필요합니다")
            report = analyze_pairwise(rows, read_csv(args.key, ("candidate_id", "condition")),
                                      target=args.target, baseline=args.baseline, seed=args.seed, repetitions=args.bootstrap)
        elif args.analysis == "voice":
            report = analyze_voice(rows, seed=args.seed, repetitions=args.bootstrap)
        elif args.analysis == "audio":
            report = analyze_audio(rows)
        else:
            report = analyze_critical(rows)
        report.update(schema_version="kof5-study-analysis-v1", data_kind=args.data_kind,
                      input_sha256=hashlib.sha256(args.input.read_bytes()).hexdigest(), seed=args.seed)
        if args.key:
            report["key_sha256"] = hashlib.sha256(args.key.read_bytes()).hexdigest()
        with args.output.open("x", encoding="utf-8") as stream:
            args.output.chmod(0o600)
            json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write("\n")
    except (ValueError, OSError, KeyError) as error:
        parser.exit(2, f"분석 실패: {error}\n")
    print(f"주석 분석 보고서를 저장했습니다: {args.output}")


if __name__ == "__main__":
    main()
