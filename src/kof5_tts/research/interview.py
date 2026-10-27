"""가상 표현 선호 가설을 베이즈 갱신하는 오프라인 인터뷰 연구 모형.

질문의 signal과 lapse는 연구자가 정한 가정이며 실제 보호자에서 추정한 값이 아니다.
같은 우도로 만든 가상 응답자에서의 점수는 현실의 개인화 성능을 입증하지 않는다.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import random
import re

BANK_PATH = Path(__file__).resolve().parents[3] / "configs/research/interview.json"
STYLE_VALUES = {
    "support": ["acknowledge", "plain"],
    "initiative": ["ask", "offer"],
    "detail": ["brief", "elaborate"],
}
STRATEGIES = ("fixed", "random", "adaptive")


def _number(value, lower: float, upper: float) -> bool:
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and lower <= value <= upper)


def _identifier(value) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[a-z][a-z0-9_-]{0,63}", value) is not None


def _style(value, *, complete=False) -> bool:
    return (isinstance(value, dict) and bool(value)
            and (not complete or set(value) == set(STYLE_VALUES))
            and all(key in STYLE_VALUES and item in STYLE_VALUES[key] for key, item in value.items()))


def validate_question_bank(bank: dict) -> None:
    if (not isinstance(bank, dict) or bank.get("version") != "kof5-interview-v2"
            or bank.get("dimensions") != STYLE_VALUES):
        raise ValueError("지원하지 않는 질문 은행 형식입니다.")
    model = bank.get("model")
    if not isinstance(model, dict) or not _number(model.get("lapse"), 0.001, 0.999):
        raise ValueError("응답 잡음 lapse는 0.001~0.999여야 합니다.")
    hypotheses, questions = bank.get("hypotheses"), bank.get("questions")
    if (not isinstance(hypotheses, list) or not 1 <= len(hypotheses) <= 16
            or not isinstance(questions, list) or not 2 <= len(questions) <= 16):
        raise ValueError("가설과 질문 수가 허용 범위를 벗어났습니다.")
    hypothesis_ids, styles = set(), set()
    for hypothesis in hypotheses:
        if (not isinstance(hypothesis, dict) or not _identifier(hypothesis.get("id"))
                or hypothesis["id"] in hypothesis_ids or not _style(hypothesis.get("style"), complete=True)
                or not _number(hypothesis.get("prior"), 1e-9, 1e9)):
            raise ValueError("유효하지 않거나 중복된 선호 가설입니다.")
        style = tuple(hypothesis["style"][key] for key in STYLE_VALUES)
        if style in styles:
            raise ValueError("선호 가설의 스타일은 서로 달라야 합니다.")
        styles.add(style)
        hypothesis_ids.add(hypothesis["id"])
    question_ids, splits = set(), set()
    for question in questions:
        if (not isinstance(question, dict) or not _identifier(question.get("id"))
                or question["id"] in question_ids or question.get("split") not in {"elicitation", "heldout"}
                or not isinstance(question.get("scenario"), str) or not 1 <= len(question["scenario"]) <= 500
                or not _number(question.get("signal"), 0.01, 5)):
            raise ValueError("유효하지 않거나 중복된 질문입니다.")
        options = question.get("options")
        if not isinstance(options, list) or not 2 <= len(options) <= 4:
            raise ValueError("질문에는 2~4개의 선택지가 필요합니다.")
        option_ids = set()
        for option in options:
            if (not isinstance(option, dict) or not _identifier(option.get("id"))
                    or option["id"] in option_ids or not isinstance(option.get("text"), str)
                    or not 1 <= len(option["text"]) <= 500
                    or any(not isinstance(option.get(key), str) or not 1 <= len(option[key]) <= 500
                           for key in ("casual_text", "mixed_text"))
                    or not _style(option.get("style"))):
                raise ValueError("유효하지 않거나 중복된 선택지입니다.")
            option_ids.add(option["id"])
        question_ids.add(question["id"])
        splits.add(question["split"])
    if splits != {"elicitation", "heldout"}:
        raise ValueError("인터뷰 질문과 미관측 평가 질문을 분리해야 합니다.")


def load_question_bank(path: str | Path | None = None) -> dict:
    bank = json.loads(Path(path if path is not None else BANK_PATH).read_text(encoding="utf-8"))
    validate_question_bank(bank)
    return bank


def initial_posterior(bank: dict) -> dict[str, float]:
    total = sum(item["prior"] for item in bank["hypotheses"])
    return {item["id"]: item["prior"] / total for item in bank["hypotheses"]}


def option_likelihoods(bank: dict, hypothesis: dict, question: dict) -> dict[str, float]:
    """가설별 선택 확률: style 일치 점수의 softmax와 균일 lapse 혼합."""
    scores = [question["signal"] * sum(1 if hypothesis["style"][key] == value else -1
              for key, value in option["style"].items()) for option in question["options"]]
    maximum = max(scores)
    weights = [math.exp(score - maximum) for score in scores]
    total = sum(weights)
    lapse, count = bank["model"]["lapse"], len(weights)
    return {option["id"]: (1 - lapse) * weight / total + lapse / count
            for option, weight in zip(question["options"], weights)}


def question_probabilities(bank: dict, posterior: dict[str, float], question: dict) -> dict[str, float]:
    result = {option["id"]: 0.0 for option in question["options"]}
    for hypothesis in bank["hypotheses"]:
        for option_id, probability in option_likelihoods(bank, hypothesis, question).items():
            result[option_id] += posterior[hypothesis["id"]] * probability
    return result


def update_posterior(bank: dict, posterior: dict[str, float], question: dict, option_id: str) -> dict[str, float]:
    if option_id not in {option["id"] for option in question["options"]}:
        raise ValueError("질문에 없는 선택지입니다.")
    weights = {hypothesis["id"]: posterior[hypothesis["id"]]
               * option_likelihoods(bank, hypothesis, question)[option_id] for hypothesis in bank["hypotheses"]}
    total = sum(weights.values())
    return {key: value / total for key, value in weights.items()}


def entropy(posterior: dict[str, float]) -> float:
    return -sum(value * math.log2(value) for value in posterior.values() if value > 0)


def expected_information_gain(bank: dict, posterior: dict[str, float], question: dict) -> float:
    expected = sum(probability * entropy(update_posterior(bank, posterior, question, option_id))
                   for option_id, probability in question_probabilities(bank, posterior, question).items())
    return max(0.0, entropy(posterior) - expected)


def _select_question(bank: dict, posterior: dict[str, float], answered: set[str], strategy: str, order: list[dict]):
    candidates = [question for question in order if question["id"] not in answered]
    if not candidates:
        return None
    if strategy == "adaptive":
        return max(candidates, key=lambda question: expected_information_gain(bank, posterior, question))
    return candidates[0]


def interview_state(answers: list[dict], strategy: str = "adaptive", seed: int = 0,
                    budget: int = 8, question_bank: dict | None = None) -> dict:
    bank = load_question_bank() if question_bank is None else question_bank
    validate_question_bank(bank)
    if strategy not in STRATEGIES:
        raise ValueError("질문 전략은 fixed/random/adaptive 중 하나여야 합니다.")
    if not isinstance(seed, int) or isinstance(seed, bool) or not -(2**31) <= seed < 2**31:
        raise ValueError("seed는 32비트 정수여야 합니다.")
    order = [question for question in bank["questions"] if question["split"] == "elicitation"]
    if not isinstance(budget, int) or isinstance(budget, bool) or not 0 <= budget <= len(order):
        raise ValueError("질문 예산이 허용 범위를 벗어났습니다.")
    if not isinstance(answers, list) or len(answers) > budget:
        raise ValueError("응답 수가 질문 예산을 초과했습니다.")
    if strategy == "random":
        random.Random(seed).shuffle(order)
    posterior, answered = initial_posterior(bank), set()
    written_answers, reflected_count = [], 0
    for answer in answers:
        if (not isinstance(answer, dict)
                or set(answer) not in ({"question_id", "option_id"}, {"question_id", "text"},
                                      {"question_id", "text", "option_id"})
                or not _identifier(answer.get("question_id"))
                or ("option_id" in answer and not _identifier(answer["option_id"]))
                or ("text" in answer and (not isinstance(answer["text"], str)
                                         or not 1 <= len(answer["text"]) <= 500 or not answer["text"].strip()))):
            raise ValueError("질문 ID와 선택지 또는 500자 이내의 답변을 확인해주세요.")
        question = _select_question(bank, posterior, answered, strategy, order)
        if question is None or question["id"] != answer["question_id"]:
            raise ValueError("응답 순서가 선택된 인터뷰 질문과 다릅니다.")
        if "option_id" in answer:
            posterior = update_posterior(bank, posterior, question, answer["option_id"])
            reflected_count += 1
        if "text" in answer:
            # Free text needs explicit user annotation; never infer a style from keywords.
            written_answers.append({"question_id": question["id"], "scenario": question["scenario"],
                                    "text": answer["text"], "reflected": "option_id" in answer})
        answered.add(question["id"])
    done = len(answers) == budget
    question = None if done else _select_question(bank, posterior, answered, strategy, order)
    style = {}
    for key, values in STYLE_VALUES.items():
        style[key] = max(values, key=lambda value: sum(posterior[hypothesis["id"]]
                         for hypothesis in bank["hypotheses"] if hypothesis["style"][key] == value))
    heldout = []
    for heldout_question in bank["questions"]:
        if heldout_question["split"] != "heldout":
            continue
        probabilities = question_probabilities(bank, posterior, heldout_question)
        option = max(heldout_question["options"], key=lambda item: probabilities[item["id"]])
        heldout.append({"question_id": heldout_question["id"], "scenario": heldout_question["scenario"],
                        "option_id": option["id"], "text": option["text"], "casual_text": option["casual_text"],
                        "mixed_text": option["mixed_text"], "probabilities": probabilities})
    bits = entropy(posterior)
    return {
        "method": "discrete-bayesian-synthetic-v2", "bank_version": bank["version"],
        "strategy": strategy, "seed": seed, "answered_count": len(answers), "budget": budget, "done": done,
        "next_question": ({"id": question["id"], "scenario": question["scenario"],
                           "options": [{key: option[key] for key in ("id", "text", "casual_text", "mixed_text")} for option in question["options"]]}
                          if question else None),
        "predicted_style": style, "posterior": posterior, "entropy_bits": bits,
        "uncertainty": bits / math.log2(len(posterior)) if len(posterior) > 1 else 0.0,
        "heldout_predictions": heldout,
        "written_answers": written_answers, "reflected_count": reflected_count,
    }
