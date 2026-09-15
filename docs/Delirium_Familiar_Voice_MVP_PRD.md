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

**병원 등록 설계 보충:** [환자 정보·목소리 프로필 테이블](delirium-familiar-voice/08-hospital-patient-registry-and-voice.md)은 FHIR 기반 병원 정보 범주, 최소 MVP 컬럼, 약 30초 녹음과 화자 유사도 경계를 정리합니다. 원문 0–65절의 보충 설계이며 실제 병원 EHR·임상 자료를 연결한 것은 아닙니다.

**현재 구현·시험 준비:** [Phase 5 및 환자 대상 시험 준비 상태](delirium-familiar-voice/09-phase5-and-patient-trial-status.md)는 합성 검증과 아직 필요한 감사·철회·삭제·기관 검토 및 네 안전 게이트를 구분합니다.
**실기기 지연 검증:** [iPad 첫 실제 소리 지연 검증 절차](delirium-familiar-voice/10-first-audible-audio-latency-test.md)는 현재 명령 확인 수치와 PRD의 첫 청취 소리를 구분합니다.

클라우드 중심 전환은 [ADR-0001](../architecture/decisions/0001-cloud-first-familiar-voice-mvp.md), iPad·기기 내 감지·Vercel 우선 경로는 [ADR-0002](../architecture/decisions/0002-ipad-local-audio-vercel-first.md), 로그인·환자 데이터 저장의 Supabase Auth/Postgres 선택은 [ADR-0004](../architecture/decisions/0004-supabase-auth-postgres.md), 병원 승인 사실·메시지 원문 보존은 [ADR-0005](../architecture/decisions/0005-hospital-approved-facts-message-fidelity.md), 합성 보조 알림은 [ADR-0007](../architecture/decisions/0007-synthetic-auxiliary-alert-state-boundary.md), 첫 합성 음성 시험 준비는 [ADR-0008](../architecture/decisions/0008-synthetic-first-voice-enrollment-readiness.md)을 따릅니다. 병원 환자·목소리 프로필은 [ADR-0003 제안](../architecture/decisions/0003-hospital-registry-patient-voice-profile.md), iPad 기기 계정과 현재 입원 연결은 [ADR-0006 제안](../architecture/decisions/0006-ipad-anonymous-device-pairing.md), 합성 가족 의미 검색의 임시 모델·임계값은 [ADR-0009 제안](../architecture/decisions/0009-provisional-synthetic-family-semantic-rag.md), 보호자 음성 복제의 상태·삭제 확인은 [ADR-0010 제안](../architecture/decisions/0010-guardian-voice-lifecycle-and-deletion-proof.md), 합성 직접 발화 전사의 당일 조회는 [ADR-0011 제안](../architecture/decisions/0011-synthetic-directed-transcript-today-view.md), 입원별 합성 대화 상태는 [ADR-0014 제안](../architecture/decisions/0014-synthetic-admission-conversation-session.md)에서 검증 중입니다. 제품 기능은 구현 초안이며 임상·기관 검토가 필요한 절차는 게이트 문서에서 정의합니다.

**합성 병원 예약 메시지 재생 완료의 의미:** [ADR-0012 제안](../architecture/decisions/0012-synthetic-hospital-message-device-playback-receipt.md)은 기기 자동 조회와 네이티브 재생 완료 보고를 실제 환자 청취·임상 전달과 구분합니다.
