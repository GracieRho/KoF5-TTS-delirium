# ADR-0004: 로그인과 환자 데이터에 Supabase Auth/Postgres 사용

- 상태: 승인됨
- 작성일: 2026-09-15
- 관련 문서: [MVP PRD](../../docs/Delirium_Familiar_Voice_MVP_PRD.md), [병원 등록 설계](../../docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md), [환자 시험 전 안전 게이트](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md), [ADR-0002](0002-ipad-local-audio-vercel-first.md)

## 배경

Vercel은 첫 웹/API 배포 대상이다. 보호자·직원 로그인, 환자·입원·동의·화자 특징 메타데이터와 대화 상태는 서버 함수의 메모리 밖에 보관해야 한다. 이 데이터의 권한 경계는 병원 기관·담당 범위와 보호자 연결을 따로 검증해야 한다.

## 결정

1. 보호자와 병원 직원 로그인은 **Supabase Auth**, 환자 관련 관계형 데이터는 **Supabase Postgres**를 사용한다. Vercel은 첫 웹/API 배포 대상으로 유지한다.
2. 환자·입원·동의·목소리 프로필/샘플은 Data API에 노출되지 않는 `kof5` 스키마에 둔다. 모든 테이블은 `FORCE RLS`이고, 병원 직원의 검증된 기관·담당 범위와 보호자의 검증된 환자 연결을 Auth 사용자에 매핑한다. 공개 API는 필요한 `api` 스키마의 호출자 RLS 뷰로 제한한다. [Supabase RLS 문서](https://supabase.com/docs/guides/database/postgres/row-level-security)가 구분하듯 사용자 수정이 가능한 Auth `user_metadata`를 권한 근거로 쓰지 않는다.
3. iPad·보호자 웹에 Supabase 비밀 키나 데이터베이스 접속 정보를 넣지 않는다. 실제 환자 데이터 처리 API는 사용자 세션 검증, 유효한 목적별 동의, 환자 assent/거부, 감사·삭제 경로를 확인한 뒤 연다.
4. 원본 환자/보호자 음성의 객체 저장 서비스·기간, pgvector 활성화와 의료기관 EHR 연동은 별도로 결정한다. Supabase Auth/Postgres 선택만으로 실제 환자 정보 이전이나 시험을 승인하지 않는다.

## 결과와 검증

- [세 로컬 마이그레이션](../../supabase/README.md)은 작업 전용 Supabase PostgreSQL 17에 적용했고, 합성 환자 제약 검사와 직원 15개·보호자 17개 권한 검사가 통과했다. 로컬 advisor도 문제를 보고하지 않았다. 실제 Auth/Data API HTTP 호출, 전용 원격 프로젝트와 기관 승인 흐름은 아직 검증하지 않았다.
- 기존 계정의 `yai-hub-production` 프로젝트는 이 MVP와 별개라 연결하거나 변경하지 않는다. 전용 프로젝트의 조직·지역·계획·PostgreSQL 버전, 기관 데이터 처리 계약을 확인하고 연결한다.
- 실제 환자 사용에는 [안전 게이트](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)의 네 조건과 기관 검토가 여전히 필요하다.
