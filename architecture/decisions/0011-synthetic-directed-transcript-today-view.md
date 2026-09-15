# ADR-0011: 합성 직접 발화 전사의 당일 조회 경계

- 상태: 제안됨
- 작성일: 2026-09-16
- 적용 범위: 고정 합성 환자·현재 입원 내부 시험만
- 관련 문서: [PRD 병원 화면](../../docs/delirium-familiar-voice/04-apps-and-backend.md), [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)

## 결정 초안

기기에서 `DIRECTED`로 판정되어 합성 대화에 받아들인 **글만** 기기 JWT로 기록한다. 주변·화자 불명·거부 후보의 오디오와 전사는 기록하지 않는다. 클라이언트 UUID로 동일 요청을 중복 처리하지 않고, 현재 입원·기관 승인·환자 동의/assent·기기 연결이 없으면 저장을 거부한다. 현재 입원을 담당하는 승인된 직원에게만 한국 날짜 **오늘**의 글을 조회하게 한다.

오늘이 지나 조회되지 않는 것과 DB 행의 물리적 삭제는 별개다. 실제 보존 기간, 자동 삭제, 백업·공급자 데이터 폐기는 이 합성 시험 결정으로 정해지지 않았다. 기기의 `DIRECTED` 표시는 환자 화자를 검증한 증거가 아니다.

## 검증과 변경 조건

로컬 RLS/Auth/Data API·중복 요청·철회·직원 배정·자정 경계 검사 후 결과를 기록한다. 실제 환자 전사 저장·조회는 화자 판정, 기관 승인 보존/삭제 정책, 접근 감사와 [Gate07 네 조건](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md#23-pre-patient-trial-gate)을 충족할 때 별도 결정한다.
