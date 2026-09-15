# Supabase Auth/Postgres 작업 경계

보호자·병원 직원 로그인과 환자 데이터 저장은 Supabase Auth/Postgres를 사용한다. 웹/API의 첫 배포 대상은 Vercel이다. 이 폴더의 첫 마이그레이션은 [병원 등록 설계](../docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md)의 환자·입원·동의·환자 목소리 프로필/샘플을 PostgreSQL 제약으로 옮긴 **초안**이다.

- `kof5` 스키마는 Data API에 노출하지 않는다. 모든 테이블에 `FORCE ROW LEVEL SECURITY`를 적용하고 정책과 클라이언트 권한을 아직 부여하지 않아 기본적으로 접근이 차단된다.
- 원본 음성과 임베딩 본문은 테이블에 두지 않는다. 샘플에는 일시 암호화 객체 참조와 폐기 시각만, 프로필에는 암호화된 특징 참조와 모델 버전만 둔다.
- 유효한 동의·환자 assent/거부, 직원의 기관·담당 범위, 보호자 연결은 **행 제약만으로 증명되지 않는다**. 인증 사용자와 병원 권한 매핑, RLS 정책, 철회 시 즉시 비활성화·삭제 트랜잭션, 감사 기록을 실제 API 전에 구현해야 한다.
- 마이그레이션을 기존 `yai-hub-production` 프로젝트에 적용하지 않는다. 이 MVP 전용 프로젝트의 PostgreSQL 버전·지역·계획과 기관 데이터 처리 조건을 확인한 뒤 연결한다. 실제 환자 자료는 [안전 게이트](../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md) 통과 전 입력하지 않는다.

합성 데이터 제약 검사는 **버려도 되는 독립 PostgreSQL DB**에 마이그레이션을 적용한 뒤 실행한다.

```bash
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260915120212_hospital_registry_voice_profile.sql
psql -v ON_ERROR_STOP=1 -f supabase/tests/registry_constraints.sql
```

2026-09-15 검증은 임시 PostgreSQL 18.4, 별도 `postgres:17` 작업 컨테이너, 그리고 **이 작업의 로컬 Supabase PostgreSQL 17**에서 마이그레이션과 합성 RLS/제약 테스트가 통과했다. 첫 두 작업 DB와 익명 볼륨은 제거했다. Supabase CLI의 로컬 advisor는 `No issues found`, 마이그레이션 목록은 `20260915120212` 적용을 확인했다. CLI `db query --file`은 여러 SQL 명령을 한 prepared statement로 넣어 실패하므로, 로컬 Supabase DB에서는 아래처럼 컨테이너 내부 `psql`로 테스트한다. 실제 전용 원격 프로젝트의 Auth/Storage·권한 정책·마이그레이션은 아직 검증하지 않았다.

```bash
docker exec -i supabase_db_kof5-familiar-voice-mvp psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/registry_constraints.sql
supabase db advisors --local
supabase migration list --local
```
