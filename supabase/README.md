# Supabase Auth/Postgres 작업 경계

보호자·병원 직원 로그인과 환자 데이터 저장은 Supabase Auth/Postgres를 사용한다. 웹/API의 첫 배포 대상은 Vercel이다. 첫 마이그레이션은 [병원 등록 설계](../docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md)의 환자·입원·동의·환자 목소리 프로필/샘플을 PostgreSQL 제약으로 옮긴 **초안**이다. 둘째는 Auth 직원 자격·담당 배정과 읽기 전용 환자 목록, 셋째는 보호자 연결·가족 기억, 넷째는 직원 승인 병원 사실·메시지를 추가한다.

다섯째 마이그레이션은 `api.hospital_patient_registration`에 환자 기본정보 INSERT 권한을 추가한다. `kof5.hospital_registry_activation`은 **기본 0행·클라이언트 쓰기 불가**인 기관별 서버 승인 게이트다. 기관 승인과 임상 안전 승인 참조가 기록되고 아직 유효하며, 현재 검증된 해당 기관 `registrar`가 로그인한 경우에만 RLS가 등록을 허용한다. `registered_by_staff_ref`에는 입력 문구 대신 Auth 사용자 ID가 자동 기록되고 RLS가 일치를 재검사한다. 기존 `(hospital_ref, ehr_patient_ref)` 중복 제약은 그대로 적용된다. `care_staff`, 자격 대기·만료·철회, 다른 기관, 비로그인은 등록할 수 없다. 환자 수정·입원·동의·목소리·승인 사실 입력은 계속 열지 않았다. **실제 기관 자격 검증/배정·동의·안전 승인 서버 업무 흐름은 아직 구현되지 않았으므로 실제 승인 게이트 행을 만들거나 실환자 자료를 입력하지 않는다.** 로컬 pgTAP에서는 `TEST-*` 참조와 합성 계정만 트랜잭션 안에서 시험한다.

여섯째 마이그레이션의 읽기 전용 `api.hospital_registration_ready`는 로그인한 직원의 **현재 registrar 기관과 기관·안전 승인 게이트 준비 여부**만 보여준다. 승인 참조·타 기관 직원 목록은 반환하지 않는다. 병원 웹 등록 폼은 `ready=true`인 기관에만 나타나고, POST 직전에 준비 여부를 다시 읽는다. 등록 시 환자 번호·성명·선택 생년월일만 보내며, DB 제약/RLS가 중복·타 기관·철회를 최종 차단한다. 403이면 화면에서 세션과 환자 정보를 지우고, 로그아웃 뒤 늦은 응답은 목록·폼을 복원하지 않는다. 이것은 로컬 합성 시험 경로이며 실환자 등록/병원 EHR 연결을 입증하지 않는다.

일곱째 `api.guardian_memory_search`는 호출자 RLS를 쓰는 보호자 본인 작성·유효·일반 가족 기억의 최대 3건 문자열 검색이다. 피해야 할 주제와 민감·만료 기억은 제외한다. 실제 환자 대화 검색, pgvector·임베딩·의미 검색은 연결하지 않았다. 여덟째 `kof5.safety_audit_event`는 안전 이벤트 9종의 최소 저장 경계이며 발화·오디오·자유 텍스트 칼럼과 앱 역할의 직접 읽기/쓰기 권한이 없다. 승인된 기록자·보존/삭제 정책·실제 감사 기록 흐름은 아직 없다.

아홉째 비공개 `kof5.usable_patient_voice_profile`은 현재 진행 중 입원·활성 환자·유효한 환자 음성 기능 동의/assent가 모두 있을 때만 암호화 특징 참조를 조회한다. 철회·만료 뒤에는 기존 프로필이 active로 남아도 조회되지 않고, 철회 기록을 다시 active로 바꾸지 못한다. 앱 역할에는 조회 권한이 없다. 이것은 내부 합성 시험의 **음성 기능 동의 한 범위**만 검증하며 환자 참여/병실 주변 음성 동의, 기관 승인, 실제 특징 객체 삭제·임상 절차를 대신하지 않는다.

