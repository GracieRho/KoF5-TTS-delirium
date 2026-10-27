# 한국어 보호자 표현 개인화 연구

학부생·석사생 중심 AI 학회 발표를 위한 실행 도구다. 연구 주제는 제한된 질문 예산에서의 표현 선호 예측과 출처·시간·철회 정보를 적용한 사실 선택이다. **인격 복제, 자유 생성의 사실 보장, 섬망 개선 효과를 입증한 결과는 아니다. 현재 v2는 감정 반응·대화 주도·설명량의 표현 전략을 다루며 호칭·존댓말 여부는 저장된 설정을 사용한다.**

- [연구·개발 계획](adaptive-care-plan.md)
- [동의 성인·블라인드·음성 요인실험 프로토콜](experiment-protocol.md)
- [현재 v2 구현·검증 결과](validation-v2.md)
- [최초 v1 검증 기록](validation.md): 현재 질문은행과 점수를 직접 비교하지 않는다.

## 실행

새 환경은 기존 프로젝트 의존성을 준비하고 웹을 빌드한다. 대화 맞춤은 기존 보호자 로그인과 저장된 가족 소개·말투·일반 기억이 필요하다. 선택지와 원문 기록에는 생성 키가 필요 없고, 의미 해석을 사용할 때만 서버의 `OPENROUTER_API_KEY`를 읽는다.

```bash
uv sync
npm ci --prefix apps/portal_web
npm run build --prefix apps/portal_web
# 기존 보호자 포털과 동일한 로컬 Supabase·계정·DB 환경에서 실행
uv run python scripts/run_research.py --port 8767
```

`http://127.0.0.1:8767/studio?tab=personalize`에서 연다. `/research`는 이전 주소로 같은 화면을 보여준다. 홈의 `대화 맞춤` 메뉴와 브랜드/홈 복귀 링크를 사용한다. 본문은 `말투 인터뷰 / 답변 확인` 인라인 탭이다.

시작 시 기존 인증된 `/local-studio/state`를 조회한다. 가족 소개, 주 호칭, 평소 말투, 피해야 할 이야기가 아닌 기억이 없으면 `가족의 기억`으로 안내한다. 조회 실패는 빈 자료로 간주하지 않는다. 기존 자료의 말투가 없으면 존댓말·반말·반존대 중 직접 지정한다. 주 호칭 외 다른 호칭 6개까지 저장한다.

기본 8문항이며 12상황 중 8–12개를 선택한다. 각 질문의 네 표현은 설명·위로·질문·제안 방식으로 다르고, 말끝은 저장한 설정을 공통 적용한다. 일부 질문에 저장한 기억 제목을 쓴다. 직접 입력은 선택지보다 먼저 보인다. 원문만 기록하거나 가까운 표현을 직접 지정할 수도 있다. 원문을 기록했다는 이유만으로 표현을 학습했다고 표시하지 않는다.

연구 서버는 기존 로컬 보호자 설정(`KOF5_LOCAL_STUDIO`, `KOF5_STUDIO_DB`, `KOF5_SUPABASE_URL`, 공개 키, 소유자 ID)과 켜진 로컬 Supabase가 필요하다. 기존 `runs/local-studio/portal.env`의 설정을 사용하며, 이 실행기는 계정/DB를 자동 생성하지 않는다. Supabase 관리 PAT는 로그인 세션이나 프로젝트 공개 키를 대체하지 않는다.

`KOF5_RESEARCH_ENABLED=1` opt-in, loopback host/client, 동일 Origin, 64KiB 본문 한도와 Vercel 차단을 유지한다. 외부 모델 해석 API는 보호자 인증과 저장 자료를 서버에서도 확인한다. 인터뷰 원문·결과는 화면 메모리에만 남고 초기화·화면 종료로 지워진다. 명시적 JSON 내보내기에만 원문과 분류 출처를 담는다. 실제 환자 자료를 넣지 않는다.

## 직접 입력의 무료 모델 해석

루트 `.env`의 `OPENROUTER_API_KEY`를 서버에서만 읽는다. 작업 worktree에 키 파일이 없으면 같은 저장소 루트 `.env`를 확인하고, 기존 프로세스 환경값을 우선한다. 연구 경로에서는 이 키만 주입하며 `VERCEL_TOKEN`·`SUPABASE_ACCESS_TOKEN`을 주입하지 않는다. `.env.example`에는 변수명만 있다.

입력 옆에서 **문장과 질문·예시의 OpenRouter 전송에 동의**한 경우에만 `AI로 해석하고 계속`을 누를 수 있다. 저장된 가족 소개와 기억 전체는 보내지 않는다. 기본 모델은 `nvidia/nemotron-3-ultra-550b-a55b:free`다. Gemma 4 31B, Gemma 4 26B A4B, Nemotron 3 Super의 `:free` 모델도 선택할 수 있다. 요청 시작 시 공식 목록을 한 번 읽고, 각 후보를 시도하기 전에 요금과 지원 기능을 확인한다. prompt/completion/request 가격 상한 0, 출력 최대 300토큰, 응답 모델·JSON·비용 0원 검증을 모든 시도에 적용한다. 선택 모델이 실패하면 등록된 다른 무료 모델로 넘어가며 **최초 호출과 fallback을 합쳐 서로 다른 모델 최대 3회**다. 세 번 실패하면 구조화 오류와 `attempts`를 반환한다. 네 번째 모델이나 동일 모델 재시도는 없다. OpenRouter 내부 provider fallback도 끄고 앱에서 횟수를 관리한다. 키/인증/목록 조회 실패와 명시적 양수 비용 보고는 즉시 중단한다.

모델은 직접 쓴 문장의 의사소통 전략과 가까운 선택지를 해석한다. 모호하면 분류하지 않고 원문만 기록한다. 이는 인격 학습, 자유로운 환자 답변 생성, 임상 판단 기능이 아니다. 가설·베이즈 갱신과 네트워크 없는 벤치마크는 별도로 유지한다.

무료 공급자 혼잡·한도·데이터 정책 등의 모델 오류는 위 한도 안에서 fallback하며, 모두 실패하면 원문·현재 질문·진행 상태를 유지한다. 성공해도 실제 사용 모델과 시도 내역을 확인할 수 있다. 무료 공급자가 입력을 보관·학습에 사용할 수 있음을 전송 동의 옆에 표시한다. 이번 계정 설정은 사용자가 직접 허용했으며 앱이 계정 개인정보 설정을 바꾸지는 않는다. 실제 연결 상태는 [현재 검증 기록](validation-v2.md)을 확인한다. [OpenRouter 제공자 설정](https://openrouter.ai/docs/guides/routing/provider-selection), [모델 목록](https://openrouter.ai/api/v1/models).

## 오프라인 벤치마크

```bash
python3 scripts/benchmark_research.py --output runs/research/benchmark-v1
```

새 폴더에 `results.json`, `interview.csv`, `grounding.csv`, `report.md`, `report.html`을 만든다. HTML에는 질문 예산별 두 가상 응답자 모형의 곡선과 근거 조건별 지표가 있다. seed, 입력·구현 SHA256, 실행 Git revision/dirty 상태, Python·플랫폼과 로컬 계산 시간도 남긴다. 기존 결과는 덮어쓰지 않는다.

- 인터뷰: fixed/random/adaptive, 기본 8개 가상 프로필 × 3 seeds × 8 예산 × 3 전략 × 2 응답자 모형 = 1,152회. 같은 프로필·seed의 숨겨진 응답은 조건 간 공유한다. bootstrap 단위는 seed나 질문이 아닌 프로필이다.
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
