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
- 태블릿 플랫폼, 배포 인프라 및 네트워크 장애 시 동작
- 병실 주변 음성의 전송·보관 범위, 동의·철회 절차
- 실제 환자 대상 시험 계획과 임상 콘텐츠 승인

## 저장소 구조

```text
.
├── architecture/          # 시스템 구조, 기술 결정 기록
│   └── decisions/         # ADR(Architecture Decision Record)
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

폴더별 역할은 [저장소 구조](docs/repository-layout.md), 문서와 협업 규칙은 [docs/README.md](docs/README.md)와 [docs/contributing.md](docs/contributing.md), 제품 구조와 정책 변경은 [아키텍처](architecture/README.md)와 [ADR-0001](architecture/decisions/0001-cloud-first-familiar-voice-mvp.md)에서 확인할 수 있습니다.

## 합성 대화 흐름 확인

```bash
python3 scripts/demo_companion_text.py
```

PRD의 첫 상호작용을 합성 발화·기억으로 검사합니다. 현재 데모에는 마이크, STT, LLM, 음성 복제 및 실제 환자 데이터가 연결되지 않았습니다.

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