열째 비공개 `kof5.voice_profile_with_trial_consents`는 그 기능 동의 조회에 **별도 환자 참여·병실 주변 음성 처리 동의**와 현재 기관 안전 승인 참조를 추가한다. 각 동의가 만료·철회되거나 승인 게이트가 만료되면 0행을 반환하며 앱 역할에 SELECT를 주지 않는다. 이 DB 조건만으로 [정체성 고지·의료진 경보 게이트](../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)가 충족되지는 않는다.

열한째 합성 장치 결속은 Supabase Auth의 익명 로그인 사용자를 `authenticated` 역할로 받되, 검증된 담당 `care_staff`가 `api.patient_device_pairing`에 **장치 Auth 사용자 UUID·고정 합성 환자 UUID `00000000-0000-4000-8000-000000000975`·현재 입원 UUID·8시간 이내 만료**를 기록할 때만 활성화한다. 병원 화면은 `api.synthetic_device_pairing_ready`의 `patient_id, encounter_id` 한정 조회로 폼 자격을 확인하고, INSERT RLS가 최종 검사한다. 장치는 자기 Auth JWT와 publishable 키로 `api.patient_device_context`를 읽고 `api.patient_family_search(p_patient_id,p_term)`를 호출한다. 후자는 현재 입원·기관 승인·환자 참여/주변 음성/환자 목소리 기능 동의 및 assent·유효한 보호자 연결을 매 요청 확인하고, 유효한 일반 기억의 `category,content` 최대 3건만 반환한다. 기존 `api.family_context`는 익명 장치에 숨겨 검색 제한을 우회할 수 없게 했다. 결속은 환자/입원 간 이동 불가이고 철회 뒤 재활성화 불가다. **실제 환자 UUID는 DB에서 기본 차단**하며 이를 켜는 클라이언트 스위치가 없다. 이 로컬 합성 계약은 [실제 환자 안전 게이트](../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)의 정체성 고지·의료진 경보/ACK, 병원 승인 업무와 실제 음성/동의 절차를 입증하지 않는다.

- `kof5` 스키마는 Data API에 노출하지 않는다. 모든 테이블에 `FORCE ROW LEVEL SECURITY`를 적용한다. 인증된 직원은 **검증된 현재 기관 자격**이 있는 경우에만 해당 기관 환자를 읽고, 담당 직원은 **검증된 현재 배정 환자**만 읽는다. `api.hospital_patient_list`는 호출자 RLS를 따르는 읽기 전용 뷰다. 동의·음성 테이블에는 클라이언트 읽기 권한을 주지 않았다. 전용 원격 프로젝트에서는 `api` 스키마를 Data API 설정에도 별도로 노출해야 한다.
- 원본 음성과 임베딩 본문은 테이블에 두지 않는다. 샘플에는 일시 암호화 객체 참조와 폐기 시각만, 프로필에는 암호화된 특징 참조와 모델 버전만 둔다.
- 보호자는 자기 환자 연결의 상태만 읽는다. **검증된 유효 연결**이 있을 때에만 자기 가족 기억을 읽고 기록·수정·문자열 검색할 수 있으며, 환자 번호·생년월일·입원·동의·음성 메타데이터는 읽을 수 없다. 철회/만료 즉시 가족 기억 접근도 차단한다. 원문은 `family_fact`에 저장하고, 의미 검색/임베딩 모델은 아직 정하지 않았다.
- 병원 사실의 공개 뷰는 직원 승인·유효 기간·현재 입원을 확인한다. 병실·검사 사실은 특정 입원에 묶고, 입원 참조가 없는 사실은 병원 이름(`hospital`)만 허용한다. 병원 이름도 진행 중인 입원이 없으면 조회되지 않는다. 병원 메시지는 승인 원문·예약 시각·전달 상태를 분리하고, 승인 문구와 승인자·시각은 수정할 수 없다. 직원도 클라이언트에서 사실·메시지를 직접 등록하거나 승인할 수 없다. 실제 기관 승인/취소·전달·감사 API는 아직 구현 전이다.
- 직원 자격과 담당 배정을 **누가 검증·기록하는지**, 유효한 동의·환자 assent/거부, 보호자 연결, 철회 시 삭제 트랜잭션과 감사 기록은 아직 구현되지 않았다. 실제 환자 자료 입력 전에 기관 승인 절차가 필요하다.
- 마이그레이션을 기존 `yai-hub-production` 프로젝트에 적용하지 않는다. 이 MVP 전용 프로젝트의 PostgreSQL 버전·지역·계획과 기관 데이터 처리 조건을 확인한 뒤 연결한다. 실제 환자 자료는 [안전 게이트](../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md) 통과 전 입력하지 않는다.

