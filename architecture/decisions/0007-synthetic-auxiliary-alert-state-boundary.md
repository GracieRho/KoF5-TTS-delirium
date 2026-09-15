# ADR-0007: 합성 보조 알림의 상태와 기존 호출 수단 경계

- 상태: 승인됨
- 적용 범위: 팀 내부 고정 합성 환자 시험만
- 작성일: 2026-09-16
- 관련 문서: [MVP PRD](../../docs/Delirium_Familiar_Voice_MVP_PRD.md), [환자 시험 전 Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md), [Phase 5 상태](../../docs/delirium-familiar-voice/09-phase5-and-patient-trial-status.md)

## 배경

위험 발화 후보를 DB에 기록하는 것과 의료진이 실제로 받거나 확인하는 것은 다른 사건이다. 합성 포털의 성공 응답을 환자에게 임상 전달 성공으로 설명하면 안전 게이트의 실패 경로를 가린다.

## 결정

1. 합성 iPad는 기기 내 전사한 **자가 음성 합성 시험 후보**에서 위험 구절을 찾더라도 전사·오디오를 알림에 보내지 않는다. 고정 합성 환자 UUID, 위험 범주, 중복 방지 UUID만 기기 JWT와 함께 제출한다. 화자 불명/주변 발화, 권한·중단 확인 실패, 거부 상태에서는 알림을 만들지 않는다.
2. `created`는 DB 생성, `delivered`는 담당 직원의 합성 포털 표시 수신 버튼, `acknowledged`는 담당 직원의 명시 확인, `resolved`는 후속 조치 완료 표시, `failed`는 포털 표시/직원 확인 시간 초과다. 포털 조회만으로 전달 상태를 바꾸지 않는다. 시간 초과 계산은 담당 직원의 상태 변경 동작 또는 명시적 sweep 때만 실행한다.
3. iPad는 위험 후보와 오류 상황에서 기존 호출 버튼 사용을 안내한다. 합성 포털 알림은 실제 간호 호출 수단과 연결하지 않으며 의료진 전달·확인을 보장한다고 말하지 않는다.

## 결과와 미완료 조건

[DB 상태/RPC](../../supabase/migrations/20260915183701_synthetic_aux_alert.sql), [병원 포털](../../src/kof5_tts/hospital_portal.html), [iPad 시험](../../apps/patient_ipad/lib/synthetic_auxiliary_alert.dart)과 합성 검사가 이 경계를 구현한다. 실제 환자 사용에는 임상 위험 정의·화자 판정, 전용 원격 환경과 실기기/공급자 검증, 외부 전달·실제 의료진 ACK·상시 감시·기존 간호 호출 fallback, 기관 승인 및 [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)가 필요하다. 이 ADR의 `승인됨`은 **합성 내부 시험 정책**에만 적용한다.
