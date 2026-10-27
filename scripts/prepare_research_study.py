"""동의 성인 연구용 빈 양식과 명시적 합성 예시를 준비한다. 모집·API 호출 없음."""
from __future__ import annotations

import argparse
import csv
import itertools
from pathlib import Path
import random

import _bootstrap  # noqa: F401
from kof5_tts.research.experiment import allocation, SCENARIOS, STRATEGIES, VOICE_CONDITIONS


def write_csv(path: Path, fields: list[str], rows: list[dict]) -> None:
    with path.open("x", encoding="utf-8", newline="") as stream:
        path.chmod(0o600)
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def prepare(output: Path, participants: int, seed: int) -> None:
    if participants > 1000:
        raise ValueError("양식 생성은 한 번에 1000명 이하로 제한합니다")
    assignments = allocation(participants, seed)
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("출력 경로는 새 폴더 또는 빈 폴더여야 합니다")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.chmod(0o700)
    write_csv(output / "assignments.csv", ["participant_id", "strategy_order", "voice_order", "heldout_set"], assignments)
    conditions = list(STRATEGIES)
    random.Random(seed).shuffle(conditions)
    key = [{"candidate_id": f"C{i + 1}", "condition": condition} for i, condition in enumerate(conditions)]
    write_csv(output / "coordinator_blind_key.csv", ["candidate_id", "condition"], key)
    preference_fields = ["participant_id", "strategy", "scenario_id", "correct", "question_count", "elapsed_seconds", "timing_kind"]
    preference_rows = [{"participant_id": person["participant_id"], "strategy": strategy, "scenario_id": scenario,
                        "correct": "", "question_count": "", "elapsed_seconds": "", "timing_kind": ""}
                       for person in assignments for strategy in STRATEGIES for scenario in SCENARIOS]
    write_csv(output / "preferences.csv", preference_fields, preference_rows)
    rng = random.Random(seed + 1)
    pairwise_fields = ["participant_id", "scenario_id", "left_id", "right_id", "choice"]
    pairwise_rows = []
    for person in assignments:
        for scenario in SCENARIOS:
            for a, b in itertools.combinations([row["candidate_id"] for row in key], 2):
                left, right = (a, b) if rng.randrange(2) else (b, a)
                pairwise_rows.append({"participant_id": person["participant_id"], "scenario_id": scenario,
                                      "left_id": left, "right_id": right, "choice": ""})
    rng.shuffle(pairwise_rows)
    write_csv(output / "pairwise.csv", pairwise_fields, pairwise_rows)
    voice_fields = ["participant_id", "item_id", "condition", "outcome", "rating"]
    write_csv(output / "voice_ratings.csv", voice_fields, [
        {"participant_id": person["participant_id"], "item_id": item, "condition": condition, "outcome": outcome, "rating": ""}
        for person in assignments for item in SCENARIOS for condition in VOICE_CONDITIONS
        for outcome in ("familiarity", "content_fit", "naturalness")])
    audio_fields = ["recording_id", "clock_id", "output_route", "speech_end_seconds", "first_audible_seconds", "playback_command_seconds"]
    critical_fields = ["sample_id", "category", "reference", "heard", "assessed"]
    write_csv(output / "audio_timestamps.csv", audio_fields, [])
    write_csv(output / "critical_information.csv", critical_fields, [])
    synthetic = output / "synthetic-example"
    synthetic.mkdir(mode=0o700)
    example_preferences = [{"participant_id": f"SYNTH-{p}", "strategy": strategy, "scenario_id": SCENARIOS[s],
                            "correct": int((p + s) % 2 == 0 or strategy == "adaptive"), "question_count": 5,
                            "elapsed_seconds": 30 + p, "timing_kind": "replay-answer-sum"}
                           for p in range(1, 3) for s in range(2) for strategy in STRATEGIES]
    write_csv(synthetic / "preferences.csv", preference_fields, example_preferences)
    write_csv(synthetic / "coordinator_blind_key.csv", ["candidate_id", "condition"], key)
    write_csv(synthetic / "pairwise.csv", pairwise_fields, [
        {"participant_id": "SYNTH-1", "scenario_id": "synthetic-01", "left_id": "C1", "right_id": "C2", "choice": "tie"},
        {"participant_id": "SYNTH-2", "scenario_id": "synthetic-01", "left_id": "C1", "right_id": "C2", "choice": "left"},
    ])
    write_csv(synthetic / "voice_ratings.csv", voice_fields, [
        {"participant_id": f"SYNTH-{p}", "item_id": "synthetic-01", "condition": condition, "outcome": "content_fit", "rating": rating}
        for p in (1, 2) for condition, rating in zip(VOICE_CONDITIONS, (4, 6, 3, 5))])
    write_csv(synthetic / "audio_timestamps.csv", audio_fields, [
        {"recording_id": "SYNTH-AUDIO-1", "clock_id": "same-recording", "output_route": "synthetic-speaker", "speech_end_seconds": 2, "first_audible_seconds": 3.5, "playback_command_seconds": 3.3},
        {"recording_id": "SYNTH-AUDIO-2", "clock_id": "same-recording", "output_route": "synthetic-speaker", "speech_end_seconds": 4, "first_audible_seconds": 6, "playback_command_seconds": ""},
    ])
    write_csv(synthetic / "critical_information.csv", critical_fields, [
        {"sample_id": "SYNTH-TEXT-1", "category": "name", "reference": "가상 인물 가", "heard": "가상 인물 가", "assessed": 1},
        {"sample_id": "SYNTH-TEXT-1", "category": "negation", "reference": "아니다", "heard": "맞다", "assessed": 1},
    ])
    readme = output / "README.ko.md"
    readme.write_text("""# 연구 양식\n\n참여자 자료는 전부 공란입니다. 배정표는 참가 또는 동의를 뜻하지 않습니다.\n실제 성인 자료 수집 전 저장소의 docs/research/experiment-protocol.md 절차와 기관 검토 필요 여부를 확인하세요.\n\n- coordinator_blind_key.csv는 배정 담당자만 보관하고 평가자에게 주지 않습니다.\n- heldout-01..04는 자리표시자입니다. 수집 전에 별도 평가 상황을 확정·동결하고 모든 조건에 같은 ID를 사용하세요.\n- correct는 동결한 미관측 상황의 선호 정답과 예측의 일치(0/1), 공란은 결측입니다.\n- question_count는 실제로 사용한 질문 수입니다. elapsed_seconds는 timing_kind=live-interview이면 실제 인터뷰 경과 시간, replay-answer-sum이면 선택된 질문의 기록된 응답시간 합입니다. 두 시간 종류는 별도 파일로 분석하며 재생 비용을 실제 인터뷰 시간으로 주장하지 않습니다.\n- pairwise의 choice는 left/right/tie입니다. 자료 수집자는 조건명을 숨기고 후보 문장만 제공합니다.\n- 오디오 시각은 동일 외부 녹음 시간축에서 수동 주석합니다. command는 같은 축으로 정렬한 경우에만 입력합니다.\n- 핵심정보 assessed=1과 heard 공란은 들리지 않은 누락 오류입니다. assessed 공란/0은 아직 판정하지 않은 결측입니다.\n- synthetic-example/의 모든 값은 코드 검증을 위해 만든 가상 숫자이며 사람·모델·음성 측정 결과가 아닙니다.\n""", encoding="utf-8")
    readme.chmod(0o600)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--participants", type=int, default=12)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()
    try:
        prepare(args.output, args.participants, args.seed)
    except (ValueError, OSError) as error:
        parser.exit(2, f"준비 실패: {error}\n")
    print(f"빈 연구 양식과 명시적 합성 예시를 준비했습니다: {args.output}")


if __name__ == "__main__":
    main()
