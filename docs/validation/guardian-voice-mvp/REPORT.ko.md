# 가족 목소리 MVP 검증 기록

- 날짜: 2026-10-15
- 작업 브랜치: `feat/guardian-voice-mvp`
- 기준: `83caa1f`에서 새 `.worktrees/guardian-voice-mvp` 생성.
- 실제 공급자 호출·환자 자료·운영 DB 쓰기·원격 배포는 수행하지 않음.

## 구현

- `/studio`에 가족 소개, 기억 CRUD/분류, 본인 음성 샘플 세 개, IVC 생성/상태 대조/삭제, 기억을 참고한 음성 답변, 선택적 질문 전사 연결.
- 기존 ElevenLabs/OpenAI/Deepgram helper와 PCM16 WAV 변환 사용. 공급자 키 없이 성공을 흉내 내지 않는다.
- SQLite에 가족 소개·기억·clone 메타데이터를 영속 저장. 명시적 로컬 opt-in, Host/클라이언트/origin/전용 헤더 검사와 요청 크기 제한.
- 시연·보호자·병원은 `WorkspaceShell`·SVG Icon·입력·시트·토스트와 공통 팔레트를 공유.
- `DESIGN.md`를 Rozeta 구성과 사용자 초록/라임/올리브/모스 팔레트 기준으로 갱신.

## 자동 검사

| 검사 | 결과 |
|---|---|
| `tests.integration.test_local_studio`, `test_cloud_prototype`, `test_synthetic_api` | 58개 통과 |
| `npm run check --prefix apps/portal_web` | 웹 29개/17파일 통과, TypeScript 및 Vite 빌드 통과 |
| `scripts/generate_architecture.py --check` | 최신 상태 |
| `python3 -m unittest scripts/test_generate_architecture.py` | 7개 통과 |
| `git diff --check` | 통과 |

새 회귀 검사: 원격/타 출처/API 미활성 요청 거부, 가상 기억 저장·재조회·수정·삭제, 비동의/키 부재 차단, 등록 타임아웃 후 중복 생성 차단, 명시적 공급자 거절 뒤 재시도, 원격 본인 인증 우회 방지, clone 선택과 음성 응답, 전사 동의, 삭제 후 부재 확인. 웹에서는 샘플 세 개가 이전 샘플을 지우지 않고 전송되는지, 마이크 트랙 해제, 저장 실패 후 편집 유지, 동의 전 대화 차단, 응답 오디오 URL 연결을 모의 환경으로 검사했다.

`blob:` 오디오 미리 듣기/응답이 CSP 기본 정책에 막히는 문제를 확인해 media-src에 self/blob만 허용하고 회귀 검사를 추가했다. 공급자 원격 오디오 URL을 프런트에서 직접 로딩하지 않는다.

## 실제 브라우저 검사

Codex In-app Browser에서 1440×1000 및 390×844 CSS viewport를 사용했다.

- 가상 가족 소개 저장 → 진행 상태 갱신.
- 서로 다른 분류의 가상 기억 세 건을 실제 폼으로 저장 → 목록/개수 반영 → 새로고침/서버 재시작 후 유지.
- 모바일 기억 편집 하단 시트, Escape 닫기, 호출 카드로 포커스 복귀.
- 공급자 미연결 시 녹음/복제 등록/대화 전송 비활성 상태와 설명.
- 보호자·병원 로그인 전 공통 셸, 서비스 연결 전 상태와 비활성 로그인.
- 모바일 페이지 너비 390px, 문서 scrollWidth 390px 확인.

PNG는 실제 브라우저 캡처이며 기입된 가족 이야기와 이름은 이 작업에서 만든 가상 자료다. 실제 가족/계정/환자 정보를 포함하지 않는다.

## 남은 검증과 운영 경계

- API 검사는 임시 DB·무음 WAV·모의 공급자다. 실제 ElevenLabs 음색/한국어 명료도/생성·삭제, OpenAI 답변 품질, Deepgram 실음성, 물리적 마이크와 스피커는 검증하지 않았다.
- 실제 결합 생성은 `ELEVENLABS_API_KEY`와 `OPENAI_API_KEY`, 마이크 전사는 선택적 `DEEPGRAM_API_KEY`가 필요하다. 외부 API 호출은 비용과 공급자 처리 조건이 따른다.
- 최대 30건 기억을 전체 문맥으로 전달하는 단일 턴 시연이다. 임상 수준 소재 차단, 의미 검색 평가, 장기 대화 이력, 가족 인격 복제는 제공하지 않는다.
- 현재 SQLite 로컬 공간은 단일 운영자/단일 프로세스용이다. 인증된 다중 사용자 원격 서비스로 공개하지 않는다. 기존 Supabase 승인·보호자 연결 경로로의 원격 통합과 Vercel 500 원인 확인은 계정 접근 뒤 진행해야 한다.
- 로컬 시연 서버는 `127.0.0.1:8766`으로 유지했다. `.venv` 약 16MB, 웹 의존성 약 104MB를 작업 워크트리에서 재사용한다. 디스크 여유 약 68GB. 모델·별도 브라우저 러너·새 UI 패키지는 설치하지 않았다.
