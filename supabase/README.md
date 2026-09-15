# Supabase Auth/Postgres 작업 경계

보호자·병원 직원 로그인과 환자 데이터 저장은 Supabase Auth/Postgres를 사용한다. 웹/API의 첫 배포 대상은 Vercel이다. 첫 마이그레이션은 [병원 등록 설계](../docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md)의 환자·입원·동의·환자 목소리 프로필/샘플을 PostgreSQL 제약으로 옮긴 **초안**이다. 둘째는 Auth 직원 자격·담당 배정과 읽기 전용 환자 목록, 셋째는 보호자 연결·가족 기억, 넷째는 직원 승인 병원 사실·메시지를 추가한다.

다섯째 마이그레이션은 `api.hospital_patient_registration`에 환자 기본정보 INSERT 권한을 추가한다. `kof5.hospital_registry_activation`은 **기본 0행·클라이언트 쓰기 불가**인 기관별 서버 승인 게이트다. 기관 승인과 임상 안전 승인 참조가 기록되고 아직 유효하며, 현재 검증된 해당 기관 `registrar`가 로그인한 경우에만 RLS가 등록을 허용한다. `registered_by_staff_ref`에는 입력 문구 대신 Auth 사용자 ID가 자동 기록되고 RLS가 일치를 재검사한다. 기존 `(hospital_ref, ehr_patient_ref)` 중복 제약은 그대로 적용된다. `care_staff`, 자격 대기·만료·철회, 다른 기관, 비로그인은 등록할 수 없다. 환자 수정·입원·동의·목소리·승인 사실 입력은 계속 열지 않았다. **실제 기관 자격 검증/배정·동의·안전 승인 서버 업무 흐름은 아직 구현되지 않았으므로 실제 승인 게이트 행을 만들거나 실환자 자료를 입력하지 않는다.** 로컬 pgTAP에서는 `TEST-*` 참조와 합성 계정만 트랜잭션 안에서 시험한다.

- `kof5` 스키마는 Data API에 노출하지 않는다. 모든 테이블에 `FORCE ROW LEVEL SECURITY`를 적용한다. 인증된 직원은 **검증된 현재 기관 자격**이 있는 경우에만 해당 기관 환자를 읽고, 담당 직원은 **검증된 현재 배정 환자**만 읽는다. `api.hospital_patient_list`는 호출자 RLS를 따르는 읽기 전용 뷰다. 동의·음성 테이블에는 클라이언트 읽기 권한을 주지 않았다. 전용 원격 프로젝트에서는 `api` 스키마를 Data API 설정에도 별도로 노출해야 한다.
- 원본 음성과 임베딩 본문은 테이블에 두지 않는다. 샘플에는 일시 암호화 객체 참조와 폐기 시각만, 프로필에는 암호화된 특징 참조와 모델 버전만 둔다.
- 보호자는 자기 환자 연결의 상태만 읽는다. **검증된 유효 연결**이 있을 때에만 자기 가족 기억을 읽고 기록·수정할 수 있으며, 환자 번호·생년월일·입원·동의·음성 메타데이터는 읽을 수 없다. 철회/만료 즉시 가족 기억 접근도 차단한다. 원문은 `family_fact`에 저장하고, 임베딩/검색 모델은 아직 정하지 않았다.
- 병원 사실의 공개 뷰는 직원 승인·유효 기간·현재 입원을 확인한다. 병실·검사 사실은 특정 입원에 묶고, 입원 참조가 없는 사실은 병원 이름(`hospital`)만 허용한다. 병원 이름도 진행 중인 입원이 없으면 조회되지 않는다. 병원 메시지는 승인 원문·예약 시각·전달 상태를 분리하고, 승인 문구와 승인자·시각은 수정할 수 없다. 직원도 클라이언트에서 사실·메시지를 직접 등록하거나 승인할 수 없다. 실제 기관 승인/취소·전달·감사 API는 아직 구현 전이다.
- 직원 자격과 담당 배정을 **누가 검증·기록하는지**, 유효한 동의·환자 assent/거부, 보호자 연결, 철회 시 삭제 트랜잭션과 감사 기록은 아직 구현되지 않았다. 실제 환자 자료 입력 전에 기관 승인 절차가 필요하다.
- 마이그레이션을 기존 `yai-hub-production` 프로젝트에 적용하지 않는다. 이 MVP 전용 프로젝트의 PostgreSQL 버전·지역·계획과 기관 데이터 처리 조건을 확인한 뒤 연결한다. 실제 환자 자료는 [안전 게이트](../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md) 통과 전 입력하지 않는다.

