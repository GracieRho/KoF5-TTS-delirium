# KoF5-TTS-delirium

가족 음성과 환자·병원 맥락을 활용한 한국어 음성 대화·지남력 지원 MVP를 검증하는 프로젝트입니다.

> 현재 제품 방향은 클라우드 중심 MVP입니다. 실제 환자 대상 시험은 [안전·윤리 게이트](docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)와 기관 검토를 완료한 뒤에만 진행하며, 이 시스템은 의료적 판단이나 기존 의료진 호출 수단을 대체하지 않습니다.

## 목표

- 환자가 버튼을 누르지 않고 먼저 말을 걸 수 있는 가족 음성 기반 대화를 검증합니다.
- 보호자 기억과 병원 승인 정보를 분리해 짧은 지남력·대화 응답에 사용합니다.
- 검증 대상은 한국어 명료도, 오작동, 응답 지연, 사실 보존 및 환자 안전입니다.

## 현재 범위

현재 저장소에는 [MVP PRD](docs/Delirium_Familiar_Voice_MVP_PRD.md), 환자 시험 전 안전 게이트, ADR 및 기존 AI Hub 다운로드·오디오 전처리 도구가 있습니다. MVP는 hosted STT·LLM·보호자 음성 복제 TTS를 연결하는 클라우드 중심 흐름을 목표로 합니다. 보호자·직원 로그인과 환자 데이터 저장은 [Supabase Auth/Postgres](architecture/decisions/0004-supabase-auth-postgres.md)로 정했고, 웹/API는 Vercel 우선입니다. 기존 학습·경량화 경로는 이번 MVP의 구현 범위가 아닙니다.

다음은 실측 또는 기관 검토 전까지 확정하지 않습니다.

- STT·LLM·음성 복제 제공업체와 한국어 품질·지연 시간
- iPad Flutter의 실제 마이크·VAD·재생 중단 품질과 Vercel 배포·재연결·네트워크 장애 시 동작
- 병실 주변 음성의 전송·보관 범위, 동의·철회 절차
- 실제 환자 대상 시험 계획과 임상 콘텐츠 승인

## 저장소 구조

```text
.
├── architecture/          # 시스템 구조, 기술 결정 기록
│   └── decisions/         # ADR(Architecture Decision Record)
├── apps/patient_ipad/     # iPad 환자 클라이언트 내부 마이크 시험
├── checkpoints/           # 로컬 모델 체크포인트(파일은 Git 제외)
├── configs/               # 전처리 및 실험 설정
├── data/                  # 기존 연구용 WAV, FLAC(파일은 Git 제외)
├── docs/                  # 프로젝트·연구 문서
├── scripts/               # 실행 진입점과 작업 자동화
├── src/kof5_tts/          # 재사용 가능한 제품·연구 코드
├── supabase/              # Auth/Postgres 설정·환자/직원/보호자 RLS 초안
├── tests/                 # 단위·통합 테스트
├── .editorconfig          # 공통 편집기 설정
├── .gitignore             # 비밀정보, 데이터, 모델 산출물 제외 규칙
└── AGENTS.md              # 저장소에서 작업할 때의 기본 원칙
```

폴더별 역할은 [저장소 구조](docs/repository-layout.md), 문서와 협업 규칙은 [docs/README.md](docs/README.md)와 [docs/contributing.md](docs/contributing.md), 제품 구조와 정책 변경은 [아키텍처](architecture/README.md)와 [ADR 목록](architecture/decisions/README.md)에서 확인할 수 있습니다. 병원 환자 등록·화자 특징의 최소 컬럼은 [병원 등록 설계](docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md)에 정리했습니다.

iPad의 기기 내 발화 후보 감지·한국어 로컬 전사, 글 전용 합성 시험과 수동 자가 음성 오디오 전송은 [환자 앱 내부 시험](apps/patient_ipad/README.md)에 있습니다. 별도 본인 음성·자동 글 시험 스위치를 켠 경우에만 기기에서 판정한 후보의 **글**을 자동 전송합니다. 후보 오디오는 기본적으로 폐기하며 환자/TV/의료진 화자 판정은 아직 없습니다.

## 합성 대화 흐름 확인

```bash
python3 scripts/demo_companion_text.py
```

PRD의 첫 상호작용을 합성 발화·기억으로 검사합니다. 현재 데모에는 마이크, STT, LLM, 음성 복제 및 실제 환자 데이터가 연결되지 않았습니다.

