# 저장소 구조와 팀 작업 흐름

아래 데이터·체크포인트 경로는 기존 연구·전처리 도구의 책임 경계입니다. 현재 [클라우드 중심 MVP](Delirium_Familiar_Voice_MVP_PRD.md)는 학습·경량화 경로를 필수 단계로 사용하지 않습니다. 제품 코드의 새 폴더는 실제 구현 시 역할이 정해진 뒤 추가합니다.

## 기존 연구용 구조

```text
.
├── data/
│   ├── raw/aihub/               # AI Hub key별 다운로드 원본
│   ├── raw/wav/                 # 전달받은 원본 WAV
│   ├── interim/flac/            # WAV에서 무손실 변환한 FLAC
│   └── processed/
│       ├── audio/               # 분할·정규화 등을 마친 학습 입력
│       └── manifests/           # 학습용 메타데이터와 데이터 목록
├── checkpoints/
│   ├── pretrained/              # 변경하지 않은 기준 모델
│   ├── finetuned/               # 파인튜닝 결과
│   └── optimized/
│       ├── pruned/               # 프루닝 결과
│       └── quantized/            # 양자화 결과
├── configs/
│   ├── preprocessing/           # 변환·분할·정규화 설정
│   ├── finetuning/              # 학습 모델과 하이퍼파라미터
│   ├── optimization/            # 프루닝·양자화 설정
│   └── inference/               # 추론·생성 설정
├── src/kof5_tts/
│   ├── preprocessing/           # 재사용 가능한 데이터 처리 코드
│   ├── training/                # 파인튜닝 코드
│   ├── inference/               # TTS 추론 코드
│   ├── optimization/            # 경량화·변환 코드
│   └── evaluation/              # 음질·성능 평가 코드
├── scripts/                     # 얇은 실행 진입점
├── apps/
│   ├── patient_ipad/            # 환자 병상 Flutter 앱과 별도 진단 target
│   └── portal_web/              # 보호자·병원 Vite/React 반응형 포털
├── tests/
│   ├── unit/
│   └── integration/
├── runs/                        # 실험별 로그와 임시 출력(Git 제외)
├── docs/                        # 요구사항·평가·실험 요약
└── architecture/                # 구조와 기술 결정 기록
```

## 기존 전처리·학습 데이터 흐름

1. AI Hub 원본은 `data/raw/aihub/<dataset-key>/`, 별도 원본 WAV는 `data/raw/wav/`에 두고 수정하지 않습니다.
2. WAV→24 kHz mono 16-bit FLAC 변환 결과는 `data/interim/flac/`에 저장합니다.
3. 파인튜닝에 추가 분할·정규화가 필요하면 결과를 `data/processed/audio/`에 저장합니다.
4. 오디오 경로, 텍스트, 화자 등 학습 입력 목록은 `data/processed/manifests/`에 저장합니다.
5. 별도 연구에서 파인튜닝을 재개할 경우에만 설정은 `configs/finetuning/`, 결과는 `checkpoints/finetuned/`에 둡니다.

`data/`, `checkpoints/`, `runs/`의 실제 파일은 기본적으로 Git에서 제외됩니다. 체크포인트 중 기준선이나 배포 후보처럼 재현·비교에 유의미하고 팀 검토를 마친 결과만 예외적으로 추적합니다. 상세 선정 기준은 [`checkpoints/README.md`](../checkpoints/README.md)를 따릅니다. 환자 관련 원본이나 메타데이터는 비식별화·접근통제 절차가 확정되기 전까지 공유 저장소에 올리지 않습니다.

## 코드와 설정 원칙

- 재사용 가능한 로직은 `src/kof5_tts/`에 두고 `scripts/`에는 인자 처리와 호출만 둡니다.
- 실험 조건은 코드에 하드코딩하지 않고 `configs/`의 설정 파일로 관리합니다.
- 한 실험은 사용한 설정, 코드 커밋, 데이터 버전, 기준 체크포인트를 식별할 수 있어야 합니다.
- `runs/`는 실행 중 출력, `checkpoints/`는 모델 가중치, `docs/`는 사람이 읽는 결과 요약을 보관합니다.
- 코드나 설정 구조를 바꾼 뒤에는 `python3 scripts/generate_architecture.py`를 실행해 자동 아키텍처 문서를 갱신합니다.

## MVP 제품 작업 경계

- `apps/patient_ipad/`: Flutter iPad 클라이언트. `lib/main.dart`는 시간·날짜·병원 장소/일정과 수동적 음성 상태만 보여주는 비조작형 환자 화면입니다. API 주소, publishable key, 내부 토큰, 로그와 시험 제어는 표시하지 않습니다. `lib/main_debug.dart`는 숨은 제스처나 라우트가 아닌 별도 Flutter target이며 내부 진단에만 사용합니다. 후보 발화 처리와 실제 환자 시험의 안전 경계는 기존 합성 시험 제한을 유지합니다.
- `apps/portal_web/`: 보호자 `/guardian`와 병원 직원 `/hospital` 화면을 함께 제공하는 Vite 기반 React/TypeScript 반응형 웹입니다. 소스는 역할별 페이지·기능·공통 컴포넌트로 나누고, `dist/`는 생성된 빌드 출력이므로 소스 책임 경계가 아닙니다.
- `supabase/`: Auth/Postgres의 로컬 마이그레이션과 합성 권한 검사. 환자·입원·동의·음성 메타데이터, 가족 기억, 병원 승인 사실·메시지·안전 감사 초안은 비공개 `kof5` 스키마에 두고, 검증된 직원·보호자 범위의 조회, 보호자 기억 등록·수정·문자열 검색, 승인 게이트를 통과한 등록자만 환자 기본정보 입력을 호출자 RLS `api` 경로로 노출합니다. 작업 전용 로컬 Auth/Data API의 합성 권한 시험은 통과했지만, 전용 원격 프로젝트·실제 기관 승인/메시지 전달·환자 자료·음성 저장소·감사 기록 업무 흐름은 연결하지 않았습니다.
- 환자 음성 인터랙션: 임시 버퍼, 발화 활성화, 대화 상태, 재생과 중단
- 대화·정보 경계: 보호자 기억, 병원 승인 정보, 짧은 응답과 메시지 원문 보존
- 보호자·병원 입력: 동의된 음성 등록, 정보 수정, 병원 메시지와 일정
- 안전·평가: 환자 화면에서 AI 정체성 표시는 제거하되 이 방향과 Gate 07 Identity 요구의 충돌을 미완료 상태로 유지하고, 환자 거부, 주변 음성 처리, 보조 알림과 기능 지표를 검증합니다.

기존 AI Hub 전처리 담당은 `src/kof5_tts/preprocessing/`과 `scripts/download_aihub.py`, `scripts/run_preprocessing_pipeline.py`를 유지합니다. 이는 현재 제품 MVP와 별도의 연구 도구입니다.

역할은 파일 소유권이 아니라 충돌을 줄이기 위한 기본 경계이며, 공통 인터페이스 변경은 ADR이나 문서에서 먼저 합의합니다.