합성 데이터 제약 검사는 **버려도 되는 독립 PostgreSQL DB**에 마이그레이션을 적용한 뒤 실행한다.

```bash
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260915120212_hospital_registry_voice_profile.sql
psql -v ON_ERROR_STOP=1 -f supabase/smoke/registry_constraints.sql
```

2026-09-16 현재 검증은 임시 PostgreSQL 18.4, 별도 `postgres:17` 작업 컨테이너, 그리고 **이 작업의 로컬 Supabase PostgreSQL 17**에서 합성 제약 검사가 통과했다. 첫 두 작업 DB와 익명 볼륨은 제거했다. 로컬 Supabase DB에는 다섯 마이그레이션이 적용됐고, 직원 15개·보호자 17개·병원 사실/메시지 25개·환자 등록 17개인 pgTAP **74개**가 통과했다. 퇴원 후 사실·메시지 차단과 재입원 시 이전 입원 정보 제외도 검사했다. CLI advisor는 `No issues found`를 보고했다. 작업 전용 **로컬 GoTrue/Data API HTTP**에서 합성 보호자·직원 경계와 등록자 Auth/기관 승인 게이트·참조 위조·중복·철회·비로그인 차단이 통과했고, 새 등록 시험 환자·계정·게이트 행은 0건으로 정리했다. 전용 원격 프로젝트, 실제 기관 직원 승인·Auth/Storage와 환자 데이터 처리 흐름은 검증하지 않았다. CLI `db query --file`은 여러 SQL 명령을 한 prepared statement로 넣어 실패하므로, 제약 검사는 컨테이너 내부 `psql`로 실행한다.

```bash
docker exec -i supabase_db_kof5-familiar-voice-mvp psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/smoke/registry_constraints.sql
supabase test db --local
supabase db advisors --local
supabase migration list --local
```

로컬 HTTP 검사는 작업 전용 Supabase DB/Auth/Data API/Kong을 켠 뒤 실행한다. `local_http_smoke.py`와 `local_staff_http_smoke.py`는 실행 위치와 관계없이 이 작업 설정을 읽고 `127.0.0.1:54341`만 허용한다. 브라우저와 같은 **publishable 키**를 사용한다. 임의 비밀번호와 `example.invalid` 합성 계정을 사용하고 로컬 키·토큰을 출력하지 않으며, 생성 응답이 유실돼도 이번 합성 이메일로 계정을 찾아 환자·기억·계정을 삭제한다. 직원 검사는 다른 기관 환자·승인 사실·메시지가 조회되지 않고 자격 철회 후 세 뷰가 비워지는 것을 확인한다. 공유 `yai-hub` 인스턴스에는 적용하지 않는다. 별도 `/guardian` 보호자 웹도 로컬 합성 계정의 로그인·가족 기억 저장/재조회·연결 철회 후 거부 및 기존 기억 숨김을 브라우저에서 확인했다.

```bash
supabase start --exclude edge-runtime,imgproxy,mailpit,postgres-meta,realtime,storage-api,studio,logflare,vector,supavisor
python3 supabase/tests/local_http_smoke.py
python3 supabase/tests/local_staff_http_smoke.py
python3 supabase/tests/local_patient_registration_http_smoke.py
python3 -m unittest supabase/tests/test_local_http_smoke.py
supabase stop --project-id kof5-familiar-voice-mvp
```
