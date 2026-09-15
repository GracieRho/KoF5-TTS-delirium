# KoF5-TTS-delirium

가족 음성과 환자·병원 맥락을 활용한 한국어 음성 대화·지남력 지원 MVP를 검증하는 프로젝트입니다.

> 현재 제품 방향은 클라우드 중심 MVP입니다. 실제 환자 대상 시험은 [안전·윤리 게이트](docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md)와 기관 검토를 완료한 뒤에만 진행하며, 이 시스템은 의료적 판단이나 기존 의료진 호출 수단을 대체하지 않습니다.

## 목표

- 환자가 버튼을 누르지 않고 먼저 말을 걸 수 있는 가족 음성 기반 대화를 검증합니다.
- 보호자 기억과 병원 승인 정보를 분리해 짧은 지남력·대화 응답에 사용합니다.
- 검증 대상은 한국어 명료도, 오작동, 응답 지연, 사실 보존 및 환자 안전입니다.

## 현재 범위

현재 저장소에는 [MVP PRD](docs/Delirium_Familiar_Voice_MVP_PRD.md), 환자 시험 전 안전 게이트, ADR 및 기존 AI Hub 다운로드·오디오 전처리 도구가 있습니다. MVP는 hosted STT·LLM·보호자 음성 복제 TTS를 연결하는 클라우드 중심 흐름을 목표로 합니다. 기존 학습·경량화 경로는 이번 MVP의 구현 범위가 아닙니다.

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
├── tests/                 # 단위·통합 테스트
├── .editorconfig          # 공통 편집기 설정
├── .gitignore             # 비밀정보, 데이터, 모델 산출물 제외 규칙
└── AGENTS.md              # 저장소에서 작업할 때의 기본 원칙
```

폴더별 역할은 [저장소 구조](docs/repository-layout.md), 문서와 협업 규칙은 [docs/README.md](docs/README.md)와 [docs/contributing.md](docs/contributing.md), 제품 구조와 정책 변경은 [아키텍처](architecture/README.md)와 [ADR 목록](architecture/decisions/README.md)에서 확인할 수 있습니다. 병원 환자 등록·화자 특징의 최소 컬럼은 [병원 등록 설계](docs/delirium-familiar-voice/08-hospital-patient-registry-and-voice.md)에 정리했습니다.

iPad의 기기 내 발화 후보 감지 코드는 [환자 앱 내부 시험](apps/patient_ipad/README.md)에 있습니다. 아직 오디오는 기기 밖으로 보내지 않습니다.

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

내부 오디오 API `POST /internal/synthetic/audio`는 `KOF5_INTERNAL_DEMO_TOKEN`(32자 이상), 공급자 키·voice ID, `VOICE_OWNER_CONSENT_RECORD_ID`가 서버에 설정된 경우에만 열립니다. 요청에는 `X-Internal-Demo-Token`, `X-Synthetic-Material: confirmed`, `Content-Type: audio/wav`가 필요하며, PCM16 WAV 원문(2 MB 이하·30초 이하)을 전송합니다. 응답은 전사·짧은 답·MP3의 base64입니다. 이 확인은 내부 시험자의 선언이며 실제 동의 검증이나 환자 인증이 아닙니다. 오디오는 메모리에서만 처리하고 앱 DB에 저장하지 않습니다. 실제 환자 오디오를 보내지 마세요.

루트 `app.py`와 `vercel.json`은 [Vercel FastAPI 진입점](https://vercel.com/docs/frameworks/backend/fastapi) 및 Python 함수 번들 제외 설정입니다. 이 설정은 **합성 텍스트 API의 배포 준비**만 뜻합니다. 현재 메모리 세션은 함수 인스턴스 간 공유·영속화되지 않으므로 실제 환자 서비스나 다중 인스턴스 대화에 사용할 수 없고, Vercel 배포도 아직 실행하지 않았습니다.

별도 `cloud_prototype.py`에는 Phase 0용 배치 WAV→STT→LLM→MP3 호출을 합성 데이터 기준으로 구현했습니다. Deepgram Nova-3, OpenAI Responses, ElevenLabs IVC는 현재 **비교 후보**이고, 공급업체 선정과 실제 서비스 검증은 남아 있습니다. [Deepgram MIP 제외](https://developers.deepgram.com/docs/the-deepgram-model-improvement-partnership-program)와 [OpenAI `store=false`](https://developers.openai.com/api/docs/guides/your-data)를 요청에 적용하지만, [ElevenLabs 복제 음성 샘플은 Zero Retention 적용 대상이 아니므로](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode) 실제 보호자 샘플 등록은 동의·보존·삭제 계약을 확인하기 전까지 진행하지 않습니다. 테스트는 네트워크 없이 모의 응답만 사용합니다.

후보 API를 실제 합성 자료로 시험할 때는 세 API key, `ELEVENLABS_VOICE_ID`, `VOICE_OWNER_CONSENT_RECORD_ID`를 로컬 환경 변수에 설정하고 `uv run python scripts/demo_cloud_pipeline.py <합성 WAV> --synthetic-only`를 실행합니다. 동의 기록 ID 입력은 **내부 시험자의 확인 표시**일 뿐 실제 환자 시험의 승인·동의 절차가 아닙니다. Deepgram에는 WAV, OpenAI에는 전사 문장과 합성 사실, ElevenLabs에는 응답 문장과 시험용 voice ID가 전달됩니다. 결과 MP3는 Git에서 제외된 `runs/synthetic-preview-*.mp3`에 저장합니다. 현재 실서비스 호출은 수행하지 않았습니다.

보호자 복제 음성의 API 계약은 [ElevenLabs IVC 생성](https://elevenlabs.io/docs/api-reference/voices/ivc/create)·[목록 검색](https://elevenlabs.io/docs/api-reference/voices/search)·[삭제](https://elevenlabs.io/docs/api-reference/voices/delete)를 기준으로 내부 **자가 음성**만 시험합니다. `ELEVENLABS_API_KEY`와 `VOICE_OWNER_CONSENT_RECORD_ID`를 설정한 뒤, 각 20~30초 PCM16 WAV 세 파일에 대해 `uv run python scripts/demo_voice_enrollment.py enroll <내음성1.wav> <내음성2.wav> <내음성3.wav> --own-voice --upload`를 명시적으로 실행해야 외부 전송·시험 clone 생성이 시작됩니다. 전송 전에 고유 시험 이름과 pending 상태를 Git에서 제외된 `runs/internal-test-voice.json`에 기록하고, 성공 시 voice ID와 검증 상태를 기록합니다. 원본 파일은 복사하지 않습니다. 응답이 끊기거나 시간 초과가 발생하면 재등록을 막고 pending 기록을 유지합니다. `uv run python scripts/demo_voice_enrollment.py reconcile`로 공급자 목록에서 같은 고유 이름의 시험 clone을 확인한 뒤, `uv run python scripts/demo_voice_enrollment.py delete --confirm-delete`로 **이 CLI가 만든 시험 clone만** 삭제할 수 있습니다. 등록·복구·삭제는 동일한 로컬 잠금을 사용합니다. ElevenLabs는 [IVC에 1~2분의 깨끗한 음성과 MP3 192kbps 이상](https://elevenlabs.io/docs/help-center/product/voices/voice-cloning/what-files-do-you-accept-for-voice-cloning)을 권장하므로, WAV 기반 절차의 품질·업로드 성공은 아직 실측되지 않았습니다. [Zero Retention Mode도 IVC 샘플에는 적용되지 않습니다](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode). 실제 보호자/환자 자료는 기관·동의·보관/삭제 계약이 정해지기 전까지 등록하지 않습니다.

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
