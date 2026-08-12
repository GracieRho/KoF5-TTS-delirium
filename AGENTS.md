# Repository Guidelines

## Project Context

- 이 프로젝트는 섬망 환자의 비약물적 중재를 지원하는 한국어 TTS 프로젝트다.
- 문서와 사용자에게 노출되는 기본 언어는 한국어로 작성한다.
- 현재는 초기 단계이므로 모델, 프레임워크, 하드웨어를 근거 없이 확정하지 않는다.

## Repository Workflow

- 폴더별 역할과 팀 인계 흐름은 `docs/repository-layout.md`를 먼저 따른다.
- `main` 직접 작업은 사용자가 명시적으로 긴급 핫픽스를 요청한 경우에만 허용한다. 일반 기능, 실험, 문서와 설정 작업은 예외 없이 최신 `origin/main`에서 작업별 브랜치와 `.worktrees/<task-slug>/` 워크트리를 만들고 그 안에서 진행한다.
- 브랜치는 `feat/`, `fix/`, `docs/`, `chore/`, `experiment/` 중 작업 성격에 맞는 접두사를 사용한다.
- 작업이 끝나면 검증 결과와 데이터·체크포인트 영향을 PR에 기록하고, 리뷰 승인을 받은 뒤 병합한다.
- PR 리뷰 대화를 모두 해결하고 생성된 아키텍처 문서가 최신인지 확인한다. 기본 병합 방식은 squash merge를 권장한다.
- PR이 병합되면 `.github/workflows/delete-merged-branch.yml`이 동일 저장소의 원격 작업 브랜치를 자동 삭제한다. 로컬 워크트리와 브랜치는 상태를 확인한 뒤 별도로 정리한다.
- 원본 WAV는 `data/raw/wav/`, 변환한 FLAC는 `data/interim/flac/`, 학습 입력은 `data/processed/`에 둔다.
- 재사용 코드는 `src/kof5_tts/`, 실행 진입점은 `scripts/`, 실험 설정은 `configs/`에 둔다.
- 파인튜닝 결과는 `checkpoints/finetuned/`, 프루닝·양자화 결과는 `checkpoints/optimized/`에 둔다.
- 데이터, 실행 로그와 체크포인트는 기본적으로 Git에서 제외한다. 체크포인트는 `checkpoints/README.md`의 기준을 만족하는 유의미한 결과만 팀 리뷰 후 예외적으로 추적하며, 체크포인트 디렉터리 전체를 강제 추가하지 않는다.

## Safety and Data

- 환자 식별정보, 실제 임상 음성, 비공개 연구 데이터, 인증정보를 저장소에 커밋하지 않는다.
- 임상 문구나 환자 대상 동작을 변경할 때는 안전상 영향과 임상 검토 필요 여부를 명시한다.
- 생성 음성, 모델 체크포인트, 실험 로그, 변환 모델은 기본적으로 산출물로 취급한다.

## Model Optimization

- 경량화 전 기준 모델의 품질과 성능을 먼저 측정한다.
- 양자화나 디코딩 레이어 프루닝은 크기, 지연 시간, 메모리뿐 아니라 한국어 명료도와 핵심 메시지 보존을 함께 비교한다.
- 기기별 최적화는 목표 하드웨어와 런타임이 확정된 뒤 결정 기록(ADR)으로 남긴다.

## Changes

- 기존 문서 구조와 프로젝트 용어를 우선 재사용한다.
- 변경 범위에 맞는 가장 작은 검증부터 실행하고, 검증하지 못한 항목은 명확히 밝힌다.
- `src/`, `configs/`, `scripts/` 구조가 바뀌면 `python3 scripts/generate_architecture.py`를 실행하고 생성 파일을 함께 반영한다.
- 완료 전 `python3 scripts/generate_architecture.py --check`, `python3 -m unittest scripts/test_generate_architecture.py`, `git diff --check`를 실행한다.
