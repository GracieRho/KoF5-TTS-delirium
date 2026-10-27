"""참여자 주석·외부 녹음 시각의 오프라인 분석. 치료 효과를 추정하지 않는다."""
from __future__ import annotations

import csv
import itertools
import math
from pathlib import Path
import random
import statistics
import unicodedata

STRATEGIES = ("fixed", "random", "adaptive")
VOICE_CONDITIONS = ("familiar_generic", "familiar_personalized", "unfamiliar_generic", "unfamiliar_personalized")
VOICE_ORDERS = ((0, 1, 3, 2), (1, 2, 0, 3), (2, 3, 1, 0), (3, 0, 2, 1))
SCENARIOS = tuple(f"heldout-{index:02d}" for index in range(1, 5))


def allocation(participants: int, seed: int = 0) -> list[dict]:
    if type(participants) is not int or not 1 <= participants <= 10000:
        raise ValueError("참여자 수는 1–10000의 정수여야 합니다")
    if type(seed) is not int:
        raise ValueError("seed는 정수여야 합니다")
    rng = random.Random(seed)
    strategy_orders = list(itertools.permutations(STRATEGIES))
    voice_orders = list(VOICE_ORDERS)
    rng.shuffle(strategy_orders)
    rng.shuffle(voice_orders)
    rows = []
    for index in range(participants):
        rows.append({"participant_id": f"P{index + 1:04d}",
                     "strategy_order": "|".join(strategy_orders[index % len(strategy_orders)]),
                     "voice_order": "|".join(VOICE_CONDITIONS[j] for j in voice_orders[index % 4]),
                     "heldout_set": "heldout-study-v1"})
    return rows


def read_csv(path: Path, required: tuple[str, ...]) -> list[dict[str, str]]:
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames is None or len(set(reader.fieldnames)) != len(reader.fieldnames):
            raise ValueError("CSV 헤더가 없거나 중복되었습니다")
        if not set(required) <= set(reader.fieldnames):
            raise ValueError("CSV 필수 열이 누락되었습니다: " + ", ".join(required))
        rows = list(reader)
    if len(rows) > 100000:
        raise ValueError("CSV는 100000행 이하여야 합니다")
    if any(None in row or any(value is None for value in row.values()) for row in rows):
        raise ValueError("CSV의 열 개수가 맞지 않습니다")
    return rows


