"""명시적으로 켠 loopback 서버의 가상 연구 예시만 제공한다."""

import os
from typing import Literal

from fastapi import APIRouter, HTTPException, Request
from fastapi.routing import APIRoute
from pydantic import BaseModel, ConfigDict, Field

from kof5_tts.research.grounding import load_grounding_cases, plan_reply
from kof5_tts.research.interview import interview_state

STRATEGIES = ("fixed", "random", "adaptive")
CONDITIONS = ("full_context", "rag", "no_time", "proposed")


class ResearchRoute(APIRoute):
    def get_route_handler(self):
        handler = super().get_route_handler()

        async def guarded(request: Request):
            if (os.environ.get("KOF5_RESEARCH_ENABLED") != "1"
                    or os.environ.get("VERCEL")
                    or request.url.hostname not in {"127.0.0.1", "localhost", "::1"}
                    or not request.client
                    or request.client.host not in {"127.0.0.1", "::1", "testclient"}):
                raise HTTPException(403, "연구 화면은 명시적으로 켠 개인 컴퓨터에서만 사용할 수 있습니다.")
            origin = request.headers.get("origin")
            if origin and origin != f"{request.url.scheme}://{request.url.netloc}":
                raise HTTPException(403, "같은 연구 화면에서 다시 요청해주세요.")
            body = bytearray()
            async for chunk in request.stream():
                if len(body) + len(chunk) > 16_384:
                    raise HTTPException(413, "연구 요청이 너무 큽니다.")
                body.extend(chunk)
            request._body = bytes(body)
            response = await handler(request)
            response.headers["Cache-Control"] = "no-store"
            return response

        return guarded


router = APIRouter(route_class=ResearchRoute)


class ResearchInput(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Answer(ResearchInput):
    question_id: str = Field(min_length=1, max_length=80)
    option_id: str = Field(min_length=1, max_length=80)


class InterviewInput(ResearchInput):
    answers: list[Answer] = Field(default_factory=list, max_length=8)
    strategy: Literal["fixed", "random", "adaptive"] = "adaptive"
    seed: int = Field(default=0, ge=0, le=4_294_967_295, strict=True)
    budget: int = Field(default=5, ge=1, le=8, strict=True)


class Style(ResearchInput):
    address: Literal["neutral", "familiar"] = "neutral"
    ending: Literal["polite", "casual"] = "polite"
    support: Literal["acknowledge", "plain"] = "plain"


class PreviewInput(ResearchInput):
    case_id: str = Field(min_length=1, max_length=80)
    condition: Literal["full_context", "rag", "no_time", "proposed"] = "proposed"
    style: Style | None = None


@router.get("/research", include_in_schema=False)
def research_page():
    from kof5_tts.api import _portal_index
    return _portal_index()


@router.get("/research-api/catalog", include_in_schema=False)
def catalog():
    return {
        "cases": [{"id": case["id"], "profile_id": case["profile_id"],
                   "question": case["question"], "description": case.get("description", case["question"])}
                  for case in load_grounding_cases()],
        "strategies": STRATEGIES,
        "conditions": CONDITIONS,
        "default_budget": 5,
    }


@router.post("/research-api/interview", include_in_schema=False)
def interview(payload: InterviewInput):
    try:
        return interview_state(
            [answer.model_dump() for answer in payload.answers], payload.strategy,
            payload.seed, payload.budget,
        )
    except ValueError:
        raise HTTPException(422, "질문 순서와 선택지를 확인하거나 인터뷰를 초기화해주세요.") from None


@router.post("/research-api/preview", include_in_schema=False)
def preview(payload: PreviewInput):
    case = next((case for case in load_grounding_cases() if case["id"] == payload.case_id), None)
    if case is None:
        raise HTTPException(404, "가상 연구 상황을 찾을 수 없습니다.")
    case = {key: value for key, value in case.items() if key != "expected"}
    style = payload.style.model_dump() if payload.style is not None else None
    return plan_reply(case, payload.condition, style)
