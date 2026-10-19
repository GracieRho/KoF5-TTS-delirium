# Vercel·Supabase 연결

운영 도메인은 `https://kof5-tts-delirium.vercel.app`, 전용 Supabase 프로젝트는 `mvqwzraiganchlkmnegj`입니다. 도커 없이 Management API와 Vercel API로 설정합니다.

## 환경변수

Vercel Production에 다음 값을 설정한 뒤 재배포합니다. Supabase 연동이 자동 생성하는 `SUPABASE_*` 이름만으로는 서버 설정이 채워지지 않습니다.

| 변수 | 용도 |
| --- | --- |
| `KOF5_SUPABASE_URL` | 전용 프로젝트 URL |
| `KOF5_SUPABASE_PROJECT_REF` | 전용 프로젝트 ref |
| `KOF5_SUPABASE_PUBLISHABLE_KEY` | 브라우저 로그인·RLS 요청 |
| `KOF5_SUPABASE_SECRET_KEY` | 서버 전용 보호자 저장소 RPC |
| `KOF5_REMOTE_STUDIO=1` | Vercel에서 계정별 원격 저장 활성화 |

Management API의 secret 키 조회는 `GET /v1/projects/{ref}/api-keys/{id}?reveal=true`를 사용합니다. 기본 조회의 대체 값을 실제 서버 키로 사용하면 401이 발생합니다. 키 값은 출력하거나 Git에 저장하지 않습니다. 관리 토큰 자체를 런타임 환경변수나 프런트엔드에 넣지 않습니다.

## DB·로그인

- `supabase/migrations/`를 버전 순서대로 적용하고 `supabase_migrations.schema_migrations` 이력과 대조합니다. 초기 프로젝트에 기존 29개 마이그레이션을 한 트랜잭션으로 적용했습니다.
- Data API 노출 스키마는 `public,graphql_public,api`입니다. 원본 `kof5`와 `portal_private`는 노출하지 않습니다.
- Auth Site URL은 운영 도메인, redirect 허용 목록은 같은 도메인의 `/studio`, `/hospital`입니다. 이메일 확인을 우회하는 전역 설정은 변경하지 않습니다.
- 로그인만으로 업무 권한을 부여하지 않습니다. 보호자는 유효한 `patient_guardian_link`, 직원은 검증된 `hospital_staff_membership`을 통해 `api.portal_access()`에서 권한을 판정합니다. 사용자 편집 가능 메타데이터는 사용하지 않습니다.
- 보호자 작업 공간은 `kof5.guardian_workspace`에 계정별로 저장합니다. 브라우저 역할에는 테이블·저장 RPC 권한이 없으며, 서버가 매 요청의 보호자 세션을 확인하고 서버 키로 호출합니다. provider voice ID는 공개 응답과 병원 제출에서 제외합니다.
- 저장은 revision을 비교하며 충돌 시 409를 반환합니다. SQLite 파일과 로컬 가상 계정은 자동 업로드하지 않습니다.

## 검증과 한계

`/hospital`, `/studio`의 200 응답은 페이지 제공만 증명합니다. `/portal/config`의 200, Auth 로그인, 역할 판정, 보호자 저장·재조회, 직원의 보호자 API 접근 거부, 로그아웃 뒤 기존 세션 차단을 별도로 검증해야 합니다.

가상 계정·환자 자료의 원격 생성은 별도 승인 범위입니다. 공개 계정에 로컬 공통 비밀번호를 재사용하지 않습니다. 음성 등록·대화·전사는 각각 `ELEVENLABS_API_KEY`, `OPENAI_API_KEY`, `DEEPGRAM_API_KEY`가 필요하며, 연결 키만 설정했다고 음성 공급자 검증까지 완료되는 것은 아닙니다.

이 변경은 저장 위치와 인증 경계만 변경하며 임상 승인·음성 재생 성공을 발급하지 않습니다. 실제 환자 이용은 기존 기관·동의·임상 검토 게이트를 따라야 합니다.