합성 데이터만 받는 로컬 텍스트 API는 다음과 같이 실행합니다.

```bash
uv sync --locked
uv run python scripts/run_backend.py
```

`http://127.0.0.1:8765/health`는 현재 `synthetic_demo_only`를 반환합니다. 환자 ID는 `synthetic_patient`만 허용하며, 일반 대화 API는 합성 텍스트 시험에 한정됩니다. 실제 환자 데이터와 임상 시험에는 사용하지 않습니다.
브라우저에서 `http://127.0.0.1:8765/demo`를 열면 팀 내부 합성 발화를 입력하고 대화 상태·응답·거부·주변 발화 폐기를 확인할 수 있습니다. 화면의 날짜·시간은 한국 시간으로 표시됩니다.
`http://127.0.0.1:8765/demo/hospital`은 가상 환자·입원 등록과 동의 상태에 따른 약 30초 자가 음성 채집 화면을 시험합니다. 입력과 오디오는 브라우저 메모리에서만 처리하고 서버로 보내거나 환자 화자 특징으로 등록하지 않습니다.
`http://127.0.0.1:8765/demo/guardian`은 가상 가족 기억을 화면에서만 바꾸고, 피해야 할 주제가 대화 후보에서 제외되는 것을 시험합니다. 보호자 로그인·환자 연결·기억 저장·음성 등록은 연결되지 않았습니다.

`http://127.0.0.1:8765/guardian`은 별도 **보호자 웹 초안**입니다. 전용 Supabase의 URL과 publishable 키를 서버 환경 변수 `KOF5_SUPABASE_URL`, `KOF5_SUPABASE_PUBLISHABLE_KEY`로 설정해야 로그인할 수 있습니다. 원격 프로젝트에는 `KOF5_SUPABASE_PROJECT_REF`도 설정해야 하며, 공유 `yai-hub-production` 주소는 거부합니다. 보호자는 Auth 계정을 만들 수 있지만, 가입 응답으로 자동 로그인하거나 환자 연결을 스스로 승인하지 않습니다. 별도 로그인 후 병원이 검증한 환자 연결의 가족 기억만 Data API/RLS로 읽고 등록·수정합니다. 피해야 할 주제는 대화 기억과 분리해 보여주며, 보호자 본인이 쓴 일반 기억의 소규모 문자열 검색 RPC도 로컬 합성 계정에서 검사했습니다. 보호자 RPC 자체는 환자 계정에 노출하지 않으며, 별도의 합성 iPad 기기 연결 경로는 유효한 보호자 기억을 매 턴 다시 검색해 글 응답에 공급합니다. 토큰은 페이지 메모리에만 있어 새로고침하면 다시 로그인해야 합니다. 작업 전용 **로컬 합성 계정**에서는 가입·로그인, 연결 없는 계정의 읽기/쓰기 차단, 기억 등록/수정/검색·철회 후 차단을 실제 Auth/Data API로 확인하고 브라우저에서 수정 폼과 로그아웃을 확인했습니다. 원격 이메일 전달·전용 프로젝트·기관 직원 승인·실제 환자 데이터 처리·음성 등록은 아직 연결되지 않았습니다. 실제 가족/환자 정보는 안전 게이트 통과 전 입력하지 마세요.

`http://127.0.0.1:8765/hospital`은 **병원 직원 웹 초안**입니다. 같은 전용 Supabase 설정으로 Auth에 로그인한 뒤 호출자 RLS가 적용된 `api.hospital_patient_list`, `api.hospital_context_current`, `api.hospital_message_list`를 읽습니다. 현재 입원이 없는 환자의 병원 사실·메시지는 조회하지 않고, 승인 메시지 원문과 검증·유효 종료·승인·예약·전달/취소 시각을 한국 시간으로 표시합니다. 현재 등록자 자격과 기관·안전 승인 게이트가 준비된 경우에만 `api.hospital_registration_ready`를 통해 최소 환자 기본정보 등록 폼을 보이며, POST 직전 준비 상태를 다시 읽고 DB RLS가 최종 권한을 확인합니다. 기본 게이트는 0행이라 실제 입력은 열리지 않습니다. 토큰은 페이지 메모리에만 보관하고 로그아웃·자격 거부 시 환자 상세와 등록 입력을 지웁니다. 작업 전용 로컬 합성 직원 계정에서 기관별 조회·등록·중복/위조/철회 차단과 승인 기록 조회를 HTTP로 확인했지만, 실제 기관 직원 자격·임상 승인 업무 흐름, 환자 동의/목소리 등록, 병원 사실 승인·전달은 아직 연결되지 않았습니다.

