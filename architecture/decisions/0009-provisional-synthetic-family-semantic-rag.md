# ADR-0009: 합성 가족 기억의 임시 semantic RAG 평가 설정

- 상태: 제안됨
- 작성일: 2026-09-16
- 적용 범위: 고정 합성 환자·합성 가족 기억의 내부 평가만
- 관련 문서: [PRD 기억 검색](../../docs/delirium-familiar-voice/03-context-and-guardian.md), [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)

## 결정 초안

[합성 migration](../../supabase/migrations/20260916123000_synthetic_family_embedding_rag.sql)과 [API](../../src/kof5_tts/api.py)의 현재 평가 설정은 `text-embedding-3-small` 1536차원, cosine 유사도 **0.75** 이상, 가족 기억 20~30건의 정확한 거리 정렬이다. 임계값은 임의 시험값이며 모델·제공업체 선정이나 환자 사용 기준이 아니다. 유효한 일반 기억·현재 보호자 연결·기기/동의 권한을 다시 확인하고, 벡터와 점수는 응답에 넣지 않는다.

## 검증과 변경 조건

한국어 질문의 관련 기억 재현율·정밀도, 피할 주제와 민감/만료 기억의 차단, 사실 충실도 및 임계값은 실제 평가셋으로 측정하지 않았다. embedding 입력이 공급자에 전송될 경우의 보존·학습·지역·삭제 계약도 [Gate07 공급자 검토](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md#14-cloud-provider-data-review) 대상이다. 합성 SQL/API 검사 결과와 한국어 품질 측정 후 모델·임계값·검색 방식을 다시 결정하며, Gate07과 기관 검토 전 실제 환자/가족 내용을 사용하지 않는다.