합성 데이터 제약 검사는 **버려도 되는 독립 PostgreSQL DB**에 마이그레이션을 적용한 뒤 실행한다.

```bash
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260915120212_hospital_registry_voice_profile.sql
psql -v ON_ERROR_STOP=1 -f supabase/smoke/registry_constraints.sql
```

2026-09-16 현재 검증은 임시 PostgreSQL 18.4, 별도 `postgres:17` 작업 컨테이너, 그리고 **이 작업의 로컬 Supabase PostgreSQL 17**에서 합성 제약 검사가 통과했다. 첫 두 작업 DB와 익명 볼륨은 제거했다. 로컬 Supabase DB에는 열 마이그레이션이 적용됐고, 기존 123개와 분리 동의·기관 승인 경계 11개인 pgTAP **134개**가 통과했다. 퇴원 후 사실·메시지 차단과 재입원 시 이전 입원 정보 제외도 검사했다. CLI advisor는 `No issues found`를 보고했다. 작업 전용 **로컬 GoTrue/Data API HTTP**에서 합성 보호자 기억 등록·수정·검색/철회/비로그인 차단과 연결 없는 신규 계정 차단, 직원 승인 조회 필드, 등록자 Auth/기관 승인 게이트의 준비 상태 전환·참조 위조·중복·철회가 통과했다. 검사 뒤 환자·동의·음성 프로필·기억·감사·Auth 계정·승인 게이트 행은 모두 0건이었다. 전용 원격 프로젝트, 실제 기관 직원 승인·Auth/Storage와 환자 데이터 처리 흐름은 검증하지 않았다. CLI `db query --file`은 여러 SQL 명령을 한 prepared statement로 넣어 실패하므로, 제약 검사는 컨테이너 내부 `psql`로 실행한다.

```bash
docker exec -i supabase_db_kof5-familiar-voice-mvp psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/smoke/registry_constraints.sql
supabase test db --local
supabase db advisors --local
supabase migration list --local
```

로컬 HTTP 검사는 작업 전용 Supabase DB/Auth/Data API/Kong을 켠 뒤 실행한다. `local_http_smoke.py`, `local_guardian_signup_http_smoke.py`, `local_staff_http_smoke.py`는 실행 위치와 관계없이 이 작업 설정을 읽고 `127.0.0.1:54341`만 허용한다. 브라우저와 같은 **publishable 키**를 사용한다. 임의 비밀번호와 `example.invalid` 합성 계정을 사용하고 로컬 키·토큰을 출력하지 않으며, 생성 응답이 유실돼도 이번 합성 이메일로 계정을 찾아 환자·기억·계정을 삭제한다. 가입 검사는 Auth 계정을 만든 뒤 환자 연결이 없으면 읽기·쓰기가 모두 차단되는지 확인한다. 직원 검사는 다른 기관 환자·승인 사실·메시지가 조회되지 않고 자격 철회 후 세 뷰가 비워지는 것을 확인한다. 공유 `yai-hub` 인스턴스에는 적용하지 않는다. 별도 `/guardian` 보호자 웹도 로컬 합성 계정의 로그인·가족 기억 저장/재조회·연결 철회 후 거부 및 기존 기억 숨김을 브라우저에서 확인했다. 원격 이메일 확인·SMTP 설정은 아직 미검증이다.

```bash
supabase start --exclude edge-runtime,imgproxy,mailpit,postgres-meta,realtime,storage-api,studio,logflare,vector,supavisor
python3 supabase/tests/local_http_smoke.py
python3 supabase/tests/local_guardian_signup_http_smoke.py
python3 supabase/tests/local_staff_http_smoke.py
python3 supabase/tests/local_patient_registration_http_smoke.py
python3 -m unittest supabase/tests/test_local_http_smoke.py
supabase stop --project-id kof5-familiar-voice-mvp
```