고정 합성 환자의 **첫 음성 시험 준비**는 담당 `care_staff`·현재 입원·기관 승인·환자 참여 및 음성 기능 동의/assent·입원 중 거부 없음으로 별도 조회합니다. 아직 음성 프로필이 없어도 준비 여부를 판정하며 프로필 상태는 정보로만 표시합니다. 준비된 직원 화면의 30초 이내 **시험자 본인 음성** 마이크 시험은 브라우저 메모리에만 머물고 중단 시 트랙을 닫고 오디오 참조를 버립니다. 업로드·특징 추출·프로필 생성·실제 환자 등록은 하지 않습니다([ADR-0008](architecture/decisions/0008-synthetic-first-voice-enrollment-readiness.md)).

고정 합성 환자 UUID에 한해서는 병원 담당 직원의 `api.synthetic_device_pairing_ready` 조회가 현재 입원과 일치할 때 iPad 익명 Auth 사용자 ID만 연결할 수 있습니다. 실제 환자 배정은 DB에서 차단하며, 화면의 연결 폼은 동의나 임상 승인 업무를 대신하지 않습니다. 로컬 GoTrue/Data API에서 직원·기기 자체 연결 거절, 담당 직원 연결, 철회 뒤 기억 접근 차단을 확인했습니다.

iPad 앱의 글 전용 내부 시험은 응답 재생 종료 뒤 듣기를 재개합니다. MP3가 없는 안전 응답도 듣기를 재개하되 서버가 응답을 거부하면 자동 글 전송을 멈춥니다. 기기 내에서 명시적 거부 후보를 확인하면 서버 전송 없이 듣기·자동 글 시험을 중단하고 본인 음성 동의를 새로 확인해야 재개합니다. 별도의 재생 중 끼어들기 실험에서는 응답 중 마이크 후보로 재생을 중단하고 기기 안에서 전사한 뒤, 시험자가 본인 목소리였음을 직접 확인해야 글을 보냅니다. 실제 iPad의 음향·한국어 인식 검증 전에는 자동 환자 끼어들기 기능으로 사용하지 않습니다.

iPad의 합성 기기 연결 모드는 익명 JWT를 메모리에만 두고 병원 연결·현재 입원을 확인한 뒤 글만 전송합니다. 중단·철회·백그라운드 전환 시 JWT를 지우고, 연결이 끊겨도 기존 내부 시험 API로 자동 전환하지 않습니다. 원격 Supabase와 paired API는 각각 정확한 빌드 설정 주소가 없으면 차단됩니다. 실제 iPad와 원격 서비스는 아직 검증하지 않았습니다.

내부 오디오 API `POST /internal/synthetic/audio`는 `KOF5_INTERNAL_DEMO_TOKEN`(32자 이상), 공급자 키·voice ID, `VOICE_OWNER_CONSENT_RECORD_ID`가 서버에 설정된 경우에만 열립니다. 요청에는 `X-Internal-Demo-Token`, `X-Synthetic-Material: confirmed`, `Content-Type: audio/wav`가 필요하며, PCM16 WAV 원문(2 MB 이하·30초 이하)을 전송합니다. 응답은 전사·짧은 답·MP3의 base64입니다. 이 확인은 내부 시험자의 선언이며 실제 동의 검증이나 환자 인증이 아닙니다. 오디오는 메모리에서만 처리하고 앱 DB에 저장하지 않습니다. 실제 환자 오디오를 보내지 마세요.

별도 `POST /internal/synthetic/text`는 같은 내부 토큰·합성 자료 확인·시험 음성 소유자 동의 표시를 요구하고, `Content-Type: application/json`의 4 KB 이하 `{"transcript":"...","label":"DIRECTED"}`를 받습니다. 이 경로는 후보 오디오를 받거나 hosted STT를 호출하지 않으며, `AMBIENT`/거부 발화는 음성 응답 없이 폐기합니다. 글은 hosted LLM에, 승인된 짧은 답은 시험 TTS 제공업체에 전달될 수 있습니다. 모델이 만든 의료 진단·처방·약물 조언과 출처 없는 합성 사실은 TTS 전에 차단하지만 실제 임상 안전성은 검증하지 않았습니다. iPad 내부 시험 화면은 시험자 본인 음성·기기 내 전사·별도 스위치를 켠 경우에만 이름 호출과 짧은 후속 질문의 글을 이 API로 보냅니다. 이름/질문 규칙은 TV·의료진 발화나 환자 화자를 구분하지 못합니다. 글 전용 시험은 정상 재생 종료 또는 MP3 없는 안전 응답 뒤 상태가 확인될 때 듣기를 재개하고, 서버가 응답을 거부하면 자동 글 전송을 중단합니다. 수동 오디오 전송 후에는 직접 다시 켜야 합니다. 실제 환자 오디오·글은 안전 게이트 통과 전 보내지 않습니다.

