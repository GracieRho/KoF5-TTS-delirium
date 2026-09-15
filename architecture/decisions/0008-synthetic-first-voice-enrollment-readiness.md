# ADR-0008: 첫 합성 음성 시험 준비와 음성 사용 분리

- 상태: 승인됨
- 적용 범위: 고정 합성 환자의 직원·시험자 본인 음성 내부 시험만
- 작성일: 2026-09-16
- 관련 문서: [PRD 인덱스](../../docs/Delirium_Familiar_Voice_MVP_PRD.md), [병원 음성 등록 설계](../../docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md), [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)

## 결정

첫 음성 등록의 **준비**는 활성 음성 프로필 없이 판정한다. 고정 합성 환자·담당 `care_staff`·현재 입원·기관 승인·환자 참여와 음성 기능 동의/assent·입원 중 거부 없음만 [읽기 전용 RPC](../../supabase/migrations/20260916110000_synthetic_voice_enrollment_ready.sql)에서 확인한다. 기존 프로필 상태는 정보이며, [활성 프로필 사용 조건](../../supabase/migrations/20260915160000_patient_voice_consent_gate.sql)과 별개다.

병원 웹의 30초 이내 마이크 시험에는 **시험자 본인 음성**만 쓴다. 중단 시 트랙을 닫고 브라우저 메모리의 오디오 참조를 버린다. 서버 업로드, 특징 생성, 환자 프로필 생성, 실제 환자 자료 입력은 열지 않는다. 기관 승인 동의·거부 확인·원본/특징 삭제와 임상·보안 검토 및 [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)는 여전히 환자 시험 차단 조건이다.
