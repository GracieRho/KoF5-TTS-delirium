# 병원 환자 등록·목소리 프로필 데이터 설계

이 문서는 병원 화면에서 환자를 등록하고 약 30초의 목소리 샘플을 받기 위한 **설계안**이다. [Supabase 로컬 마이그레이션](../../supabase/README.md)으로 환자·직원·보호자 구조와 읽기/가족 기억 권한을 합성 데이터에서 검증했다. 실제 병원 연동, 환자 녹음 또는 화자 모델 선택은 하지 않았다. 실제 환자 자료를 받기 전에는 [환자 시험 전 안전 게이트](07-pre-patient-trial-safety-ethics-gate.md)의 동의·거부·주변 음성·기관 검토가 적용된다.

## 병원에서 흔히 관리하는 정보와 MVP 사용 범위

병원별 EHR 테이블 이름과 컬럼은 다르다. 아래는 보편적인 **FHIR R4 자원에 대응하는 정보 범주**다. 병원 연동 시 실제 API/HL7 메시지와 권한을 확인해야 한다.

| 범주 | 대표 필드 | FHIR 근거 | 이 MVP의 처리 |
| --- | --- | --- | --- |
| 환자 기본정보 | 병원 환자 식별자(MRN 등), 성명, 생년월일/계산된 나이, 행정 성별, 연락처, 언어, 기록 활성 여부 | [Patient](https://hl7.org/fhir/R4/patient.html) | 환자 연결과 직원의 오등록 방지에 필요한 식별·표시 정보만. 주민등록번호·주소·전화번호는 기본 수집하지 않음 |
| 입원·병실 | 입원 식별자, 입원/퇴원 시각, 상태, 병동·호실·병상, 담당자 | [Encounter](https://hl7.org/fhir/R4/encounter.html), [Location](https://hl7.org/fhir/R4/location.html) | 현재 유효한 입원·위치만 병원 승인 지남력 정보로 사용. 이동/퇴원 시 즉시 갱신 |
| 의료진·보호자 관계 | 담당 팀/직원 역할, 환자와 보호자의 관계·연결 상태 | [CareTeam](https://hl7.org/fhir/R4/careteam.html), [RelatedPerson](https://hl7.org/fhir/R4/relatedperson.html) | 직원 등록·승인 권한과 보호자 연결에 사용. 보호자 연락처는 별도 계정에 관리 |
| 병원 조직·직원 권한 | 기관 식별자, 직원의 기관별 역할과 유효 기간, 담당 환자 범위 | [Organization](https://hl7.org/fhir/R4/organization.html), [PractitionerRole](https://hl7.org/fhir/R4/practitionerrole.html), [CareTeam](https://hl7.org/fhir/R4/careteam.html) | 직원 인증/EHR의 기관·역할·담당 범위를 검증. 권한 근거를 확인할 수 없으면 실제 환자 등록을 허용하지 않음 |
| 진단·알레르기·약물·검사 | 문제/진단 상태, 알레르기, 처방, 검사 지시와 예정 시각, 활력징후 | [Condition](https://hl7.org/fhir/R4/condition.html), [AllergyIntolerance](https://hl7.org/fhir/R4/allergyintolerance.html), [MedicationRequest](https://hl7.org/fhir/R4/medicationrequest.html), [ServiceRequest](https://hl7.org/fhir/R4/servicerequest.html), [Observation](https://hl7.org/fhir/R4/observation.html) | 전체 임상 테이블을 복제하지 않음. 검사·일정은 직원이 확인·승인한 문구만 `hospital_context`에 투입. 진단/약물 판단에 사용하지 않음 |
| 동의·메시지·감사 | 동의 범위/동의자/기간, 예약 메시지·발신자, 누가 기록을 처리했는지 | [Consent](https://hl7.org/fhir/R4/consent.html), [CommunicationRequest](https://hl7.org/fhir/R4/communicationrequest.html), [AuditEvent](https://hl7.org/fhir/R4/auditevent.html) | 환자 참여·환자 화자 특징·보호자 복제 음성·주변 음성 고지를 분리. 승인 문구와 접근/삭제 이력을 유지 |

## MVP 논리 테이블과 핵심 컬럼

아래 컬럼은 제품 계약이다. 현재 로컬 마이그레이션의 타입·제약과 실제 API 제공 범위는 [Supabase 작업 경계](../../supabase/README.md)를 따른다. 각 테이블의 기본키(`patient_id`, `encounter_id`, `profile_id` 등)는 내부 UUID다. `hospital_id`, `guardian_id`, `*_staff_id`는 기관·인증 시스템의 외부 참조, `*_ref`는 병원 EHR 또는 암호화된 저장소의 참조값이다. 병원별 환자 번호는 조직 범위에서만 유일하며 전역 키로 사용하지 않는다.

| 테이블 | 컬럼 | 책임 |
| --- | --- | --- |
| `hospital_patient` | `patient_id` PK, `hospital_id`, `ehr_patient_ref`, `staff_display_name`, `birth_date` nullable, `administrative_gender` nullable, `preferred_language`, `active`, `registered_by_staff_id`, `created_at`, `updated_at` | 직원 화면의 환자 등록·중복 확인. 나이는 `birth_date`와 조회 시점에서 계산; 두 값을 중복 저장하지 않음. 식별/표시 필드는 직원만 접근 |
| `hospital_encounter` | `encounter_id` PK, `patient_id` FK, `ehr_encounter_ref`, `status`, `admitted_at`, `discharged_at` nullable, `ward_ref`, `room_ref`, `bed_ref`, `care_team_ref`, `location_verified_at` | 병동·호실·병상·담당 팀은 환자 고정 속성이 아니라 **입원별** 속성. 활성 입원 하나만 지남력 응답에 사용 |
| `patient_guardian_link` | `link_id` PK, `patient_id` FK, `guardian_id` FK, `relationship`, `is_primary`, `access_status`, `verified_by_staff_id`, `verified_at` | 보호자 연결과 정보 입력 범위. 보호자는 자기 환자 연결만 조회·수정 |
| `consent_record` | `consent_id` PK, `patient_id` FK, `guardian_id` nullable, `scope`, `signer_role`, `signer_ref`, `assent_status`, `status`, `effective_at`, `expires_at` nullable, `withdrawn_at` nullable, `recorded_by_staff_id` | 최소 네 범위 `patient_participation`, `patient_voice_feature`, `guardian_voice_clone`, `ambient_processing`을 구분. 대리인 동의와 환자 이해/거부를 별도 상태로 기록 |
| `patient_voice_profile` | `profile_id` PK, `patient_id` FK, `encounter_id` FK, `consent_id` FK, `status`, `enrollment_duration_ms`, `embedding_model`, `embedding_version`, `encrypted_embedding_ref`, `quality_status`, `enrolled_by_staff_id`, `enrolled_at`, `revoked_at` nullable, `deleted_at` nullable | 환자 목소리 특징의 등록·갱신·폐기. 원본 WAV나 임베딩 벡터를 일반 환자 행에 넣지 않음. 활성 프로필은 환자/입원 단위로 하나 |
| `patient_voice_sample` | `sample_id` PK, `profile_id` FK, `temporary_encrypted_object_ref` nullable, `codec`, `duration_ms`, `captured_at`, `purge_due_at`, `purged_at` nullable | 약 30초 원본의 **일시 처리 메타데이터**. 특징 추출·품질 확인 후 원본 객체를 삭제하고 참조를 비움. 별도 원본 보관은 목적·기간·동의가 승인된 경우에만 허용 |
| `hospital_context_fact` | `fact_id` PK, `patient_id` FK, `encounter_id` FK nullable, `category`, `content`, `source_staff_id`, `approved_by_staff_id`, `verified_at`, `valid_until` nullable, `status` | 병실·검사·면회 등 **직원 승인 사실**. 입원 참조가 없으면 병원 이름(`hospital`)만 허용하고, 현재 입원이 없거나 사실이 만료되면 응답에서 제외 |
| `hospital_message` | `message_id` PK, `patient_id` FK, `encounter_id` FK, `approved_text`, `approved_by_staff_id`, `due_at`, `delivery_status`, `delivered_at` nullable | 직원 승인 원문을 그대로 TTS에 전달. 생성·전달·직원 확인은 별도 상태; 위험 발화 보조 알림과 혼동하지 않음 |

FHIR는 교환 형식의 기준이며 위 테이블은 **이 제품이 필요한 데이터 최소화에 대한 설계 추론**이다. 병원 EHR에서 이름·생년월일·병실을 안전하게 조회할 수 있다면 앱 DB의 중복 보관을 줄인다. 보호자/환자 앱과 LLM 프롬프트에는 MRN, 연락처, 원본 음성, 임베딩을 보내지 않는다.

직원 승인 병원 사실과 예약 메시지는 [ADR-0005](../../architecture/decisions/0005-hospital-approved-facts-message-fidelity.md)에 따라 가족 기억에서 분리하며, 승인된 메시지 원문은 변경하지 않는다. 퇴원하면 병원 사실·메시지를 조회하지 않고, 재입원 시 이전 입원의 사실·메시지를 제외한다. 로컬 DB의 저장·읽기 경계만 합성 자료로 검증했고, 실제 출처 확인·임상 문구 승인·전달은 아직 구현되지 않았다.

`hospital_id`와 `*_staff_id`는 각각 병원 조직과 직원 인증/EHR의 외부 참조다. 로컬 마이그레이션은 Auth 사용자와 직원 자격·환자 배정을 별도 테이블로 연결한다. 실제 병원 연동에서 기관 소속·역할·담당 입원 범위를 확인할 수 없다면 해당 직원의 등록·목소리 처리 API를 막는다.

## 환자 목소리 등록 흐름

1. 직원이 환자·현재 입원 정보를 확인하고, `patient_voice_feature` 범위의 유효한 동의·대리인 동의/환자 assent 및 거부 상태를 검사한다. 명확한 거부가 있으면 녹음·예정 대화를 중단한다.
2. 병원 화면에서 약 30초의 환자 발화를 녹음한다. iPad 또는 병원 단말에서 짧은 품질 검사를 하고, 녹음 도중 주변인 목소리가 섞이면 다시 받는다. 30초는 시험용 UI 목표이며 **화자 분류 성능을 보장하는 수치가 아니다**.
3. 화자 특징을 생성할 때만 원본을 일시 사용한다. 원본은 기본적으로 특징 생성 후 삭제하고, 암호화된 특징 참조와 모델 버전·품질·동의 참조만 유지한다. 원본 별도 보관/제3자 전송은 정책·동의가 승인된 뒤에만 추가한다. [KISA 생체정보 안내서](https://xn--t60bp32bmoar7entoqlj.xn--3e0b707e/2060301/form?lang_type=KO&page=1&postSeq=42)가 원본·특징정보의 별도 보호 검토 자료다.
4. 활성화 시 VAD·발화 내용/의도·대화 상태에 **화자 유사도 점수 하나를 보조 신호로 합친다**. 점수가 낮다는 이유만으로 환자 말을 단독 차단하지 않는다. 고령 환자의 음성 변화와 짧은 시험 발화가 오류를 키울 수 있으므로, 실제 한국어 병실 자료에서 오활성화·누락을 측정한 뒤 임계값을 정한다. [노화와 음성 품질 연구](https://www.sciencedirect.com/science/article/abs/pii/S0885230812001076), [짧은 발화 검증 연구](https://www.isca-archive.org/interspeech_2024/chen24l_interspeech.html).
5. 동의 철회·환자 거부·퇴원/시험 종료 시 프로필을 즉시 비활성화하고 원본·특징 참조의 삭제를 감사한다. 등록 실패나 샘플 품질 저하 시 텍스트/맥락 활성화 후보 경로를 유지한다.

### iPad 화자 판정 구현 전 검증

[Apple Speech](https://developer.apple.com/documentation/speech/)는 전사·VAD 기능을, [Sound Analysis](https://developer.apple.com/documentation/SoundAnalysis)는 소리 분류와 사용자 모델 경로를 문서화한다. 이 문서들만으로 **등록한 특정 환자와 발화자의 일치 판정**이 제공된다고 볼 수 없다. [SpeechBrain ECAPA-TDNN](https://github.com/speechbrain/speechbrain/blob/develop/speechbrain/inference/speaker.py)은 16 kHz 음성의 임베딩·유사도 비교 후보지만, 공개 [VoxCeleb 평가](https://github.com/speechbrain/speechbrain/blob/develop/recipes/VoxCeleb/SpeakerRec/README.md)를 한국어 고령 환자·병실 소음·짧은 발화 성능으로 그대로 옮길 수 없다. [Apple Core ML Tools](https://github.com/apple/coremltools/)는 PyTorch 모델 변환 경로를 제공하지만, 해당 화자 모델의 변환 성공·iPad 지연·전력·정확도는 별도 실측이 필요하다. 따라서 모델·임계값·클라우드/기기 내 특징 생성 위치는 현 단계에서 확정하지 않는다.

## 병원 화면과 접근 경계

- 환자 목록/등록: 병원 환자 번호 조회, 성명·생년월일 또는 나이 확인, 활성 입원·병실 표시, 중복 등록 확인.
- 환자 상세: 보호자 연결, AI 고지·동의/assent·거부 상태, 환자 목소리 등록/갱신/삭제, 병원 승인 사실·메시지 편집.
- 음성 등록: 등록 권한 직원만 시작; 유효한 동의 없거나 거부 상태면 녹음 버튼 비활성화; 샘플 길이·품질·특징 생성·원본 삭제 상태를 분리해 표시.
- 권한: 병원 직원은 자기 기관·담당 환자 범위, 보호자는 연결된 환자의 **가족 기억과 자기 음성** 범위, 환자 iPad는 세션 실행에 필요한 최소 사실/프로필 신호만. 화자 특징과 원본은 일반 보호자·환자 화면에 노출하지 않는다.

실제 병원 EHR 스키마, 직원 역할, 보관 기간, 임베딩 모델/저장소, 30초 품질 기준, 기관 동의 문구는 아직 미정이다. 이 설계는 합성 데이터 UI와 계약 검증에만 사용한다.