별도 `POST /internal/synthetic/paired/00000000-0000-4000-8000-000000000975/text`는 기존 내부 합성 토큰과 **기기 Supabase Auth JWT**를 함께 요구합니다. 주변·불확실·거부 발화는 외부 전송 전에 버립니다. 일반 가족 질문은 기기 배정·동의를 사전 확인한 뒤 임시 임베딩을 만들고, `api.patient_family_semantic_turn_context` 한 번으로 현재 권한과 일반 가족 기억 최대 세 건을 같은 DB 스냅샷에서 다시 확인합니다. 병원 질문은 별도 승인 사실 RPC를 사용합니다. 기억이 없으면 확인된 정보가 없다고 답합니다. 로컬 Auth/Data API와 모의 공급자 연결은 통과했지만 한국어 의미 검색 품질·실제 공급자·iPad·환자 자료는 검증되지 않았습니다.

연결된 합성 글 요청은 iPad에서 생성한 UUIDv4 `client_turn_id`를 받습니다. 서버는 현재 입원·동의·보호자 연결을 다시 확인해 **정확히 하나의 사용 가능한 보호자 시험 clone**을 선택한 뒤에만 TTS를 호출하며, 이 경로에는 Deepgram STT 키나 서버의 고정 voice ID가 필요하지 않습니다. 후보 음성의 전송·등록과 실제 보호자 음성 재생은 검증하지 않았습니다. [보호자 clone 선택 migration](supabase/migrations/20260916163000_synthetic_patient_tts_voice_selection.sql)은 고정 합성 환자에만 적용됩니다.

병원 이름·병실·병동·검사/면회 일정 질문에서는 별도 `api.patient_hospital_turn_context`가 **고정 합성 환자**의 기기 권한과 현재 입원의 짧은 승인 사실을 한 DB 조회에서 확인합니다. 승인·유효 시각·입원 범위·안전 범주·질문과의 연결을 제한하고, 정확히 한 사실을 찾지 못하면 확인되지 않았다고 답합니다. 직원 출처 ID는 기기 응답에 넣지 않습니다. [합성 병원 사실 migration](supabase/migrations/20260915183905_patient_hospital_turn_context.sql)의 어휘 규칙과 로컬 합성 자료는 실제 병원 출처·임상 문구 승인이나 한국어 질문 품질을 증명하지 않습니다.

합성 병원 메시지는 고정 합성 환자·현재 입원·세 동의·활성 음성 프로필이 모두 준비된 경우에만 담당 직원이 초안을 쓰고 **다른 담당 직원**이 승인해 예약 큐에 넣습니다. 기기는 익명 JWT로 기한이 된 메시지 ID 최대 세 개를 찾고, 개별 RPC에서 권한과 승인 원문을 다시 확인합니다. `POST /internal/synthetic/paired/{patient_id}/message/{message_id}/audio`는 원문을 언어 모델로 다시 쓰지 않고 시험 TTS에 그대로 보냅니다. iPad는 RPC 원문과 API 원문이 완전히 일치할 때만 수동 재생하며, 재생 중단·철회 시 폐기합니다. 이 경로는 DB 메시지를 `pending`에서 `delivered`로 바꾸거나 의료진 확인을 기록하지 않습니다. 실제 환자·실기기·실제 공급자와 임상 원문 승인·전달은 아직 검증하지 않았습니다.