def _number(value: str, label: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{label}: 숫자가 필요합니다") from error
    if not math.isfinite(number) or number < 0:
        raise ValueError(f"{label}: 유한한 음이 아닌 값이 필요합니다")
    return number


def _id(value: str, label: str) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 128:
        raise ValueError(f"{label}: 짧은 가명 ID가 필요합니다")
    return value.strip()


def percentile(values: list[float], probability: float) -> float:
    if not values:
        raise ValueError("분위수를 계산할 관측값이 없습니다")
    ordered = sorted(values)
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def bootstrap_mean(values: list[float], *, seed: int = 0, repetitions: int = 2000) -> dict:
    if type(repetitions) is not int or not 1 <= repetitions <= 100000:
        raise ValueError("bootstrap 반복 수는 1–100000의 정수여야 합니다")
    if any(not math.isfinite(value) for value in values):
        raise ValueError("bootstrap 입력은 유한해야 합니다")
    result = {"n_participants": len(values), "mean": statistics.mean(values) if values else None,
              "ci95": None, "method": "participant_percentile_bootstrap", "repetitions": repetitions}
    if len(values) < 2:
        return result
    rng = random.Random(seed)
    means = [statistics.mean(rng.choices(values, k=len(values))) for _ in range(repetitions)]
    result["ci95"] = [percentile(means, 0.025), percentile(means, 0.975)]
    return result


def analyze_preferences(rows: list[dict], *, seed: int = 0, repetitions: int = 2000) -> dict:
    cells = {}
    participants = set()
    timing_kinds = set()
    for row in rows:
        participant = _id(row["participant_id"], "participant_id")
        scenario = _id(row["scenario_id"], "scenario_id")
        strategy = row["strategy"]
        if strategy not in STRATEGIES:
            raise ValueError("알 수 없는 인터뷰 조건입니다")
        key = participant, scenario, strategy
        if key in cells:
            raise ValueError("참여자·상황·조건 행이 중복되었습니다")
        participants.add(participant)
        if row["correct"] == "":
            cells[key] = None
            continue
        if row["correct"] not in {"0", "1"}:
            raise ValueError("correct는 0, 1 또는 결측 공란이어야 합니다")
        count = _number(row["question_count"], "question_count")
        elapsed = _number(row["elapsed_seconds"], "elapsed_seconds")
        if not count.is_integer() or count < 1 or elapsed <= 0:
            raise ValueError("완료 행에는 양의 질문 수와 소요시간이 필요합니다")
        timing_kind = row["timing_kind"]
        if timing_kind not in {"live-interview", "replay-answer-sum"}:
            raise ValueError("timing_kind는 live-interview 또는 replay-answer-sum이어야 합니다")
        timing_kinds.add(timing_kind)
        if len(timing_kinds) > 1:
            raise ValueError("실시간 인터뷰와 재생 비용 시간은 별도 파일로 분석해야 합니다")
        cells[key] = int(row["correct"]), int(count), elapsed
    comparisons = {}
    for baseline in ("fixed", "random"):
        paired_by_participant = {}
        complete = missing = 0
        relevant = {(p, s) for p, s, strategy in cells if strategy in {"adaptive", baseline}}
        for participant, scenario in sorted(relevant):
            target = cells.get((participant, scenario, "adaptive"))
            control = cells.get((participant, scenario, baseline))
            if target is None or control is None:
                missing += 1
                continue
            if target[1] != control[1]:
                raise ValueError("대응 비교의 질문 예산이 다릅니다")
            complete += 1
            paired_by_participant.setdefault(participant, []).append(target[0] - control[0])
        differences = [statistics.mean(values) for _, values in sorted(paired_by_participant.items())]
        comparisons[f"adaptive_minus_{baseline}"] = {
            **bootstrap_mean(differences, seed=seed, repetitions=repetitions),
            "complete_scenario_pairs": complete, "missing_scenario_pairs": missing,
            "unit": "participant_mean_paired_accuracy_difference"}
    strategy_summary = {}
    for strategy in STRATEGIES:
        grouped = {}
        for (participant, _, condition), value in cells.items():
            if condition == strategy and value is not None:
                grouped.setdefault(participant, []).append(value)
        strategy_summary[strategy] = {
            "n_participants": len(grouped), "n_completed_scenarios": sum(map(len, grouped.values())),
            "participant_mean_accuracy": statistics.mean(statistics.mean(v[0] for v in values) for values in grouped.values()) if grouped else None,
            "participant_mean_elapsed_seconds": statistics.mean(statistics.mean(v[2] for v in values) for values in grouped.values()) if grouped else None,
        }
    return {"analysis": "heldout_preference_prediction", "n_participants_seen": len(participants),
            "timing_kind": next(iter(timing_kinds), None),
            "missing_rows": sum(value is None for value in cells.values()),
            "strategies": strategy_summary, "comparisons": comparisons,
            "limitation": "비교는 완료된 같은 상황·예산 쌍에 한정된다. 결측은 대체하지 않는다. 임상 효과를 측정하지 않는다."}


def analyze_pairwise(rows: list[dict], key_rows: list[dict], *, target: str = "adaptive", baseline: str = "fixed", seed: int = 0, repetitions: int = 2000) -> dict:
    if target not in STRATEGIES or baseline not in STRATEGIES or target == baseline:
        raise ValueError("서로 다른 유효 조건을 비교해야 합니다")
    key = {}
    for row in key_rows:
        candidate = _id(row["candidate_id"], "candidate_id")
        if candidate in key or row["condition"] not in STRATEGIES:
            raise ValueError("블라인드 키가 중복되거나 조건이 잘못되었습니다")
        key[candidate] = row["condition"]
    if len(key) != len(STRATEGIES) or set(key.values()) != set(STRATEGIES):
        raise ValueError("블라인드 키에는 각 조건이 정확히 한 번 필요합니다")
    participants = {}
    seen = set()
    complete = missing = excluded = 0
    for row in rows:
        participant = _id(row["participant_id"], "participant_id")
        scenario = _id(row["scenario_id"], "scenario_id")
        left, right = row["left_id"], row["right_id"]
        if left not in key or right not in key or left == right:
            raise ValueError("블라인드 후보 ID가 잘못되었습니다")
        pair = participant, scenario, tuple(sorted((left, right)))
        if pair in seen:
            raise ValueError("동일한 상황·후보 쌍이 중복되었습니다")
        seen.add(pair)
        choice = row["choice"]
        if choice not in {"", "left", "right", "tie"}:
            raise ValueError("choice는 left/right/tie 또는 결측 공란이어야 합니다")
        if {key[left], key[right]} != {target, baseline}:
            excluded += 1
            continue
        if choice == "":
            missing += 1
            continue
        score = 0.5 if choice == "tie" else float(key[left if choice == "left" else right] == target)
        participants.setdefault(participant, []).append(score)
        complete += 1
    values = [statistics.mean(scores) for _, scores in sorted(participants.items())]
    return {"analysis": "blind_pairwise_preference", "target": target, "baseline": baseline,
            **bootstrap_mean(values, seed=seed, repetitions=repetitions),
            "completed_pairs": complete, "missing_pairs": missing, "other_condition_pairs": excluded,
            "unit": "participant_mean_target_win_score", "tie_score": 0.5,
            "limitation": "가족다움·표현 선호 점수이며 치료 효과나 인격 복제의 정확도가 아니다."}


def analyze_audio(rows: list[dict]) -> dict:
    audible, command, gaps = [], [], []
    seen = set()
    routes = set()
    for row in rows:
        recording = _id(row["recording_id"], "recording_id")
        if recording in seen:
            raise ValueError("recording_id가 중복되었습니다")
        seen.add(recording)
        _id(row["clock_id"], "clock_id")
        routes.add(_id(row["output_route"], "output_route"))
        if len(routes) > 1:
            raise ValueError("출력 경로가 다른 녹음은 별도 파일로 분석해야 합니다")
        end = _number(row["speech_end_seconds"], "speech_end_seconds")
        first = _number(row["first_audible_seconds"], "first_audible_seconds")
        if first < end:
            raise ValueError("첫 청취음이 발화 종료보다 빠릅니다")
        audible.append(first - end)
        if row.get("playback_command_seconds", "") != "":
            at = _number(row["playback_command_seconds"], "playback_command_seconds")
            if not end <= at <= first:
                raise ValueError("동일 시간축의 재생 명령은 발화 종료와 첫 청취음 사이여야 합니다")
            command.append(at - end)
            gaps.append(first - at)
    def distribution(values):
        return {"n": len(values), "p50_seconds": percentile(values, .5) if values else None,
                "p95_seconds": percentile(values, .95) if values else None,
                "min_seconds": min(values) if values else None, "max_seconds": max(values) if values else None}
    return {"analysis": "external_recording_manual_timestamps", "first_audible_latency": distribution(audible),
            "playback_command_latency": distribution(command), "command_to_audible": distribution(gaps),
            "limitation": "수동 주석·동일 녹음 시간축의 측정이다. 재생 명령과 실제 소리를 혼용하지 않으며 환자의 이해·임상 개선을 뜻하지 않는다."}


def _edit_distance(reference: str, heard: str) -> int:
    previous = list(range(len(heard) + 1))
    for i, expected in enumerate(reference, 1):
        current = [i]
        for j, actual in enumerate(heard, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (expected != actual)))
        previous = current
    return previous[-1]


