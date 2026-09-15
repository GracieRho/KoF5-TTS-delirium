# ADR-0010: 보호자 복제 음성 상태와 공급자 삭제 후조건

- 상태: 제안됨
- 작성일: 2026-09-16
- 적용 범위: 고정 합성 환자·시험자 본인 음성의 내부 계약 검증만
- 관련 문서: [PRD 보호자 음성 등록](../../docs/delirium-familiar-voice/03-context-and-guardian.md#31-guardian-voice-enrollment), [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)

## 결정 초안

별도 `guardian_voice_clone` 동의와 검증된 보호자 Auth 연결을 요구한다. [DB lifecycle 초안](../../supabase/migrations/20260916143000_synthetic_guardian_voice_lifecycle.sql)은 공급자 slug·`voice_id`·`pending`/`verification_pending`/`created`/`deletion_pending`/`deleted`/`failed` 상태만 보관하고 원본 음성·전사·API 키를 저장하지 않는다. 공급자 POST 전에 고유 요청을 `pending`으로 기록하고 불확실한 결과는 재등록 대신 조회로 조정한다. 유효한 연결·동의와 확인된 clone만 TTS에 사용하며 철회나 삭제 대기 때 즉시 사용을 차단한다.

공급자 DELETE의 성공 응답만으로 `deleted`로 표시하지 않는다. 정확한 `voice_id`가 공급자 계정의 조회 목록에서 더는 보이지 않는지 확인한 뒤에만 삭제 확인 시각을 남긴다. 조회가 실패하거나 ID가 아직 보이면 `deletion_pending`을 유지한다. 현재 [자가 음성 CLI](../../scripts/demo_voice_enrollment.py)와 [시험 공급자 helper](../../src/kof5_tts/cloud_prototype.py)는 이 API 후조건을 모의 응답으로 검사한다. 이는 **계정 목록에서의 부재**이며 공급자 내부 샘플·백업·보존 자료의 삭제 증명은 아니다.

## 환자 시험 전 남은 조건

ElevenLabs는 내부 시험의 **후보 계약**이고 최종 음성 공급업체로 결정하지 않았다. 실제 보호자 음성에는 별도 동의서·철회 절차, 원본/clone 보존·학습·사칭 방지·삭제 계약, 기관 승인과 [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)이 필요하다. 현재 합성 DB/API/UI 경로와 실제 공급자·보호자 샘플 처리는 별도 검증이다.
