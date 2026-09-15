# Architecture Decision Records

ADR은 중요한 기술 결정의 배경, 선택지, 결과를 짧게 기록합니다.

## 파일 이름

```text
NNNN-short-title.md
```

예: `0001-select-baseline-tts-model.md`

## 상태

- `제안됨`: 검토 중
- `승인됨`: 현재 적용하는 결정
- `대체됨`: 후속 ADR로 교체됨
- `폐기됨`: 더 이상 적용하지 않음

새 기록은 [0000-template.md](0000-template.md)를 복사해 작성합니다. 기존 기록은 삭제하거나 내용을 바꾸지 않고, 변경된 결정은 새 ADR에서 연결합니다.

현재 적용하는 결정: [ADR-0001 가족 음성 대화 MVP의 클라우드 중심 전환](0001-cloud-first-familiar-voice-mvp.md), [ADR-0002 iPad 기기 내 발화 감지와 Vercel 우선 배포](0002-ipad-local-audio-vercel-first.md), [ADR-0004 Supabase Auth/Postgres](0004-supabase-auth-postgres.md), [ADR-0005 병원 승인 사실과 메시지 원문 보존](0005-hospital-approved-facts-message-fidelity.md), [ADR-0007 합성 보조 알림의 상태 경계](0007-synthetic-auxiliary-alert-state-boundary.md), [ADR-0008 첫 합성 음성 시험 준비](0008-synthetic-first-voice-enrollment-readiness.md).

검증 중인 설계: [ADR-0003 병원 환자 등록과 분리된 환자 목소리 프로필](0003-hospital-registry-patient-voice-profile.md), [ADR-0006 iPad 기기 계정과 현재 입원 연결](0006-ipad-anonymous-device-pairing.md), [ADR-0009 합성 가족 기억 의미 검색의 임시 평가 설정](0009-provisional-synthetic-family-semantic-rag.md), [ADR-0010 보호자 음성 복제 상태와 삭제 확인](0010-guardian-voice-lifecycle-and-deletion-proof.md), [ADR-0011 합성 직접 발화 전사의 당일 조회 경계](0011-synthetic-directed-transcript-today-view.md), [ADR-0012 합성 병원 예약 메시지의 iPad 재생 완료 기록](0012-synthetic-hospital-message-device-playback-receipt.md), [ADR-0013 합성 병원 맥락 사실의 두 직원 원문 승인](0013-synthetic-hospital-context-two-staff-approval.md).
