# 한국어 보호자 표현 개인화 연구

학부생·석사생 중심 AI 학회 발표를 위한 실행 도구다. 연구 주제는 제한된 질문 예산에서의 표현 선호 예측과 출처·시간·철회 정보를 적용한 사실 선택이다. **인격 복제, 자유 생성의 사실 보장, 섬망 개선 효과를 입증한 결과는 아니다.**

- [연구·개발 계획](adaptive-care-plan.md)
- [동의 성인·블라인드·음성 요인실험 프로토콜](experiment-protocol.md)
- [구현·검증 결과와 재현 기록](validation.md)

## 실행

새 환경은 기존 프로젝트 의존성을 준비하고 웹을 빌드한다. 공급자 키와 Supabase 로그인은 연구 화면에 필요하지 않다.

```bash
uv sync
npm ci --prefix apps/portal_web
npm run build --prefix apps/portal_web
uv run python scripts/run_research.py --port 8767
```

`http://127.0.0.1:8767/research`에서 가상 자료 사용 안내를 확인한 뒤 질문을 시작한다. 응답 선택 → 예측 갱신 → 미관측 상황 예측 → 근거 처리 네 조건 비교 → 결과 내보내기 순서다. 선택 기록은 메모리에만 있으며 새로고침·초기화로 지워진다. 브라우저는 연구 API만 호출하고 기존 로그인 provider를 마운트하지 않는다.

연구 API는 `KOF5_RESEARCH_ENABLED=1`일 때 loopback에서만 열리며 Vercel·외부 Host/client·타 Origin을 거부한다. 연구 화면에 실제 환자 자료를 입력하지 않는다. 기존 `/studio`, `/hospital`, iPad와 원격 저장 경로에는 연구 자료를 연결하지 않았다.

## 오프라인 벤치마크

```bash
python3 scripts/benchmark_research.py --output runs/research/benchmark-v1
```

새 폴더에 `results.json`, `interview.csv`, `grounding.csv`, `report.md`, `report.html`을 만든다. HTML에는 질문 예산별 두 가상 응답자 모형의 곡선과 근거 조건별 지표가 있다. seed, 입력·구현 SHA256, 실행 Git revision/dirty 상태, Python·플랫폼과 로컬 계산 시간도 남긴다. 기존 결과는 덮어쓰지 않는다.

- 인터뷰: fixed/random/adaptive, 기본 8개 가상 프로필 × 3 seeds × 5 예산 × 3 전략 × 2 응답자 모형 = 720회. 같은 프로필·seed의 숨겨진 응답은 조건 간 공유한다. bootstrap 단위는 seed나 질문이 아닌 프로필이다.
- 근거: 수동 라벨 33개 × 4조건 = 132행. `full_context`는 첫 승인 근거 선택, `rag`는 키워드 순위, `no_time`은 시간 필터 제거, `proposed`는 유효성·철회·상충 적용이다. **강한 전체 문맥 LLM/RAG의 성능 비교가 아닌 추출 규칙의 회귀 검사**다.
- 답변 가능 사례의 유효 응답률과 답변한 사례의 오류를 함께 보고한다. 전체 거절을 성공으로 판정하지 않는다.
- latency는 Python 순수 함수의 경과 시간이다. 공급자/TTS/iPad 첫 청취음과 비교하지 않는다.

## 나중에 실제 생성 결과를 평가할 때

```bash
python3 scripts/benchmark_research.py --export-inputs runs/research/generation-inputs.jsonl
python3 scripts/benchmark_research.py --responses runs/research/reviewed-responses.jsonl --output runs/research/reviewed-v1
```

첫 명령은 채점 정답·사례 설명·category를 뺀 입력 manifest만 생성한다. `input.id`는 중립 식별자로 바꾸며, 바깥의 `case_id`·condition은 작업 배정과 결합용이므로 모델 프롬프트에 넣지 않는다. 동일 모델·프롬프트·정보 예산을 동결해 별도 승인된 생성 절차에서 응답을 얻고, 평가자가 실제 문장의 원자적 주장과 근거 원문을 대응해 주석한다. 의미 있는 근거 ID도 단서가 될 수 있으므로 본 실험에서는 중립 ID를 사용한 동결 평가셋을 새로 작성하고 개발용 회귀 사례와 분리한다.

두 번째 명령은 이미 주석한 JSONL만 읽는다. 각 행은 `case_id`, `condition`, `action`, `text`, `evidence_ids`, `claims`, `claims_reviewed: true`와 선택적인 `elapsed_ms`다. action은 answer/abstain/identity/stop/refer다. 모든 사례×네 조건을 정확히 한 번씩 제공해야 하며 누락·중복을 거부한다. claims는 모델의 자기 보고가 아닌 평가자의 정규화 주석이어야 한다. `claims_reviewed`는 도구가 사람 검토를 증명한다는 뜻이 아니다.

어느 명령도 LLM·TTS·ASR 요청을 실행하지 않는다. 실제 생성 호출·참여자 모집·음성 공개는 별도 범위이며 현재 실행하지 않았다.

## 참여자·음성 측정 도구

```bash
python3 scripts/prepare_research_study.py --output runs/research/study-v1 --participants 12 --seed 7
python3 scripts/analyze_research_study.py preferences runs/research/study-v1/synthetic-example/preferences.csv --output runs/research/study-v1/preferences-example.json --data-kind synthetic
```

준비 명령은 균형 배정표, 블라인드 키, 빈 주석 CSV, 도구 검증용 `synthetic-example/`을 만든다. 실제 참여자를 생성·등록·모집하지 않는다. 분석 종류는 preferences/pairwise/voice/audio/critical이다. 모든 합성 예시는 코드 검증용 가상 숫자다. 실험과 실제 청취 지연의 입력 기준은 [프로토콜](experiment-protocol.md)을 따른다.

## 검증

```bash
python3 -m unittest tests.unit.test_research_interview tests.unit.test_research_grounding tests.unit.test_research_benchmark tests.unit.test_research_experiment
uv run python -m unittest tests.integration.test_research_api tests.unit.test_research_runner
npm test --prefix apps/portal_web
python3 scripts/generate_architecture.py --check
python3 -m unittest scripts/test_generate_architecture.py
git diff --check
```

API tests는 외부 socket 연결을 차단하고 합성 자료만 사용한다. 실제 환자 시험은 기존 Gate07의 미완료 상태를 유지한다.
