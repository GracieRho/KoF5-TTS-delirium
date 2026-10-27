"""합성 응답자와 추출형 템플릿을 비교하는 오프라인 연구 벤치마크."""

from __future__ import annotations

import csv
from datetime import datetime, timezone
from hashlib import sha256
import html
import json
import math
from pathlib import Path
import platform
import random
from statistics import mean
import subprocess
from time import perf_counter

from .grounding import load_grounding_cases, plan_reply
from .interview import interview_state, load_question_bank, option_likelihoods

STRATEGIES = ("fixed", "random", "adaptive")
CONDITIONS = ("full_context", "rag", "no_time", "proposed")
RESPONDENT_MODELS = ("in_model", "context_dependent")
CONDITION_DESCRIPTIONS = {
    "full_context": "공통 안전 필터 후 동일 topic의 첫 근거를 선택하는 추출형 휴리스틱",
    "rag": "동일 topic 후보의 어휘 겹침·최신 검증 시각 순으로 선택하는 검색 휴리스틱",
    "no_time": "제안 추출형 계획에서 시간 필터만 제거한 ablation",
    "proposed": "출처·프로필·승인·시간·철회·개정·상충을 검사하는 추출형 계획",
}
LIMITATION = (
    "합성 응답자·구조화 topic·추출형 템플릿의 오프라인 비교입니다. "
    "실제 참여자 개인화, 자유 생성 LLM/RAG의 안전성, 음성 품질, 섬망 개선 효과를 입증하지 않습니다. "
    "계산 지연은 공급자 왕복·iPad 첫 청취음 지연이 아닙니다."
)
EXTERNAL_LIMITATION = (
    "외부에서 제공한 응답과 사람이 검토·정규화한 주장 주석을 채점합니다. "
    "주장·근거 ID의 일치는 자동 의미적 함의 검증이 아닙니다. 생성·전사·음성·임상 효과를 측정하지 않습니다."
)


def percentile(values: list[float], quantile: float) -> float | None:
    if not values:
        return None
    if not 0 <= quantile <= 1:
        raise ValueError("quantile must be between 0 and 1")
    ordered = sorted(values)
    position = (len(ordered) - 1) * quantile
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def paired_difference_ci(
    left: dict[str, float], right: dict[str, float], *, seed: int = 0, samples: int = 1000
) -> dict:
    """동일 profile의 반복 관측을 먼저 평균한 뒤 profile 쌍을 재표집한다."""
    if not left or set(left) != set(right):
        raise ValueError("paired groups must be nonempty and identical")
    if isinstance(samples, bool) or not isinstance(samples, int) or not 1 <= samples <= 10000:
        raise ValueError("bootstrap samples must be between 1 and 10000")
    differences = [left[key] - right[key] for key in sorted(left)]
    rng = random.Random(seed)
    draws = [mean(rng.choices(differences, k=len(differences))) for _ in range(samples)]
    return {
        "difference": mean(differences), "ci95": [percentile(draws, 0.025), percentile(draws, 0.975)],
        "group_count": len(differences), "resampling_unit": "synthetic_profile",
    }


def _digest(value) -> str:
    return sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def _rng(seed: int, *parts) -> random.Random:
    return random.Random(_digest([seed, *parts]))


def _sample(probabilities: dict[str, float], rng: random.Random) -> str:
    options = sorted(probabilities)
    return rng.choices(options, weights=[probabilities[key] for key in options], k=1)[0]


def simulate_answers(bank: dict, hypothesis: dict, *, seed: int, respondent_model: str) -> dict[str, str]:
    """전략과 무관하게 모든 질문의 숨겨진 응답을 한 번만 샘플링한다."""
    if respondent_model not in RESPONDENT_MODELS:
        raise ValueError("unknown respondent model")
    answers = {}
    for index, question in enumerate(bank["questions"]):
        target = hypothesis
        if respondent_model == "context_dependent" and index % 2:
            style = dict(hypothesis["style"])
            support = bank["dimensions"]["support"]
            style["support"] = support[(support.index(style["support"]) + 1) % len(support)]
            target = {**hypothesis, "style": style}
        probabilities = option_likelihoods(bank, target, question)
        answers[question["id"]] = _sample(
            probabilities, _rng(seed, respondent_model, hypothesis["id"], question["id"])
        )
    return answers


