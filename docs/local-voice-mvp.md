# 가족 목소리 MVP 로컬 시연

토큰을 기다리는 동안 보호자 역할의 성인 본인 음성과 **가상 가족 기억**으로 등록→기억 입력→질문→음성 답변을 확인하는 단일 운영자 공간이다. 실제 환자 서비스나 원격 Supabase 승인을 대신하지 않는다.

## 실행

저장소의 이 작업 브랜치에서 실행한다.

```bash
uv sync
npm ci --prefix apps/portal_web
npm run build --prefix apps/portal_web
KOF5_LOCAL_STUDIO=1 uv run uvicorn app:app --host 127.0.0.1 --port 8766
```

브라우저에서 `http://127.0.0.1:8766/studio`를 연다. 기본 API는 꺼져 있으며 `KOF5_LOCAL_STUDIO=1`이 있어도 Vercel 환경, 외부 Host/클라이언트, 타 출처 요청을 차단한다. 공통 웹 셸은 기존 `/guardian`, `/hospital`에도 적용된다.

### 공급자 키

로컬 서버는 저장소 루트의 Git 제외 `.env`에서 아래 세 공급자 키를 읽는다. 이미 설정된 환경 변수가 우선하며, worktree의 `.env`가 없거나 키가 빠진 경우 원본 저장소의 `.env`를 확인한다. 셸 명령이나 변수 치환은 실행하지 않는다. Vercel에서는 로컬 파일을 읽지 않는다. 키는 브라우저에서 받거나 응답에 반환하지 않는다.

| 환경 변수 | 용도 | 없을 때 |
|---|---|---|
| `ELEVENLABS_API_KEY` | IVC 생성·상태 확인·TTS·삭제 | 녹음 등록·음성 답변 차단 |
| `OPENAI_API_KEY` | 짧은 한국어 답변 생성 | 대화 전송 차단 |
| `DEEPGRAM_API_KEY` | 선택적 30초 질문 녹음 전사 | 글 질문은 가능 |
| `KOF5_STUDIO_DB` | 선택적 SQLite 경로 | `runs/local-studio/workspace.sqlite3` |

Vercel/Supabase 관리 토큰은 위 런타임 키와 다르다. 토큰이 없어도 화면과 가족 소개·기억 CRUD는 사용할 수 있다. 실제 생성에는 공급자 계정·해당 기능 권한/할당량이 필요하고 요청 비용이 발생할 수 있다. 이번 작업에서는 유료 요청을 실행하지 않았다.

셸 기록에 키를 남기지 않으려면 zsh에서 다음처럼 숨김 입력을 사용한다.

```zsh
read -s 'ELEVENLABS_API_KEY?ElevenLabs key: '; export ELEVENLABS_API_KEY
read -s 'OPENAI_API_KEY?OpenAI key: '; export OPENAI_API_KEY
```

## 시연 순서

1. **우리 가족 소개**: 시연용 이름·상대 별칭·관계·호칭을 저장한다.
2. **목소리 등록**: 본인 음성과 ElevenLabs 전송에 동의하고 20~30초 WAV 샘플 세 개를 녹음한다. 샘플을 미리 들은 뒤 등록한다. 원본은 브라우저 메모리/요청 중에만 있고 서버 DB에 저장하지 않는다.
3. **가족의 기억**: 일상·추억·좋아하는 것·피해야 할 이야기를 작성·수정·삭제한다. 일반 기억은 최소 한 건 필요하다.
4. **대화해보기**: 기억/질문의 OpenAI 전송과 답변의 ElevenLabs 전송에 동의하고 질문한다. 녹음 질문은 Deepgram 전사 후 입력란에 보여주며 직접 확인·수정한 뒤 전송한다.
5. **답변 재생**: 생성된 글과 오디오를 확인하고 직접 재생한다. 브라우저 기본 음성이나 임의의 다른 목소리로 대체하지 않는다.
6. **사용 중단/삭제**: 등록 화면에서 clone 사용을 중단하고 공급자 삭제 후 목록 부재까지 확인한다. 실패하면 `deletion_pending`을 유지한다.

## 동작과 경계

- 로컬 SQLite 한 작업 공간이며 로그인·기관별 분리가 없다. 여러 사용자/기기용 서버로 열지 않는다. 한 프로세스/worker로 실행한다.
- SQLite는 Git 제외 경로와 파일 권한 0600을 사용한다. 파일 자체는 암호화되지 않는다. 가족 소개·기억·clone 식별자/상태를 저장하고 원본 녹음·API 키·대화 전사/응답은 저장하지 않는다.
- UI는 마지막 질문/답변만 페이지 메모리에 표시한다. 이전 대화 이력을 모델에 다시 보내는 장기 대화는 구현하지 않는다.
- 최대 30개·각 1200자 기억을 전체 문맥으로 전달한다. “관련 기억 검색 정확도”를 입증한 RAG가 아니다. 피해야 할 소재는 별도 지시로 전달하며 임상 수준 차단을 보장하지 않는다.
- 기존 `generate_short_reply`의 짧은 답변·가족 사칭/의료 문구/미확인 사실 제한과 ElevenLabs helper를 재사용한다. `family` 관계·호칭과 `avoid_topics`의 취급 지시를 덧붙인다.
- POST 전 `pending`을 영속 저장하여 생성 응답이 유실돼도 무작정 다시 만들지 않는다. 고유 시험 이름으로 조회하고 원격 본인 인증 상태가 확인된 경우에만 사용할 수 있다.
- 공급자 인증이 필요하면 ElevenLabs 계정에서 본인이 처리한 뒤 원격 상태 확인을 누른다. 인증/불명확 상태를 자동으로 건너뛰지 않는다.
- 공급자 삭제 성공 뒤 DB 기록이 실패하면 재시도 404를 성공으로 간주하지 않아 수동 대조가 필요할 수 있다. 목록에서의 부재는 공급자 백업/보존 자료의 삭제 증명이 아니다.
- 동의 해제/탭 숨김/화면 종료 시 녹음 트랙과 응답 재생을 정리한다. 이미 공급자에 보낸 요청의 전송을 취소하거나 원격 보존 자료를 삭제한다는 뜻은 아니다.

## 원격 MVP로 남은 일

- Vercel 500 실행 로그 확인·수정·재배포 검증.
- 전용 Supabase 프로젝트의 migration/RLS/Auth·`api` 스키마 노출·앱 환경 변수 확인.
- 로컬 SQLite 공간을 외부에 공개하는 대신 기존 인증·검증된 보호자 연결·동의/철회 업무 경로로 통합.
- 실제 ElevenLabs IVC 생성·한국어 음색/명료도·삭제, LLM 질문/기억 정확도·응답 지연과 마이크 실기기 확인.
- 실제 가족 정보 입력과 환자 대상 사용은 별도 동의·보존/삭제·기관/임상 검토 및 Gate07 충족 뒤 진행.

## 검증

```bash
.venv/bin/python -m unittest tests.integration.test_local_studio tests.integration.test_cloud_prototype tests.integration.test_synthetic_api
npm run check --prefix apps/portal_web
python3 scripts/generate_architecture.py --check
python3 -m unittest scripts/test_generate_architecture.py
git diff --check
```

검사는 임시 DB·무음 합성 WAV·모의 공급자만 사용한다. 실제 API 왕복과 한국어 음질을 통과했다는 의미는 아니다. 시각 증거와 실행 결과는 `docs/validation/guardian-voice-mvp/`에 기록한다.
