# Phase 5 및 환자 대상 시험 준비 상태

2026-09-16 기준. 이 문서는 [개발 Phase 5](06-privacy-plan-and-evaluation.md#phase-5--pilot-readiness)와 [환자 대상 시험 Blocking Gate](07-pre-patient-trial-safety-ethics-gate.md#23-pre-patient-trial-gate)의 **현재 구현 증거와 남은 조건**을 구분한다. 로컬 합성 시험은 기관 승인이나 실제 환자 시험 허가가 아니다.

| Phase 5 항목 | 현재 확인된 범위 | 남은 조건 |
| --- | --- | --- |
| Auth/role | Supabase Auth 직원·보호자 로그인 웹, 기관/담당 배정 RLS, 합성 기기 결속·철회 차단. [권한 migration](../../supabase/migrations/20260915122803_staff_patient_read_access.sql), [기기 migration](../../supabase/migrations/20260915165234_patient_device_family_access.sql), [로컬 검사 기록](../../supabase/README.md) | 전용 원격 프로젝트 연결, 기관 직원 자격·배정 승인 업무, 실기기·실제 기관 검증 |
| 승인된 동의·철회 | 네 동의 범위와 유효 시각/assent 제약, 철회된 동의 재활성화 금지, 철회·만료 시 비공개 환자 음성 프로필 조회 차단. iPad 내부 시험은 거부·철회 후 듣기/전송을 중단한다. [음성 동의 조회](../../supabase/migrations/20260915160000_patient_voice_consent_gate.sql), [분리 동의 조회](../../supabase/migrations/20260915161000_voice_trial_consent_scopes.sql) | 기관·IRB 승인 동의서와 대리인/환자 assent 절차, 거부 확인·재개 권한·철회 전달 및 이미 시작한 클라우드 처리 취소 |
| Audit | 최소 안전 이벤트 저장 테이블과 앱 역할 접근 차단. 합성 보조 알림의 생성·포털 표시·직원 확인·실패·해결 상태만 제한된 이벤트로 기록한다. [audit migration](../../supabase/migrations/20260915155000_phase5_audit_events.sql), [합성 알림](../../supabase/migrations/20260915183701_synthetic_aux_alert.sql) | 실제 환자·임상 이벤트와 접근/삭제 이력의 승인된 기록자·조회자, 보존 기간과 기관 감사 검토 |
| Deletion | iPad 합성 후보는 휘발성 메모리에 두고 시험 중단 시 폐기. DB에는 환자 음성 샘플 폐기 시각 필드와 철회·삭제 프로필의 재활성화 차단이 있다. [등록 schema](../../supabase/migrations/20260915120212_hospital_registry_voice_profile.sql), [종료 상태](../../supabase/migrations/20260915162000_voice_profile_terminal_states.sql) | 원본·특징 객체·복제 음성·전사·가족 기억의 승인된 삭제 트랜잭션, 공급자 삭제 확인, 실패 재시도와 감사 기록. 상태 필드만으로 실제 객체 삭제를 증명할 수 없음 |
| Observability | 합성 상태를 알리는 `/health`와 로컬 검사만 있다. [API](../../src/kof5_tts/api.py) | 운영 메트릭·로그의 개인정보 최소화, 실패/지연 알림, 감사 가능한 모니터링, 기관 운영 절차 |
| Failure handling | 내부 API의 권한/입력/공급자 오류, iPad 마이크·전사·재생 중단 확인 실패 시 차단, 기기 권한 조회 실패 시 hosted 호출 중단. 합성 보조 알림의 생성·포털 수신·직원 확인·해결·시간 초과 실패 상태를 DB/포털에서 분리한다. [API](../../src/kof5_tts/api.py), [합성 알림](../../supabase/migrations/20260915183701_synthetic_aux_alert.sql), [iPad 경계](../../apps/patient_ipad/README.md) | 실제 병실 네트워크·기기·공급자 장애, 임상 경고의 외부 전달·실제 의료진 ACK·상시 timeout 감시·기존 간호 호출 fallback과 환자 안내 검증 |
| Hospital security review | 로컬 합성 PostgreSQL RLS/제약과 GoTrue/Data API 검사는 기록됨. [검증 범위](../../supabase/README.md) | 병원 보안·개인정보·임상 담당자의 전용 프로젝트, 데이터 처리/보관, 계정 발급·권한, 공급자 계약 검토 및 승인 |

현재 제품 경로도 합성 시험에 한정된다. 병원 웹은 검증된 등록자와 **기본 0행** 기관 승인 게이트가 있을 때에만 최소 환자 등록을 허용하며, 실제 승인·EHR·입원·동의·환자 목소리 등록 업무는 없다([병원 경계](../../supabase/README.md)). 별도 합성 병원 사실 경로는 결속된 기기·현재 입원·승인된 안전 범주·질문을 한 DB 조회로 대조하고, 모호한 결과에는 사실을 내지 않는다([병원 사실 경계](../../supabase/migrations/20260915183905_patient_hospital_turn_context.sql)). iPad는 자기 음성의 기기 내 전사와 글 시험, 고정 합성 환자 UUID에 대한 익명 기기 결속을 지원하지만 실기기 병실 화자 판정, 환자 음성 등록, 실제 보호자 복제 음성은 검증되지 않았다([iPad 범위](../../apps/patient_ipad/README.md)). 보호자 웹의 가족 기억 등록·문자열 검색은 합성 계정에서 검사했으며 실제 가족 기억의 한국어 의미 검색 품질은 미측정이다([맥락 현황](03-context-and-guardian.md)).

병원 화면의 [첫 합성 음성 시험 준비 조회](../../supabase/migrations/20260916110000_synthetic_voice_enrollment_ready.sql)는 담당 직원·현재 입원·기관 승인·환자 참여/음성 기능 동의와 assent·입원 중 거부 없음을 확인한다. **활성 프로필을 선행 조건으로 요구하지 않으며** 기존 프로필 상태는 정보로만 보여준다. 브라우저의 30초 이내 시험자 본인 음성 채집은 중단 시 마이크 트랙과 오디오 참조를 폐기하고 업로드·특징 추출·프로필 생성·실제 환자 사용을 하지 않는다([ADR-0008](../../architecture/decisions/0008-synthetic-first-voice-enrollment-readiness.md)).

기기와 가족 기억을 매 턴 확인하는 [단일 `patient_family_turn_context` RPC](../../supabase/migrations/20260915172531_atomic_patient_family_turn_context.sql)는 호출 시점의 DB 스냅샷에서 `authorized`와 최대 3건의 일반 기억을 함께 반환한다. [FastAPI 합성 경로](../../src/kof5_tts/api.py)는 `authorized=false`나 RPC 실패 때 hosted 모델 호출을 중단한다. 호출 이후 철회가 일어나면 이미 시작한 공급자 처리를 취소하는 보장은 없다. 로컬 합성 Auth/Data API→FastAPI 모의 공급자 검사와 실제 iPad·원격 공급자·환자 시험은 서로 다른 검증 단계다.

| Gate 07 | 판정 | 환자 대상 시험 전에 필요한 것 |
| --- | --- | --- |
| Identity | **미완료** | AI/voice cloning 고지 문구·주기, 정체성 질문 fallback, 금지 표현의 기관 승인과 실제 UX 검증 |
| Consent | **미완료** | 환자/대리인/보호자 별도 동의서와 능력·assent·거부·철회 protocol, 실제 처리/삭제 연계 |
| Ambient Audio | **미완료** | 병실 녹음 후보·주변인 음성의 기기→서버→공급자 전송/보관/즉시 폐기 흐름, 공급자 보존 정책과 병실 시험 |
| Clinical Escalation | **미완료** | 합성 알림의 DB 상태/포털 버튼은 실제 의료진 전달·ACK가 아님. 위험 발화의 임상 정의·정확도, 외부 전달·실제 의료진 확인·상시 timeout·실패·기존 간호 호출 연계의 폐루프 검증 |

[Gate 07 차단 규칙](07-pre-patient-trial-safety-ethics-gate.md#24-blocking-rule)에 따라 네 조건과 기관 검토가 모두 완료되기 전 **실제 환자 자료 입력과 환자 대상 시험은 차단**한다.