합성 보조 알림은 iPad의 **자가 음성 합성 시험 후보**에서 위험 구절과 이름 호출을 확인한 뒤, 기기 JWT로 `patient_id`(고정 합성 UUID)·위험 `category`·중복 방지 UUID만 DB RPC에 보냅니다. 전사 원문·오디오는 알림 요청에 넣지 않습니다. `created`는 DB 행 생성, `delivered`는 담당 직원의 **합성 포털 표시 수신 기록**, `acknowledged`는 담당 직원의 명시 확인, `resolved`는 후속 조치 완료 표시, `failed`는 포털 표시/직원 확인 시간 초과입니다. 포털 목록을 읽기만 해서는 `delivered`가 되지 않으며, 실패 판정은 담당 직원의 상태 변경 동작 또는 명시적 sweep 때만 실행되고 **상시 cron/외부 발송은 없습니다**. iPad에는 항상 “기존 호출 버튼을 이용해주세요”라고 안내하지만 실제 간호 호출 장치와 연결된 fallback은 아닙니다. [합성 보조 알림 migration](supabase/migrations/20260915183701_synthetic_aux_alert.sql)과 [ADR-0007](architecture/decisions/0007-synthetic-auxiliary-alert-state-boundary.md)은 실제 의료진 전달·ACK·임상 조치를 증명하지 않습니다. 환자 시험에는 [Gate07](docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)의 폐루프 검증, 전용 원격 배포, 실기기·공급자 시험과 기관 승인이 먼저 필요합니다.

