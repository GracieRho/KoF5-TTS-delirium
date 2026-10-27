# 개인화 연구 화면 확인

2026-10-27, `feat/adaptive-care-research`의 실제 loopback 서버를 in-app browser로 확인했다. 모든 예시는 가상 정보이며 provider key·로그인·원격 DB·실제 음성 생성 없이 실행했다.

- `desktop.png`: 인터뷰 1개 예산 완료, 미관측 상황 예측, 만료 일정 비교의 전체 화면. 별도로 5개 적응형 질문 완료도 확인했다.
- `mobile.png`: 390×844 viewport에서 같은 상태. 문서 폭=viewport 폭=390px. 임시 viewport는 확인 후 원래대로 복원했다.
- `comparison.png`: 만료 일정에서 근거 처리 네 규칙의 차이. 첫 항목·키워드·시간 제외는 오래된 근거를 선택하고, 출처·시간 적용은 사용 가능한 현재 근거가 없다고 응답했다.

스크린샷은 규칙 기반 합성 예시의 실제 실행 화면이며 자유 생성 LLM·인격 복제·음성 품질·치료 효과의 증거가 아니다. 연구 본문은 [구현·검증 기록](../../research/validation.md)을 따른다.