def analyze_critical(rows: list[dict]) -> dict:
    categories = {key: {"assessed": 0, "errors": 0} for key in ("name", "place", "time", "negation")}
    seen = set()
    characters = edits = missing = 0
    for row in rows:
        sample = _id(row["sample_id"], "sample_id")
        category = row["category"]
        if category not in categories or (sample, category) in seen:
            raise ValueError("핵심 정보 범주가 잘못되었거나 sample·category가 중복되었습니다")
        seen.add((sample, category))
        if row["assessed"] in {"", "0"}:
            missing += 1
            continue
        if row["assessed"] != "1":
            raise ValueError("assessed는 0/1 또는 공란이어야 합니다")
        reference = unicodedata.normalize("NFC", row["reference"])
        heard = unicodedata.normalize("NFC", row["heard"])
        if not reference or max(len(reference), len(heard)) > 2000:
            raise ValueError("완료 주석에는 1–2000자의 기준 문구와 2000자 이하 청취 문구가 필요합니다")
        categories[category]["assessed"] += 1
        categories[category]["errors"] += int(reference != heard)
        characters += len(reference)
        edits += _edit_distance(reference, heard)
    for values in categories.values():
        values["error_rate"] = values["errors"] / values["assessed"] if values["assessed"] else None
    return {"analysis": "manual_critical_information_transcription", "categories": categories,
            "missing_annotations": missing, "reference_characters": characters, "character_edits": edits,
            "annotated_span_cer": edits / characters if characters else None,
            "normalization": "Unicode NFC; spaces and punctuation retained",
            "limitation": "CER는 주석한 핵심 구간만의 값이며 전체 음성 CER가 아니다. 공란 청취 문구는 assessed=1일 때 누락 오류로 센다."}


