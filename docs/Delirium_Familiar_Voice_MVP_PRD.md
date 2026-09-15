# Delirium Familiar Voice Companion — MVP PRD

이 문서는 MVP PRD의 인덱스입니다. 기능 PRD의 0–65절은 아래 여섯 문서에 이어집니다. 실제 환자 대상 시험에는 별도의 안전·윤리 게이트가 적용됩니다.

| 문서 | 원문 절 | 내용 |
| --- | --- | --- |
| [제품 방향과 범위](delirium-familiar-voice/01-vision-and-scope.md) | 0–5 | 문제, 가설, 제외 범위, 사용자, 전체 UX |
| [환자 음성 대화](delirium-familiar-voice/02-patient-conversation.md) | 6–21 | 상시 대기, 활성화, 대화 상태, 시작 경로, 정체성 정책 |
| [맥락과 보호자 등록](delirium-familiar-voice/03-context-and-guardian.md) | 22–32 | 가족·병원 정보, 검색, 온보딩, 음성 등록 |
| [앱과 백엔드](delirium-familiar-voice/04-apps-and-backend.md) | 33–42 | 앱 구성, 기술 스택, 서비스, DB, 안전 규칙, 병원 메시지 |
| [화면과 실행 흐름](delirium-familiar-voice/05-interface-and-runtime.md) | 43–53 | 화면, API, 상태 머신, 프롬프트, 지연 시간, 스트리밍 |
| [개인정보·개발·평가](delirium-familiar-voice/06-privacy-plan-and-evaluation.md) | 54–65 | 개인정보, 단계별 개발, KPI, 성공 기준, 연구·구현 원칙 |

**환자 대상 시험 전 필수 문서:** [안전·윤리 Blocking Gate](delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md). 기능 구현 완료만으로 시험을 시작하지 않으며, 정체성 고지·동의·병실 주변 음성 처리·의료진 알림의 네 게이트를 모두 확정해야 합니다.

클라우드 중심 전환과 MVP 정책의 결정 기록은 [ADR-0001](../architecture/decisions/0001-cloud-first-familiar-voice-mvp.md)을 따릅니다. 제품 기능은 구현 초안이며 임상·기관 검토가 필요한 절차는 게이트 문서에서 정의합니다.
