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

현재 적용하는 결정: [ADR-0001 가족 음성 대화 MVP의 클라우드 중심 전환](0001-cloud-first-familiar-voice-mvp.md), [ADR-0002 iPad 기기 내 발화 감지와 Vercel 우선 배포](0002-ipad-local-audio-vercel-first.md), [ADR-0004 Supabase Auth/Postgres](0004-supabase-auth-postgres.md).

검증 중인 설계: [ADR-0003 병원 환자 등록과 분리된 환자 목소리 프로필](0003-hospital-registry-patient-voice-profile.md).
