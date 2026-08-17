# 저장소 구조와 팀 작업 흐름

## 권장 구조

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
├── tests/
│   ├── unit/
│   └── integration/
├── runs/                        # 실험별 로그와 임시 출력(Git 제외)
├── docs/                        # 요구사항·평가·실험 요약
└── architecture/                # 구조와 기술 결정 기록
```

## 데이터 전달 흐름

1. AI Hub 원본은 `data/raw/aihub/<dataset-key>/`, 별도 원본 WAV는 `data/raw/wav/`에 두고 수정하지 않습니다.
2. WAV→24 kHz mono 16-bit FLAC 변환 결과는 `data/interim/flac/`에 저장합니다.
3. 파인튜닝에 추가 분할·정규화가 필요하면 결과를 `data/processed/audio/`에 저장합니다.
4. 오디오 경로, 텍스트, 화자 등 학습 입력 목록은 `data/processed/manifests/`에 저장합니다.
5. 파인튜닝 설정은 `configs/finetuning/`, 결과 체크포인트는 `checkpoints/finetuned/`에 둡니다.

`data/`, `checkpoints/`, `runs/`의 실제 파일은 기본적으로 Git에서 제외됩니다. 체크포인트 중 기준선이나 배포 후보처럼 재현·비교에 유의미하고 팀 검토를 마친 결과만 예외적으로 추적합니다. 상세 선정 기준은 [`checkpoints/README.md`](../checkpoints/README.md)를 따릅니다. 환자 관련 원본이나 메타데이터는 비식별화·접근통제 절차가 확정되기 전까지 공유 저장소에 올리지 않습니다.

## 코드와 설정 원칙

- 재사용 가능한 로직은 `src/kof5_tts/`에 두고 `scripts/`에는 인자 처리와 호출만 둡니다.
- 실험 조건은 코드에 하드코딩하지 않고 `configs/`의 설정 파일로 관리합니다.
- 한 실험은 사용한 설정, 코드 커밋, 데이터 버전, 기준 체크포인트를 식별할 수 있어야 합니다.
- `runs/`는 실행 중 출력, `checkpoints/`는 모델 가중치, `docs/`는 사람이 읽는 결과 요약을 보관합니다.
- 코드나 설정 구조를 바꾼 뒤에는 `python3 scripts/generate_architecture.py`를 실행해 자동 아키텍처 문서를 갱신합니다.

## 팀 작업 경계

- 전처리 담당: `src/kof5_tts/preprocessing/`, `scripts/download_aihub.py`, `scripts/run_preprocessing_pipeline.py`, `data/raw/` → `data/interim/`
- 파인튜닝 담당: `src/kof5_tts/training/`, `configs/finetuning/`, `data/processed/` → `checkpoints/finetuned/`
- 경량화 담당: `src/kof5_tts/optimization/`, `configs/optimization/`, `checkpoints/finetuned/` → `checkpoints/optimized/`
- 평가 담당: `src/kof5_tts/evaluation/`, 평가 설정과 `docs/`의 결과 요약

역할은 파일 소유권이 아니라 충돌을 줄이기 위한 기본 경계이며, 공통 인터페이스 변경은 ADR이나 문서에서 먼저 합의합니다.