def score_grounding(case: dict, result: dict) -> dict:
    """별도 수동 라벨로 채점하며 planner의 validator나 reason은 사용하지 않는다."""
    expected = case["expected"]
    expected_claims = set(expected["claims"])
    claims = result["claims"]
    answered = result["action"] == "answer"
    unsupported = sum(claim not in expected_claims for claim in claims)
    action_correct = result["action"] == expected["action"]
    evidence_correct = set(result["evidence_ids"]) == set(expected["evidence_ids"])
    claims_correct = set(claims) == expected_claims
    correct = action_correct and evidence_correct and claims_correct
    return {
        "answerable": expected["action"] == "answer", "answered": answered,
        "action_correct": action_correct, "evidence_correct": evidence_correct,
        "claims_correct": claims_correct, "correct": correct,
        "claim_count": len(claims), "unsupported_claim_count": unsupported,
        "erroneous_answer": answered and not correct,
    }


def grounding_summary(rows: list[dict]) -> dict:
    if not rows:
        raise ValueError("cannot summarize empty rows")
    answered = sum(row["answered"] for row in rows)
    answerable = sum(row["answerable"] for row in rows)
    claims = sum(row["claim_count"] for row in rows)
    latency = [row["latency_ms"] for row in rows if row["latency_ms"] is not None]
    return {
        "case_count": len(rows), "answered_count": answered, "answerable_count": answerable,
        "coverage": answered / len(rows),
        "answerable_coverage": sum(row["answered"] and row["answerable"] for row in rows) / answerable if answerable else None,
        "valid_answer_rate": sum(row["correct"] and row["answerable"] for row in rows) / answerable if answerable else None,
        "selective_risk": sum(row["erroneous_answer"] for row in rows) / answered if answered else None,
        "unsupported_claim_rate": sum(row["unsupported_claim_count"] for row in rows) / claims if claims else None,
        "case_accuracy": mean(row["correct"] for row in rows),
        "latency_p50_ms": percentile(latency, 0.5), "latency_p95_ms": percentile(latency, 0.95),
    }


def _profile_scores(rows: list[dict]) -> dict[str, float]:
    profiles = sorted({row["profile_id"] for row in rows})
    return {profile: mean(row["accuracy"] for row in rows if row["profile_id"] == profile) for profile in profiles}


def _execution_metadata() -> dict:
    root = Path(__file__).resolve().parents[3]
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, check=False)
    status = subprocess.run(["git", "status", "--porcelain"], cwd=root, capture_output=True, text=True, check=False)
    paths = [Path(__file__), Path(__file__).with_name("interview.py"), Path(__file__).with_name("grounding.py")]
    return {
        "schema_version": "kof5-research-benchmark/v1", "created_at": datetime.now(timezone.utc).isoformat(),
        "git_revision": revision.stdout.strip() or None, "git_dirty": bool(status.stdout.strip()),
        "implementation_sha256": {path.name: sha256(path.read_bytes()).hexdigest() for path in paths},
        "python_version": platform.python_version(), "platform": platform.platform(), "provider_requests": 0,
    }