루트 `app.py`와 `vercel.json`은 [Vercel FastAPI 진입점](https://vercel.com/docs/frameworks/backend/fastapi) 및 Python 함수 번들 제외 설정입니다. 현재 **합성 텍스트 API와 인증된 내부 오디오 시험 API의 배포 준비** 단계입니다. 메모리 세션은 함수 인스턴스 간 공유·영속화되지 않으므로 실제 환자 서비스나 다중 인스턴스 대화에 사용할 수 없고, Vercel 배포도 아직 실행하지 않았습니다.

별도 `cloud_prototype.py`에는 Phase 0용 배치 WAV→STT→LLM→MP3 호출을 합성 데이터 기준으로 구현했습니다. Deepgram Nova-3, OpenAI Responses, ElevenLabs IVC는 현재 **비교 후보**이고, 공급업체 선정과 실제 서비스 검증은 남아 있습니다. [Deepgram MIP 제외](https://developers.deepgram.com/docs/the-deepgram-model-improvement-partnership-program)와 [OpenAI `store=false`](https://developers.openai.com/api/docs/guides/your-data)를 요청에 적용하지만, [ElevenLabs 복제 음성 샘플은 Zero Retention 적용 대상이 아니므로](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode) 실제 보호자 샘플 등록은 동의·보존·삭제 계약을 확인하기 전까지 진행하지 않습니다. CLI는 첫 hosted TTS 바이트와 MP3 완료 시각을 구분하며 실제 iPad 첫 청취 오디오 목표는 아직 측정하지 못했습니다. 테스트는 네트워크 없이 모의 응답만 사용합니다.

후보 API를 실제 합성 자료로 시험할 때는 세 API key, `ELEVENLABS_VOICE_ID`, `VOICE_OWNER_CONSENT_RECORD_ID`를 로컬 환경 변수에 설정하고 `uv run python scripts/demo_cloud_pipeline.py <합성 WAV> --synthetic-only`를 실행합니다. 동의 기록 ID 입력은 **내부 시험자의 확인 표시**일 뿐 실제 환자 시험의 승인·동의 절차가 아닙니다. Deepgram에는 WAV, OpenAI에는 전사 문장과 합성 사실, ElevenLabs에는 응답 문장과 시험용 voice ID가 전달됩니다. 결과 MP3는 Git에서 제외된 `runs/synthetic-preview-*.mp3`에 저장합니다. 현재 실서비스 호출은 수행하지 않았습니다.

보호자 복제 음성의 API 계약은 [ElevenLabs IVC 생성](https://elevenlabs.io/docs/api-reference/voices/ivc/create)·[목록 검색](https://elevenlabs.io/docs/api-reference/voices/search)·[삭제](https://elevenlabs.io/docs/api-reference/voices/delete)를 기준으로 내부 **자가 음성**만 시험합니다. `ELEVENLABS_API_KEY`와 `VOICE_OWNER_CONSENT_RECORD_ID`를 설정한 뒤, 각 20~30초 PCM16 WAV 세 파일에 대해 `uv run python scripts/demo_voice_enrollment.py enroll <내음성1.wav> <내음성2.wav> <내음성3.wav> --own-voice --upload`를 명시적으로 실행해야 외부 전송·시험 clone 생성이 시작됩니다. 전송 전에 고유 시험 이름과 pending 상태를 Git에서 제외된 `runs/internal-test-voice.json`에 기록하고, 성공 시 voice ID와 검증 상태를 기록합니다. 원본 파일은 복사하지 않습니다. 응답이 끊기거나 시간 초과가 발생하면 재등록을 막고 pending 기록을 유지합니다. `uv run python scripts/demo_voice_enrollment.py reconcile`로 공급자 목록에서 같은 고유 이름의 시험 clone을 확인한 뒤, `uv run python scripts/demo_voice_enrollment.py delete --confirm-delete`로 **이 CLI가 만든 시험 clone만** 삭제할 수 있습니다. 등록·복구·삭제는 동일한 로컬 잠금을 사용합니다. ElevenLabs는 [IVC에 1~2분의 깨끗한 음성과 MP3 192kbps 이상](https://elevenlabs.io/docs/help-center/product/voices/voice-cloning/what-files-do-you-accept-for-voice-cloning)을 권장하므로, WAV 기반 절차의 품질·업로드 성공은 아직 실측되지 않았습니다. [Zero Retention Mode도 IVC 샘플에는 적용되지 않습니다](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode). 실제 보호자/환자 자료는 기관·동의·보관/삭제 계약이 정해지기 전까지 등록하지 않습니다.

현재 semantic RAG 모델·0.75 임계값은 [ADR-0009 제안](architecture/decisions/0009-provisional-synthetic-family-semantic-rag.md)의 합성 평가값이며 한국어 검색 정확도는 미측정입니다. 보호자 음성의 공급자 중립 상태·삭제 후조건은 [ADR-0010 제안](architecture/decisions/0010-guardian-voice-lifecycle-and-deletion-proof.md)에 정리했습니다. 시험 clone은 정확한 ID의 `DELETE status=ok`와 그 뒤의 완전한 목록 부재를 모두 확인한 경우에만 삭제 완료로 표시합니다. ID 미확인·DELETE 404·시간 초과·조회 불명확은 `deletion_pending`으로 유지합니다. 목록 부재는 공급자 내부 원본·백업 폐기 증명이 아닙니다.

보호자 웹의 **고정 합성 환자 자가 음성 시험**은 검증된 보호자 연결·별도 `guardian_voice_clone` 동의가 있어도 서버의 `KOF5_SYNTHETIC_GUARDIAN_VOICE_UPLOAD_ENABLED=1`과 시험 공급자 키를 명시적으로 설정하기 전에는 녹음·업로드가 열리지 않습니다. `GET /internal/synthetic/guardian/{patient_id}/voice/status`가 본인 Auth JWT로 준비 상태를 확인하며, `POST .../voice/enroll`은 20~30초 PCM16 WAV 세 개의 합성 시험 샘플만 받습니다. `pending`을 공급자 POST 전에 저장하고, 재시도는 같은 샘플을 다시 보내지 않습니다. `POST .../voice/{clone_id}/reconcile`은 불확실한 생성 이름을 대조하고, `POST .../voice/{clone_id}/delete`는 별도 목록 부재 확인 뒤에만 삭제 완료를 표시합니다. 로컬 DB·모의 API/웹 회귀만 통과했고 실제 업로드·삭제·iPad Web Audio·보호자 음성은 검증되지 않았습니다.

## 기존 전처리 도구

AI Hub 데이터셋 key와 선택 file key를 확인한 뒤 다운로드부터 24 kHz mono 16-bit FLAC 변환까지 실행할 수 있습니다.

```bash
cp -n .env.example .env
# .env의 AIHUB_APIKEY 값을 로컬에서만 입력
python3 scripts/run_preprocessing_pipeline.py \
  --dataset-key <DATASET_KEY> \
  --file-key <FILE_KEY> \
  --jobs 4
```

AI Hub 승인, macOS CLI 설치, 선택 다운로드와 변환 재실행 방법은 [전처리 가이드](docs/data-preprocessing.md)를 따릅니다.

## 안전 및 데이터 원칙

- 환자 식별정보, 실제 임상 음성, 동의서와 원본 연구 데이터는 Git에 커밋하지 않습니다.
- 생성 음성, 보호자 음성 샘플, 체크포인트와 실행 로그는 기본적으로 Git 밖의 산출물로 취급합니다.
- 환자에게 제공되는 문구와 동작은 임상 검토 및 승인 절차를 거친 뒤 사용합니다.
- 환자 시험 전 AI 음성 고지, 환자·보호자 동의, 병실 주변 음성 처리, 보조 알림의 확인·실패 경로를 확정합니다.
