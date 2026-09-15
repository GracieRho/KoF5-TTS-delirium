# Supabase Auth/Postgres 작업 경계

보호자·병원 직원 로그인과 환자 데이터 저장은 Supabase Auth/Postgres를 사용한다. 웹/API의 첫 배포 대상은 Vercel이다. 첫 마이그레이션은 [병원 등록 설계](../docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md)의 환자·입원·동의·환자 목소리 프로필/샘플을 PostgreSQL 제약으로 옮긴 **초안**이다. 둘째 마이그레이션은 Supabase Auth 사용자와 병원 직원 자격·환자 담당 배정을 연결하고, 읽기 전용 환자 목록을 추가한다.

- `kof5` 스키마는 Data API에 노출하지 않는다. 모든 테이블에 `FORCE ROW LEVEL SECURITY`를 적용한다. 인증된 직원은 **검증된 현재 기관 자격**이 있는 경우에만 해당 기관 환자를 읽고, 담당 직원은 **검증된 현재 배정 환자**만 읽는다. `api.hospital_patient_list`는 호출자 RLS를 따르는 읽기 전용 뷰다. 동의·음성 테이블에는 클라이언트 읽기 권한을 주지 않았다. 전용 원격 프로젝트에서는 `api` 스키마를 Data API 설정에도 별도로 노출해야 한다.
- 원본 음성과 임베딩 본문은 테이블에 두지 않는다. 샘플에는 일시 암호화 객체 참조와 폐기 시각만, 프로필에는 암호화된 특징 참조와 모델 버전만 둔다.
- 직원 자격과 담당 배정을 **누가 검증·기록하는지**, 유효한 동의·환자 assent/거부, 보호자 연결, 철회 시 삭제 트랜잭션과 감사 기록은 아직 구현되지 않았다. 실제 환자 자료 입력 전에 기관 승인 절차가 필요하다.
- 마이그레이션을 기존 `yai-hub-production` 프로젝트에 적용하지 않는다. 이 MVP 전용 프로젝트의 PostgreSQL 버전·지역·계획과 기관 데이터 처리 조건을 확인한 뒤 연결한다. 실제 환자 자료는 [안전 게이트](../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md) 통과 전 입력하지 않는다.

합성 데이터 제약 검사는 **버려도 되는 독립 PostgreSQL DB**에 마이그레이션을 적용한 뒤 실행한다.

```bash
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260915120212_hospital_registry_voice_profile.sql
psql -v ON_ERROR_STOP=1 -f supabase/tests/registry_constraints.sql
```

2026-09-15 검증은 임시 PostgreSQL 18.4, 별도 `postgres:17` 작업 컨테이너, 그리고 **이 작업의 로컬 Supabase PostgreSQL 17**에서 합성 제약 검사가 통과했다. 첫 두 작업 DB와 익명 볼륨은 제거했다. 로컬 Supabase DB에는 두 마이그레이션이 적용됐고, 직원 권한 pgTAP 테스트 **15개**가 통과했다. CLI advisor는 `No issues found`를 보고했다. 로컬 Data API/GoTrue 실제 HTTP 호출, 전용 원격 프로젝트, Auth/Storage와 기관 승인 흐름은 검증하지 않았다. CLI `db query --file`은 여러 SQL 명령을 한 prepared statement로 넣어 실패하므로, 제약 검사는 컨테이너 내부 `psql`로 실행한다.

```bash
docker exec -i supabase_db_kof5-familiar-voice-mvp psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/registry_constraints.sql
supabase test db --local supabase/tests/staff_read_rls.test_test.sql
supabase db advisors --local
supabase migration list --local
```
