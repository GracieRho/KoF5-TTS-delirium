# 구현·검증 기록

날짜: 2026-10-27. 대상은 학회 발표용 오프라인 연구 도구다. 실제 환자·참여자 모집·유료 API·음성 생성·배포는 실행하지 않았다.

## 구현

- 8개 선호 가설, 한국어 인터뷰 질문 8개·heldout 4개, 베이즈 갱신·EIG 선택, fixed/random/adaptive 비교.
- 출처·프로필·승인·시간·철회·개정·상충을 적용하는 구조화 근거 계획과 수동 라벨 사례 33개.
- 질문 예산별 시뮬레이션, 사례별 근거 지표, profile 단위 paired bootstrap, 로컬 계산 시간 및 재현 메타데이터.
- 별도 합성 연구 화면·opt-in API, 임시 메모리 상태와 명시적 내보내기. 기존 로그인·환자 경로에 연구 자료를 연결하지 않음.
- 동의 성인 연구 프로토콜·균형 배정·빈 CSV, 선호/쌍대/음성 2×2/청취 지연/핵심정보 분석 도구.
- 외부 생성·사람 주석 결과의 오프라인 채점 및 정답을 제거한 입력 manifest 준비.

## 자동 검증

- 외부 socket 연결 차단 상태의 Python 전체 테스트: 134개 통과.
- 웹 전체 Vitest: 31파일·88개 테스트 통과. TypeScript/Vite 빌드 통과.
- 아키텍처 생성·`--check`, 생성기 단위 테스트 7개, `git diff --check` 통과.
- 기존 테스트 경고: Starlette의 httpx TestClient 지원 폐기 예정 안내, 기존 FamilyMaterialReview의 p/div 중첩 및 Select key 경고. 이번 연구 변경과 무관한 경고이며 수정 범위를 확대하지 않았다.

## 최종 오프라인 실행

실행 소스는 `0e8dc937e7c37cb390af1cbe20e3962e5062c182`이며 실행 시작 시 Git dirty=false였다. 문서·화면 캡처만 이후 추가했다. 공급자 key 없이 외부 socket 연결을 막은 실행에서 아래 명령을 완료했다.

```bash
python3 scripts/benchmark_research.py --output runs/research/final-20261027/benchmark
python3 scripts/benchmark_research.py --export-inputs runs/research/final-20261027/generation-inputs.jsonl
python3 scripts/prepare_research_study.py --output runs/research/final-20261027/study --participants 12 --seed 7
```

Python 3.15.0, macOS arm64, seed=7, seeds=3, budget=1–5, bootstrap=1000, latency repeats=3. 인터뷰 720회·근거 비교 132행. 실행 시간 1.286초는 이 작은 로컬 계산 전체의 경과 시간이며 공급자·음성 지연이 아니다. 원시 산출물은 Git 제외 경로에 보관했다.

### 질문 5개 예산의 가상 응답자 결과

| 응답자 가정 | 고정 | 무작위 | 적응형 |
| --- | ---: | ---: | ---: |
| 인터뷰 엔진과 같은 우도 모형 | 80.21% | 72.92% | 86.46% |
| 질문 맥락에 따라 일부 선호를 반전한 모형 불일치 검사 | 67.71% | 64.58% | 65.63% |

각 셀은 8개 가상 프로필×3 seeds의 24 trials이며, 프로필 안에서 seed를 평균한 후 차이를 비교한다. 같은 모형으로 만든 응답자에서는 적응형이 높았지만 **모형 불일치에서는 고정 질문보다 낮았다**. 실제 보호자·독립 평가셋에서의 이득을 입증하지 않는다. 질문 signal/lapse와 선호 반전 규칙은 연구자가 정한 가정이다.

### 수동 라벨 개발 사례 33개

| 추출 규칙 | 전체 기대 동작·근거 일치 | 답변 가능 사례의 유효 응답률 | 답변한 사례의 오류율 |
| --- | ---: | ---: | ---: |
| 전체 문맥의 첫 승인 근거 | 22/33 | 7/10 | 11/18 |
| 키워드 순위 | 23/33 | 8/10 | 10/18 |
| 시간 처리 제거 | 26/33 | 8/10 | 7/15 |
| 출처·시간·철회·상충 적용 | 33/33 | 10/10 | 0/10 |

제안 규칙은 답변 가능 10개에 모두 답하고 나머지는 정책 응답 또는 abstention이었다. 이 33개는 로직을 개발하며 작성한 **회귀 사례**다. 첫 근거 선택·키워드 순위는 강한 LLM baseline이 아니며, 33/33이나 오류 0을 실제 LLM 안전성으로 일반화하지 않는다.

### 실험·음성 도구 실행

빈 양식은 가상 자리표시자 12명에 대한 배정표일 뿐 실제 참여자가 아니다. `study/synthetic-example/`의 명시적 합성 숫자만 사용해 `analyze_research_study.py`의 preferences/pairwise/voice/audio/critical 다섯 분석을 모두 실행했다. 결과는 각각 `runs/research/final-20261027/*-synthetic.json`에 있다. 실제 성인 선호·음성 파일·실제 첫 청취음 측정은 수행하지 않았다.

## 실제 화면 확인

연구 서버는 공급자 key와 관리 토큰 없이 `127.0.0.1:8767`에 띄웠다. 5개 적응형 질문 완료·예측 변경·heldout 표시, 1개 예산, 만료 일정의 네 조건 비교를 실제 브라우저에서 확인했다. 새로고침 시 응답 초기화도 확인했다. 같은 문장인 사례는 한국어 설명으로 구분한다.

- [데스크톱 전체 화면](../validation/adaptive-care-research/desktop.png)
- [390px 모바일 전체 화면](../validation/adaptive-care-research/mobile.png): viewport=390px, document scrollWidth=390px로 가로 넘침 없음.
- [만료 정보 처리 비교](../validation/adaptive-care-research/comparison.png)

일시적인 모바일 viewport는 복원했다. UI는 실제 연구 API만 호출하며 로그인을 요구하지 않는다. export·reset·설정 변경·실패·늦은 응답 폐기는 웹 회귀 테스트로도 검증했다.

## 해석 경계

자동 인터뷰 결과는 연구자가 정한 작은 가설과 잡음 모형의 결과다. 근거 회귀 사례는 설계·개발에 사용한 데이터이며, heldout 자유 생성 LLM 안전성 평가가 아니다. 기존 네 조건도 각 추출 규칙을 비교하는 것으로 강한 LLM baseline의 우월성을 입증하지 않는다. 실제 임상 효과·iPad 첫 실제 소리 지연·실제 보호자 선호는 미측정이다.

실제 환자 사용은 기존 Gate07 및 기관·임상 검토가 필요하다. 이 변경은 임상 문구를 환자 경로에 배포하거나 환자 시험을 승인하지 않는다.
