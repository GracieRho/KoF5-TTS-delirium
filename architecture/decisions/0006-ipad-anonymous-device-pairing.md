# ADR-0006: iPad 기기 계정을 현재 입원에 별도 연결

- 상태: 제안됨
- 작성일: 2026-09-16
- 관련 문서: [MVP PRD](../../docs/Delirium_Familiar_Voice_MVP_PRD.md), [환자 시험 전 안전 게이트](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md), [ADR-0004](0004-supabase-auth-postgres.md)

## 배경

보호자 기억은 보호자 본인의 Supabase Auth 세션과 검증된 환자 연결로 보호된다. 병상 iPad의 내부 시험 토큰에는 환자·현재 입원·보호자 권한이 없으므로 그 토큰으로 가족 기억을 가져올 수 없다.

## 결정

1. iPad는 **별도의 Supabase 익명 Auth 사용자**로 로그인한다. 보호자나 직원의 비밀번호·JWT를 iPad에 옮기지 않는다. 익명 JWT와 사용자 ID는 시험 세션의 메모리에만 두고 중단·철회·백그라운드 전환 시 지운다. 재연결에는 새 로그인과 직원 확인이 필요하다.
2. 검증된 담당 직원만 병원 화면에서 iPad 사용자 ID를 현재 입원에 연결한다. 기기는 자기 배정만 조회하고, 합성 대화 서버는 `api.patient_family_turn_context` 한 번으로 기기 권한과 가족 기억 최대 세 건을 같은 DB 스냅샷에서 확인한다. 유효한 빈 기억과 철회된 권한을 구분하며, 보호자 편집 화면·민감 정보·피할 주제는 기기에 열지 않는다. 공개 클라이언트와 Vercel API는 publishable 키와 기기 JWT만 사용한다.
3. 현재 구현은 고정 **합성 fixture UUID**에만 연결·검색을 허용한다. 실제 환자 UUID는 DB와 FastAPI에서 거절한다. 기관 정체성 고지, 경보 전달/확인, 동의·거부 업무 흐름 및 보안 검토가 [Gate07](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)을 충족한 뒤에만 범위를 다시 결정한다.

## 결과와 검증

- 작업 전용 로컬 PostgreSQL 17에서 마이그레이션과 pgTAP 186개, advisor 검사가 통과했다. 로컬 GoTrue/Data API HTTP에서 익명 계정 생성, 미배정 직원·기기 자체 연결 거절, 담당 직원 연결, 질문에서 합성 보호자 기억 검색, 보호자 연결·주변 음성 동의 철회 후 차단을 확인했다. 같은 JWT로 FastAPI가 DB 기억을 읽고 모의 음성 파이프라인에 넘기는 경로도 확인했다.
- 익명 계정이 `authenticated` 역할을 쓰는 점과 호출자 RLS 뷰의 필요성은 [Supabase 익명 로그인](https://supabase.com/docs/guides/auth/auth-anonymous), [RLS 문서](https://supabase.com/docs/guides/database/postgres/row-level-security)를 따른다.
- 전용 원격 Supabase/Vercel 프로젝트, 실제 iPad, 보호자 목소리 공급자와 병원 운영 절차는 검증하지 않았다. 이 ADR은 실제 환자 시험 승인으로 해석하지 않는다.