def analyze_voice(rows: list[dict], *, seed: int = 0, repetitions: int = 2000) -> dict:
    """2×2 반복측정의 참여자별 대비. 불완전한 4조건 세트는 대체하지 않는다."""
    cells = {}
    for row in rows:
        participant = _id(row["participant_id"], "participant_id")
        item = _id(row["item_id"], "item_id")
        outcome = row["outcome"]
        condition = row["condition"]
        if outcome not in {"familiarity", "content_fit", "naturalness"} or condition not in VOICE_CONDITIONS:
            raise ValueError("음성 요인실험 조건 또는 결과변수가 잘못되었습니다")
        key = participant, item, outcome, condition
        if key in cells:
            raise ValueError("참여자·항목·결과변수·조건이 중복되었습니다")
        if row["rating"] == "":
            cells[key] = None
        else:
            value = _number(row["rating"], "rating")
            if not 1 <= value <= 7 or not value.is_integer():
                raise ValueError("rating은 1–7의 정수 또는 결측 공란이어야 합니다")
            cells[key] = value
    outcomes = {}
    for outcome in sorted({key[2] for key in cells}):
        groups = {}
        complete = missing = 0
        for participant, item in sorted({(p, item) for p, item, measure, _ in cells if measure == outcome}):
            values = [cells.get((participant, item, outcome, condition)) for condition in VOICE_CONDITIONS]
            if any(value is None for value in values):
                missing += 1
                continue
            fg, fp, ug, up = values
            contrasts = ((fg + fp - ug - up) / 2, (fp + up - fg - ug) / 2, (fp - fg) - (up - ug))
            groups.setdefault(participant, []).append(contrasts)
            complete += 1
        estimates = {}
        for index, name in enumerate(("familiar_minus_unfamiliar", "personalized_minus_generic", "voice_by_content_interaction")):
            values = [statistics.mean(item[index] for item in items) for _, items in sorted(groups.items())]
            estimates[name] = bootstrap_mean(values, seed=seed, repetitions=repetitions)
        outcomes[outcome] = {"complete_item_sets": complete, "missing_item_sets": missing, "contrasts": estimates}
    return {"analysis": "voice_content_2x2_participant_contrasts", "outcomes": outcomes,
            "rating_scale": [1, 7], "unit": "participant_mean_complete_item_contrast",
            "limitation": "동의 성인의 주관적 평정이다. 자연스러움·친숙함·내용 적합성은 환자 치료 효과가 아니며 여러 결과변수는 탐색적이다."}
