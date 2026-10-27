# 대화 맞춤 화면 확인

## 실제 인증 후속 검수

- `speech-setup-v2.png`, `speech-setup-mobile-v2.png`: 실제 저장 자료에서 말투만 누락됐을 때의 수정 화면. 기존 기억/호칭을 확인하고 말투만 인라인으로 받는다.
- `authenticated-interpret-v2.png`: 실제 Supabase Auth 보호자 인증과 기존 SQLite 조회를 거친 무료 모델 해석, 진행 1/8과 실제 모델 성공.
- `authenticated-complete-v2.png`: 직접 입력 1개+선택 7개로 8/8 완료, 원문 보존/반영 확인.

인증·저장을 대체하지 않은 실제 로컬 연동 검수지만 계정과 자료는 개발용 가상 정보다. [실행 범위·24문장 결과](../../research/validation-authenticated.md)를 따른다. 검수 중 임시 말투는 원래대로 복원했다.

## 최초 v2 (합성 인증 fixture)

`interview-v2.png`와 `interview-v2-mobile.png`는 현재 UI와 실제 연구 API에 **합성 인증·보호자 저장 자료를 제공하는 격리된 QA 서버**를 연결한 화면이다. 직접 입력 우선 배치, 8문항, 네 표현, 무료 모델 선택·최대 3회 fallback 안내, 저장된 반존대·기억 제목, 인라인 탭을 확인한다. 실제 로그인·원격 DB·모델 분류 품질 검증으로 간주하지 않는다. 실제 무료 모델 호출 결과는 [현재 검증 기록](../../research/validation-v2.md)에 별도로 구분한다. 검수 후 QA 서버를 종료한다.

`fallback-v2.png`는 위 격리된 인증·저장 fixture에서 실제 무료 모델을 호출한 결과다. Gemma 4 26B A4B 실패 후 Nemotron 3 Ultra 성공, 총 2회 시도가 화면에 표시된다.

## 최초 v1 (이전 화면)

2026-10-27, `feat/adaptive-care-research`의 실제 loopback 서버를 in-app browser로 확인했다. 모든 예시는 가상 정보이며 provider key·로그인·원격 DB·실제 음성 생성 없이 실행했다.

- `desktop.png`: 인터뷰 1개 예산 완료, 미관측 상황 예측, 만료 일정 비교의 전체 화면. 별도로 5개 적응형 질문 완료도 확인했다.
- `mobile.png`: 390×844 viewport에서 같은 상태. 문서 폭=viewport 폭=390px. 임시 viewport는 확인 후 원래대로 복원했다.
- `comparison.png`: 만료 일정에서 근거 처리 네 규칙의 차이. 첫 항목·키워드·시간 제외는 오래된 근거를 선택하고, 출처·시간 적용은 사용 가능한 현재 근거가 없다고 응답했다.

스크린샷은 규칙 기반 합성 예시의 실제 실행 화면이며 자유 생성 LLM·인격 복제·음성 품질·치료 효과의 증거가 아니다. 연구 본문은 [구현·검증 기록](../../research/validation.md)을 따른다.
