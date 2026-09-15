# ADR-0005: 병원 승인 사실과 메시지 원문 보존

- 상태: 승인됨
- 작성일: 2026-09-15
- 관련 문서: [MVP PRD 24·42절](../../docs/Delirium_Familiar_Voice_MVP_PRD.md), [병원 등록 설계](../../docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md), [안전 게이트](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)

## 배경

검사·병실·면회 등 병원 정보는 보호자의 가족 기억과 출처가 다르다. 예약 메시지를 LLM이 고쳐 말하면 직원이 승인하지 않은 일정이나 지시가 환자에게 전달될 수 있다.

## 결정

1. 병원 정보는 직원 승인·검증 시각·유효 기간을 가진 `hospital_context_fact`로 가족 기억과 분리한다. 병실·검사 사실은 해당 입원에 묶고, 입원 참조가 없는 사실은 병원 이름만 허용한다. 읽기 뷰에는 활성 환자·현재 진행 중인 입원·승인된 유효 사실만 포함하며, 재입원 때 이전 입원의 사실을 제외한다.
2. 예약 메시지는 `hospital_message.approved_text`에 승인 원문을 저장하고, 예약·전달·취소 상태를 따로 기록한다. 승인 문구와 승인자·승인 시각은 DB에서도 변경하지 못한다. 수정하려면 기존 메시지를 취소하고 새 원문을 승인한다.
3. 병원 직원은 확인된 기관·담당 환자 범위에서만 사실과 메시지를 읽는다. 고정 합성 환자에서는 담당 직원의 초안과 **다른 담당 직원의 승인**만 허용하고, 승인 원문과 일정은 DB에서 불변으로 둔다. 익명 iPad 기기는 현재 입원·동의·배정을 재확인해 기한이 된 승인 메시지만 읽는다. 클라이언트가 전달·의료진 확인 상태를 쓰는 권한은 열지 않는다. 실제 환자 승인·취소·전달·감사는 기관 권한 검증과 환자 동의/거부 절차를 갖춘 흐름에서 구현한다.

## 결과와 검증

- 작업 전용 Supabase PostgreSQL 17의 [마이그레이션](../../supabase/migrations/20260915133351_hospital_context_messages.sql)에서 사실·메시지 RLS, 다른 환자 입원 참조 차단, 승인 메시지 불변성을 적용했다. 합성 pgTAP 25개와 전체 권한 검사 57개가 통과했고, 퇴원·재입원 정보 차단을 재현했으며 advisor는 문제를 보고하지 않았다.
- 현재 구현은 직원 읽기와 저장 구조의 **합성 검증**이다. 실제 병원 출처 확인, 임상 문구 승인, 취소·전달·감사 흐름은 아직 없다. 환자 대상 사용 전에 [안전 게이트](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)와 임상 검토가 필요하다.
- 2026-09-16 합성 확장: [직원 초안·별도 승인·기기 조회 migration](../../supabase/migrations/20260915174140_synthetic_hospital_message_approval_queue.sql)과 [FastAPI 승인 원문 TTS](../../src/kof5_tts/api.py)를 추가했다. 실제 iPad 재생 완료, 병원 전달 확인, 임상 원문 승인 및 환자 대상 사용은 검증 범위 밖이다.