def export_inputs(cases: list[dict], path: Path) -> None:
    """별도 생성·주장 주석 작업에 넘길 입력만 내보내며 채점 라벨은 제외한다."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as stream:
        for condition in CONDITIONS:
            for index, case in enumerate(cases, 1):
                stream.write(json.dumps({
                    "case_id": case["id"], "condition": condition,
                    "input": {"id": f"case-{index:04d}", **{key: case[key] for key in
                              ("profile_id", "question", "topic_key", "now", "evidence")}},
                }, ensure_ascii=False) + "\n")


def load_responses(path: Path) -> list[dict]:
    path = Path(path)
    if path.stat().st_size > 10_000_000:
        raise ValueError("response file must be at most 10 MB")
    records = []
    with path.open(encoding="utf-8") as stream:
        for index, line in enumerate(stream, start=1):
            if not line.strip():
                raise ValueError(f"empty response record at line {index}")
            records.append(json.loads(line))
            if len(records) > 10000:
                raise ValueError("response file has too many records")
    return records


def score_responses(cases: list[dict], responses: list[dict]) -> dict:
    """사람이 근거 원문에 대응시킨 claim 주석만 채점하며 응답을 생성하지 않는다."""
    if not cases or len({case["id"] for case in cases}) != len(cases):
        raise ValueError("cases must be nonempty with unique ids")
    expected_keys = {(case["id"], condition) for case in cases for condition in CONDITIONS}
    indexed = {}
    for response in responses:
        if not isinstance(response, dict):
            raise ValueError("response must be an object")
        key = response.get("case_id"), response.get("condition")
        if not all(isinstance(value, str) for value in key) or key not in expected_keys or key in indexed:
            raise ValueError("response has unknown or duplicate case/condition")
        if response.get("claims_reviewed") is not True:
            raise ValueError("external claims require explicit human review: claims_reviewed=true")
        if not isinstance(response.get("action"), str) or response["action"] not in {"answer", "abstain", "identity", "stop", "refer"}:
            raise ValueError("response has invalid action")
        if not isinstance(response.get("text"), str) or not response["text"].strip() or len(response["text"]) > 2000:
            raise ValueError("response text must contain 1..2000 characters")
        for field, limit in [("claims", 20), ("evidence_ids", 100)]:
            values = response.get(field)
            if (not isinstance(values, list) or len(values) > limit
                    or any(not isinstance(value, str) or not value.strip() or len(value) > 1000 for value in values)
                    or len(values) != len(set(values))):
                raise ValueError(f"response has invalid {field}")
        elapsed = response.get("elapsed_ms")
        if elapsed is not None and (isinstance(elapsed, bool) or not isinstance(elapsed, (int, float))
                                    or not math.isfinite(elapsed) or not 0 <= elapsed <= 86_400_000):
            raise ValueError("elapsed_ms must be finite, nonnegative, and at most one day")
        indexed[key] = response
    if set(indexed) != expected_keys:
        raise ValueError("responses must cover every case and all four conditions exactly once")
    rows = []
    for condition in CONDITIONS:
        for case in cases:
            response = indexed[case["id"], condition]
            rows.append({
                "case_id": case["id"], "profile_id": case["profile_id"], "category": case.get("category", "unspecified"),
                "condition": condition, "action": response["action"], "text": response["text"],
                "evidence_ids": response["evidence_ids"], "claims": response["claims"],
                "reason": "external_human_reviewed_annotation", "latency_ms": response.get("elapsed_ms"),
                **score_grounding(case, response),
            })
    return {
        "metadata": {
            **_execution_metadata(), "mode": "offline_external_annotations", "limitation": EXTERNAL_LIMITATION,
            "grounding_cases_sha256": _digest(cases), "responses_sha256": _digest(responses),
            "condition_descriptions": {condition: "외부 결과의 조건 ID. 실제 생성 모델·프롬프트·설정은 별도 실험기록 필요" for condition in CONDITIONS},
            "latency_source": "외부 제공 elapsed_ms; 누락은 측정되지 않음으로 표시",
            "pairing": "동일 사례의 네 조건; 이 채점 모드는 기술 통계만 제공",
        },
        "interview_summary": [], "interview_comparisons": [], "interview_rows": [],
        "grounding_summary": [{"condition": condition, **grounding_summary([row for row in rows if row["condition"] == condition])} for condition in CONDITIONS],
        "grounding_rows": rows,
    }


def run_benchmark(
    *, question_bank: dict | None = None, grounding_cases: list[dict] | None = None,
    seed: int = 7, seeds: int = 3, max_budget: int = 8, bootstrap_samples: int = 1000,
    latency_repeats: int = 3,
) -> dict:
    for name, value, maximum in [
        ("seeds", seeds, 100), ("max_budget", max_budget, 12),
        ("bootstrap_samples", bootstrap_samples, 10000), ("latency_repeats", latency_repeats, 100),
    ]:
        if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= maximum:
            raise ValueError(f"{name} must be between 1 and {maximum}")
    if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed <= 2**32 - seeds:
        raise ValueError("seed and all repeat seeds must fit an unsigned 32-bit integer")
    bank = question_bank if question_bank is not None else load_question_bank()
    cases = grounding_cases if grounding_cases is not None else load_grounding_cases()
    if not cases:
        raise ValueError("grounding cases must not be empty")
    if max_budget > sum(q["split"] == "elicitation" for q in bank["questions"]):
        raise ValueError("max_budget exceeds elicitation question count")
    start = perf_counter()
    interview_rows = []
    for model in RESPONDENT_MODELS:
        for hypothesis in bank["hypotheses"]:
            for repeat in range(seeds):
                trial_seed = seed + repeat
                target = simulate_answers(bank, hypothesis, seed=trial_seed, respondent_model=model)
                for budget in range(1, max_budget + 1):
                    for strategy in STRATEGIES:
                        answers = []
                        trial_start = perf_counter()
                        for _ in range(budget):
                            state = interview_state(answers, strategy=strategy, seed=trial_seed, budget=budget, question_bank=bank)
                            question = state["next_question"]
                            if question is None:
                                raise ValueError("interview stopped before budget")
                            answers.append({"question_id": question["id"], "option_id": target[question["id"]]})
                        state = interview_state(answers, strategy=strategy, seed=trial_seed, budget=budget, question_bank=bank)
                        elapsed = (perf_counter() - trial_start) * 1000
                        predictions = state["heldout_predictions"]
                        if not predictions:
                            raise ValueError("heldout predictions must not be empty")
                        accuracy = mean(prediction["option_id"] == target[prediction["question_id"]] for prediction in predictions)
                        interview_rows.append({
                            "respondent_model": model, "profile_id": hypothesis["id"], "seed": trial_seed,
                            "budget": budget, "strategy": strategy, "accuracy": accuracy,
                            "heldout_count": len(predictions), "uncertainty": state["uncertainty"],
                            "latency_ms": elapsed, "question_ids": [answer["question_id"] for answer in answers],
                        })
    interview_summaries = []
    comparisons = []
    for model in RESPONDENT_MODELS:
        for budget in range(1, max_budget + 1):
            selected = [row for row in interview_rows if row["respondent_model"] == model and row["budget"] == budget]
            scores = {}
            for strategy in STRATEGIES:
                rows = [row for row in selected if row["strategy"] == strategy]
                scores[strategy] = _profile_scores(rows)
                interview_summaries.append({
                    "respondent_model": model, "budget": budget, "strategy": strategy,
                    "profile_count": len(scores[strategy]), "trial_count": len(rows),
                    "accuracy": mean(scores[strategy].values()),
                    "latency_p50_ms": percentile([row["latency_ms"] for row in rows], 0.5),
                    "latency_p95_ms": percentile([row["latency_ms"] for row in rows], 0.95),
                })
            for baseline in ("fixed", "random"):
                comparisons.append({
                    "respondent_model": model, "budget": budget, "contrast": f"adaptive-{baseline}",
                    **paired_difference_ci(scores["adaptive"], scores[baseline], seed=seed, samples=bootstrap_samples),
                })
    grounding_rows = []
    for condition in CONDITIONS:
        for case in cases:
            runtime_case = {key: value for key, value in case.items() if key != "expected"}
            times = []
            for _ in range(latency_repeats):
                trial_start = perf_counter()
                result = plan_reply(runtime_case, condition=condition)
                times.append((perf_counter() - trial_start) * 1000)
            grounding_rows.append({
                "case_id": case["id"], "profile_id": case["profile_id"],
                "category": case.get("category", "unspecified"), "condition": condition,
                "action": result["action"], "text": result["text"], "evidence_ids": result["evidence_ids"],
                "claims": result["claims"], "reason": result["reason"],
                "latency_ms": percentile(times, 0.5), **score_grounding(case, result),
            })
    return {
        "metadata": {
            **_execution_metadata(), "mode": "offline_synthetic_template",
            "seed": seed, "seeds": seeds, "max_budget": max_budget, "bootstrap_samples": bootstrap_samples,
            "latency_repeats": latency_repeats, "provider_requests": 0,
            "question_bank_sha256": _digest(bank), "grounding_cases_sha256": _digest(cases),
            "duration_seconds": perf_counter() - start, "limitation": LIMITATION,
            "question_bank_version": bank["version"], "interview_model": bank["model"],
            "condition_descriptions": CONDITION_DESCRIPTIONS, "latency_clock": "perf_counter wall elapsed",
            "respondent_models": {
                "in_model": "같은 우도 모델에서 응답을 샘플링한 낙관적 내부 모형 검증",
                "context_dependent": "은행 순서가 홀수인 질문에서 support 선호를 반전하는 모형 불일치 스트레스 검사",
            },
            "pairing": "같은 가상 profile/seed에서 모든 질문의 숨겨진 답변을 미리 고정; seed 평균 후 profile 쌍 재표집",
        },
        "interview_summary": interview_summaries, "interview_comparisons": comparisons,
        "grounding_summary": [
            {"condition": condition, **grounding_summary([row for row in grounding_rows if row["condition"] == condition])}
            for condition in CONDITIONS
        ],
        "interview_rows": interview_rows, "grounding_rows": grounding_rows,
    }


def _format(value: float | None) -> str:
    return "해당 없음" if value is None else f"{value:.3f}"


def render_markdown(report: dict) -> str:
    lines = [
        "# 연구 벤치마크 실행 결과", "", f"**{report['metadata']['limitation']}**", "",
        f"- 실행 방식: `{report['metadata']['mode']}`",
        f"- 공급자 요청: {report['metadata']['provider_requests']}건",
        f"- git revision: `{report['metadata']['git_revision']}`",
        f"- seed: {report['metadata'].get('seed', '미실행')}; 반복 seed 수: {report['metadata'].get('seeds', '미실행')}",
        "- 시뮬레이션 구간추정 단위: 반복 seed를 평균한 가상 profile. 실제 사람의 모집단 추론이 아닙니다.",
        "- 이론적 질문 예산만 비교했습니다. 실제 사람의 인터뷰 소요시간은 측정하지 않았습니다.", "",
        "## 인터뷰", "", "| 응답자 모형 | 질문 수 | 조건 | heldout 선택 정확도 | 계산 p50(ms) | 계산 p95(ms) |",
        "| --- | ---: | --- | ---: | ---: | ---: |",
    ]
    for row in report["interview_summary"]:
        lines.append(f"| {row['respondent_model']} | {row['budget']} | {row['strategy']} | {_format(row['accuracy'])} | {_format(row['latency_p50_ms'])} | {_format(row['latency_p95_ms'])} |")
    lines += ["", "## 적응형 조건과 비교군의 차이", "", "| 응답자 모형 | 질문 수 | 차이 | 평균 차이 | profile paired bootstrap 95% 구간 |", "| --- | ---: | --- | ---: | --- |"]
    for row in report["interview_comparisons"]:
        lines.append(f"| {row['respondent_model']} | {row['budget']} | {row['contrast']} | {_format(row['difference'])} | [{_format(row['ci95'][0])}, {_format(row['ci95'][1])}] |")
    lines += ["", "## 근거 계획", "", "| 조건 | 사례 수 | 답변률 | 답변 가능한 사례의 유효 답변률 | 답변 중 오류율 | 주장 중 근거 오류율 | 전체 사례 정확도 |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for row in report["grounding_summary"]:
        lines.append(f"| {row['condition']} | {row['case_count']} | {_format(row['coverage'])} | {_format(row['valid_answer_rate'])} | {_format(row['selective_risk'])} | {_format(row['unsupported_claim_rate'])} | {_format(row['case_accuracy'])} |")
    condition_note = ("조건 이름은 추출형 시뮬레이션의 설정 ID이며 강한 LLM baseline의 실행을 뜻하지 않습니다."
                      if report["interview_summary"] else "조건 이름은 외부 결과의 식별자입니다. 이 채점기는 실제 생성 모델·프롬프트·설정을 확인하지 않습니다.")
    lines += ["", condition_note, ""]
    lines += [f"- `{condition}`: {description}" for condition, description in report["metadata"]["condition_descriptions"].items()]
    lines += [
        "", "## 해석 제한", "",
        "- 합성 모드의 응답자는 알려진 가설 모델 또는 맥락 의존 스트레스 모형입니다. 실제 참여자 개인화 성능을 증명하지 않습니다.",
        "- 합성 근거 조건은 동일한 구조화 입력의 추출형 템플릿 처리입니다. 외부 주석 모드에서도 이 도구는 자유 생성 응답의 의미적 함의를 자동 검증하지 않습니다.",
        "- 오류율의 분모가 0이면 0으로 성공 처리하지 않고 해당 없음으로 표시합니다. 모든 질문을 거절하는 방식은 유효 답변률로 구분됩니다.",
        "- 내용은 수동 라벨의 근거 ID·원문 주장·행동으로 채점합니다. 의료적 적절성·환자 이해·치료 효과는 평가하지 않았습니다.",
        "- runtime은 이 기기에서 측정한 Python 계산 경로입니다. 측정 재현 시 시스템 부하에 따라 달라집니다.", "",
    ]
    return "\n".join(lines)


def _chart(rows: list[dict], model: str) -> str:
    width, height, left, top = 640, 300, 55, 25
    plot_width, plot_height = 550, 220
    budgets = sorted({row["budget"] for row in rows})
    def point(budget, accuracy):
        return left + plot_width * (budget - budgets[0]) / max(1, budgets[-1] - budgets[0]), top + plot_height * (1 - accuracy)
    elements = [f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="{html.escape(model)} 질문 예산별 선택 정확도">']
    elements += [f'<line x1="{left}" y1="{top+plot_height}" x2="{left+plot_width}" y2="{top+plot_height}" stroke="#777"/>', f'<line x1="{left}" y1="{top}" x2="{left}" y2="{top+plot_height}" stroke="#777"/>']
    for value in (0, 0.25, 0.5, 0.75, 1):
        _, y = point(budgets[0], value)
        elements.append(f'<text x="10" y="{y+4}" font-size="12">{value:.2f}</text>')
    for budget in budgets:
        x, _ = point(budget, 0)
        elements.append(f'<text x="{x-4}" y="{top+plot_height+22}" font-size="12">{budget}</text>')
    for strategy, color in zip(STRATEGIES, ("#777777", "#2478a8", "#52672e")):
        selected = sorted([row for row in rows if row["strategy"] == strategy], key=lambda row: row["budget"])
        points = " ".join(f"{x:.1f},{y:.1f}" for x, y in [point(row["budget"], row["accuracy"]) for row in selected])
        elements.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="3"/>')
    elements.append('<text x="280" y="292" font-size="13">질문 수 (fixed: 회색 · random: 파랑 · adaptive: 초록)</text></svg>')
    return "".join(elements)


def render_html(report: dict) -> str:
    charts = "".join(f"<h2>{html.escape(model)}</h2>" + _chart([row for row in report["interview_summary"] if row["respondent_model"] == model], model) for model in RESPONDENT_MODELS) if report["interview_summary"] else "<p>인터뷰 시뮬레이션은 실행하지 않았습니다.</p>"
    table_rows = "".join(f"<tr><td>{html.escape(row['condition'])}</td><td>{_format(row['coverage'])}</td><td>{_format(row['selective_risk'])}</td><td>{_format(row['valid_answer_rate'])}</td></tr>" for row in report["grounding_summary"])
    return '<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>오프라인 연구 벤치마크</title><style>body{font:16px/1.7 system-ui;max-width:960px;margin:32px auto;padding:0 20px;color:#263024}svg{width:100%;max-width:760px}table{border-collapse:collapse;width:100%}th,td{padding:8px;border-bottom:1px solid #ddd;text-align:left}.limit{background:#f4f6f1;padding:16px}pre{white-space:pre-wrap;font:inherit}</style><h1>오프라인 연구 벤치마크</h1><p class="limit">' + html.escape(report['metadata']['limitation']) + '</p>' + charts + '<h2>근거 계획: 답변률과 오류율</h2><table><thead><tr><th>조건</th><th>전체 답변률</th><th>답변 중 오류율</th><th>답변 가능한 사례의 유효 답변률</th></tr></thead><tbody>' + table_rows + '</tbody></table><h2>전체 결과·가정·구간추정</h2><pre>' + html.escape(render_markdown(report)) + '</pre></html>'


def write_report(report: dict, output: Path) -> None:
    output = Path(output)
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("output must be a new or empty directory")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    (output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "report.md").write_text(render_markdown(report), encoding="utf-8")
    (output / "report.html").write_text(render_html(report), encoding="utf-8")
    for name in ("interview", "grounding"):
        rows = report[f"{name}_rows"]
        with (output / f"{name}.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]) if rows else ["not_run"])
            writer.writeheader()
            for row in rows:
                values = {key: json.dumps(value, ensure_ascii=False) if isinstance(value, (list, dict)) else value for key, value in row.items()}
                # 외부 주석의 텍스트를 스프레드시트 수식으로 실행하지 않는다.
                writer.writerow({key: "'" + value if isinstance(value, str) and value.lstrip().startswith(("=", "+", "-", "@")) else value for key, value in values.items()})
