"""유료 요청 없이 연구 인터뷰·근거 계획 비교와 보고서를 생성한다."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

import _bootstrap  # noqa: F401
from kof5_tts.research.benchmark import export_inputs, load_responses, run_benchmark, score_responses, write_report
from kof5_tts.research.grounding import load_grounding_cases
from kof5_tts.research.interview import load_question_bank


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        "외부 응답 JSONL: case_id, condition, action, text, evidence_ids, claims, claims_reviewed:true, "
        "elapsed_ms(선택). claims는 사람이 실제 응답의 원자적 주장을 검토하고 근거 원문에 대응시킨 주석입니다. "
        "자동 의미적 함의 판정이 아닙니다. 모든 사례×네 조건을 정확히 한 번씩 제공하세요."
    ))
    parser.add_argument("--output", type=Path, default=Path("runs/research") / datetime.now(timezone.utc).strftime("benchmark-%Y%m%dT%H%M%S%fZ"))
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--seeds", type=int, default=3)
    parser.add_argument("--max-budget", type=int, default=5)
    parser.add_argument("--bootstrap-samples", type=int, default=1000)
    parser.add_argument("--latency-repeats", type=int, default=3)
    parser.add_argument("--question-bank", type=Path)
    parser.add_argument("--grounding-cases", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--responses", type=Path, help="외부에서 생성·사람 주석한 JSONL을 채점; 인터뷰 시뮬레이션 미실행")
    mode.add_argument("--export-inputs", type=Path, help="expected·category 없는 입력 JSONL만 출력; 생성·벤치마크 미실행")
    args = parser.parse_args(argv)
    if not args.export_inputs and args.output.exists() and (not args.output.is_dir() or any(args.output.iterdir())):
        parser.error("출력 경로는 새 폴더 또는 빈 폴더여야 합니다. 기존 결과는 덮어쓰지 않습니다.")
    try:
        cases = load_grounding_cases(args.grounding_cases)
        if args.export_inputs:
            export_inputs(cases, args.export_inputs)
            print(f"채점 라벨 없는 입력 manifest: {args.export_inputs}. 생성·유료 요청은 실행하지 않았습니다.")
            return 0
        report = score_responses(cases, load_responses(args.responses)) if args.responses else run_benchmark(
            question_bank=load_question_bank(args.question_bank), grounding_cases=cases, seed=args.seed,
            seeds=args.seeds, max_budget=args.max_budget, bootstrap_samples=args.bootstrap_samples,
            latency_repeats=args.latency_repeats,
        )
        write_report(report, args.output)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    label = "외부 주석 채점" if args.responses else "오프라인 합성 벤치마크"
    print(f"{label} 완료: {args.output / 'report.html'}")
    print("공급자 호출 0건. 이번 명령은 생성이나 실제 참여자·음성·임상 실험을 실행하지 않았습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
