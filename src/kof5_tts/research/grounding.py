"""구조화된 가상 근거를 선택·인용하는 오프라인 비교 모듈.

자유 생성이나 의미적 사실 검증기가 아니다. 모든 조건은 같은 근거를 받으며,
topic_key는 호출자가 지정한 정답 검색어가 아닌 사전 정의된 상황의 주제다.
"""

from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
import re

from kof5_tts.companion import DISSENT_PHRASES, END_PHRASES, RISK_PHRASES, policy_reply


CONDITIONS = ("full_context", "rag", "no_time", "proposed")
CASE_PATH = Path(__file__).resolve().parents[3] / "configs/research/grounding_cases.json"
STYLE_VALUES = {
    "address": ("neutral", "familiar"),
    "ending": ("polite", "casual"),
    "support": ("plain", "acknowledge"),
}


def _text(value: object, field: str, maximum: int = 500) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise ValueError(f"invalid {field}")
    return value


def _time(value: object, field: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(_text(value, field, 40).replace("Z", "+00:00"))
    except ValueError:
        raise ValueError(f"invalid {field}") from None
    if parsed.utcoffset() is None:
        raise ValueError(f"{field} must include timezone")
    return parsed


def _validate(case: dict) -> tuple[datetime, list[dict]]:
    if not isinstance(case, dict) or "expected" in case:
        raise ValueError("case must be an object without evaluation labels")
    for field in ("id", "profile_id", "question", "topic_key"):
        _text(case.get(field), field)
    if not re.fullmatch(r"(?:family|hospital|policy)\.[a-z_]+", case["topic_key"]):
        raise ValueError("invalid topic_key")
    now = _time(case.get("now"), "now")
    records = case.get("evidence")
    if not isinstance(records, list) or len(records) > 100:
        raise ValueError("evidence must contain at most 100 records")
    indexed = {}
    for item in records:
        if not isinstance(item, dict):
            raise ValueError("invalid evidence record")
        for field in ("id", "profile_id", "key", "content", "source", "kind"):
            _text(item.get(field), "evidence." + field)
        if not re.fullmatch(r"(?:family|hospital)\.[a-z_]+", item["key"]):
            raise ValueError("invalid evidence key")
        if item["source"] not in {"guardian", "hospital_staff"}:
            raise ValueError("invalid evidence source")
        if item["kind"] not in {"memory", "current"}:
            raise ValueError("invalid evidence kind")
        if any(type(item.get(field)) is not bool for field in ("approved", "revoked")):
            raise ValueError("approval and revocation must be booleans")
        verified = _time(item.get("verified_at"), "verified_at")
        start = _time(item.get("valid_from"), "valid_from")
        end = _time(item["valid_until"], "valid_until") if item.get("valid_until") is not None else None
        if end is not None and (end <= start or end < verified):
            raise ValueError("invalid evidence validity interval")
        supersedes = item.get("supersedes", [])
        if (not isinstance(supersedes, list) or len(supersedes) > 100
                or any(not isinstance(identifier, str) or not identifier for identifier in supersedes)
                or len(set(supersedes)) != len(supersedes)):
            raise ValueError("invalid supersedes list")
        if item["id"] in indexed:
            raise ValueError("duplicate evidence id")
        indexed[item["id"]] = item
    for item in records:
        for identifier in item.get("supersedes", []):
            previous = indexed.get(identifier)
            if (previous is None or identifier == item["id"]
                    or previous["profile_id"] != item["profile_id"]
                    or previous["key"] != item["key"]):
                raise ValueError("supersession must reference a different record for the same profile and key")
            if _time(item["verified_at"], "verified_at") < _time(previous["verified_at"], "verified_at"):
                raise ValueError("supersession must not precede its previous record")
    # Equal timestamps still need a cycle check to avoid silently discarding all facts.
    def visit(identifier: str, visiting: set[str], visited: set[str]) -> None:
        if identifier in visiting:
            raise ValueError("cyclic supersession")
        if identifier in visited:
            return
        visiting.add(identifier)
        for previous in indexed[identifier].get("supersedes", []):
            visit(previous, visiting, visited)
        visiting.remove(identifier)
        visited.add(identifier)
    visited: set[str] = set()
    for identifier in indexed:
        visit(identifier, set(), visited)
    return now, records


def load_grounding_cases(path: str | Path | None = None) -> list[dict]:
    data = json.loads(Path(path if path is not None else CASE_PATH).read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("version") != "grounding-cases-v1":
        raise ValueError("unsupported grounding case version")
    cases = data.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("case bank must be a nonempty list")
    identifiers = set()
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError("invalid case")
        _validate({key: value for key, value in case.items() if key != "expected"})
        if case["id"] in identifiers:
            raise ValueError("duplicate case id")
        identifiers.add(case["id"])
        expected = case.get("expected")
        if (not isinstance(expected, dict)
                or expected.get("action") not in {"answer", "abstain", "identity", "stop", "refer"}
                or not isinstance(expected.get("evidence_ids"), list)
                or not isinstance(expected.get("claims"), list)
                or type(expected.get("answerable")) is not bool):
            raise ValueError("invalid evaluation label")
        if expected["answerable"] != (expected["action"] == "answer"):
            raise ValueError("inconsistent answerability label")
        for field in ("evidence_ids", "claims"):
            if any(not isinstance(value, str) or not value for value in expected[field]):
                raise ValueError("invalid evaluation label entries")
        if (len(set(expected["evidence_ids"])) != len(expected["evidence_ids"])
                or not set(expected["evidence_ids"]) <= {item["id"] for item in case["evidence"]}
                or (expected["action"] != "answer" and (expected["evidence_ids"] or expected["claims"]))):
            raise ValueError("inconsistent evaluation evidence")
    return cases


def _style(style: dict | None) -> dict[str, str]:
    if style is None:
        style = {}
    if not isinstance(style, dict) or set(style) - set(STYLE_VALUES):
        raise ValueError("invalid style")
    result = {}
    for field, choices in STYLE_VALUES.items():
        value = style.get(field, choices[0])
        if value not in choices:
            raise ValueError("invalid style value")
        result[field] = value
    return result


def _render(claim: str, style: dict[str, str]) -> str:
    prefix = ""
    if style["support"] == "acknowledge":
        prefix += "천천히 함께 확인할게요. " if style["ending"] == "polite" else "천천히 같이 확인해볼게. "
    if style["address"] == "familiar":
        prefix += "편하게 들어요. " if style["ending"] == "polite" else "편하게 들어봐. "
    frame = "확인된 내용이에요: " if style["ending"] == "polite" else "확인된 내용이야: "
    return prefix + frame + "“" + claim + "”"


def _result(action: str, text: str, reason: str, record: dict | None = None) -> dict:
    return {
        "action": action, "text": text, "reason": reason,
        "evidence_ids": [record["id"]] if record is not None else [],
        "claims": [record["content"]] if record is not None else [],
    }


def plan_reply(case: dict, condition: str = "proposed", style: dict | None = None) -> dict:
    """같은 구조화 근거에서 선택 규칙만 비교한다. 네트워크·LLM 호출은 없다."""
    if condition not in CONDITIONS:
        raise ValueError("unknown grounding condition")
    now, records = _validate(case)
    selected_style = _style(style)
    question = case["question"]
    if any(phrase in question for phrase in (*DISSENT_PHRASES, *END_PHRASES)) or question.strip(".!? ") == "싫어":
        return _result("stop", "대화를 멈출게요.", "dissent")
    if any(phrase in question for phrase in RISK_PHRASES):
        return _result("refer", policy_reply(question, "auxiliary_alert_candidate", now), "risk")
    if re.search(r"(?:진짜|실제).{0,12}(?:딸|아들|가족|보호자)|(?:너|당신).{0,8}(?:누구|AI)|AI야", question, re.IGNORECASE):
        return _result("identity", "저는 실제 가족 본인이 아니라 AI 대화 도우미예요.", "identity")
    policy = policy_reply(question, "accepted", now)
    if policy is not None:
        if "의료 판단" in policy:
            return _result("refer", policy, "medical")
        if "실제 가족" in policy:
            return _result("identity", policy, "identity")
    eligible = [item for item in records
                if item["profile_id"] == case["profile_id"] and item["key"] == case["topic_key"]
                and item["approved"]
                and item["source"] == ("guardian" if item["key"].startswith("family.") else "hospital_staff")
                and item["kind"] == ("current" if item["key"].startswith("hospital.")
                                      or item["key"] == "family.visit" else "memory")]
    if not eligible:
        return _result("abstain", "확인된 정보가 없어서 답하기 어려워요.", "no_authorized_evidence")
    if condition == "full_context":
        selected = eligible[0]
    elif condition == "rag":
        terms = re.findall(r"[가-힣A-Za-z0-9]{2,}", question)
        selected = max(eligible, key=lambda item: (
            sum(term in item["content"] for term in terms),
            _time(item["verified_at"], "verified_at"), item["id"],
        ))
    else:
        def started(item: dict) -> bool:
            return (_time(item["verified_at"], "verified_at") <= now
                    and _time(item["valid_from"], "valid_from") <= now)
        effective = [item for item in eligible if condition == "no_time" or started(item)]
        superseded = {identifier for item in effective for identifier in item.get("supersedes", [])}
        current = [item for item in effective if not item["revoked"] and item["id"] not in superseded
                   and (condition == "no_time" or item.get("valid_until") is None
                        or now < _time(item["valid_until"], "valid_until"))]
        if not current:
            return _result("abstain", "현재 사용할 수 있는 확인 정보가 없어요.", "no_current_evidence")
        if len({item["content"] for item in current}) > 1:
            return _result("abstain", "확인 정보가 서로 달라서 담당자에게 확인이 필요해요.", "conflicting_evidence")
        selected = max(current, key=lambda item: (_time(item["verified_at"], "verified_at"), item["id"]))
    text = _render(selected["content"], selected_style)
    # The renderer quotes one exact source clause; this is not an entailment test for free text.
    if text.count("“" + selected["content"] + "”") != 1:
        raise ValueError("source clause was not preserved")
    return _result("answer", text, "selected_evidence", selected)
