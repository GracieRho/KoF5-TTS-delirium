# Claude Project Instructions

이 저장소에서 작업할 때는 [`AGENTS.md`](AGENTS.md)를 기본 작업 규칙으로 사용합니다.

사용자가 명시적으로 요청한 긴급 핫픽스만 `main` 직접 작업을 허용합니다. 그 외 모든 변경은 최신 `origin/main`에서 만든 작업별 브랜치와 `.worktrees/<task-slug>/` 워크트리에서 진행하고, 검증 결과를 포함한 PR을 만든 뒤 리뷰를 거쳐 병합합니다. 병합된 동일 저장소의 원격 작업 브랜치는 GitHub Actions가 자동 삭제합니다. 자세한 순서는 [`docs/contributing.md`](docs/contributing.md)를 따릅니다.

## 빠른 경로 안내

- WAV 원본: `data/raw/wav/`
- 변환한 FLAC: `data/interim/flac/`
- 파인튜닝 입력과 manifest: `data/processed/`
- 전처리·학습·추론·최적화 코드: `src/kof5_tts/`
- 재현 가능한 실험 설정: `configs/`
- 파인튜닝 체크포인트: `checkpoints/finetuned/`
- 프루닝·양자화 결과: `checkpoints/optimized/`

실제 데이터, 로그와 체크포인트는 기본적으로 Git에 올리지 않습니다. 체크포인트는 [`checkpoints/README.md`](checkpoints/README.md)의 선정 기준을 충족한 기준선·검증 완료 결과·배포 후보처럼 유의미한 파일만 팀 검토 후 예외적으로 추적합니다.

## 변경 후 실행

```bash
python3 scripts/generate_architecture.py
python3 scripts/generate_architecture.py --check
python3 -m unittest scripts/test_generate_architecture.py
git diff --check
```

자동 생성 결과는 `architecture/generated/`에 저장합니다. 해당 파일을 직접 편집하지 말고 코드, 설정 또는 `scripts/generate_architecture.py`를 수정한 뒤 다시 생성합니다.

임상 문구와 실제 환자 데이터에는 `AGENTS.md`의 안전·데이터 원칙을 적용합니다. 상세 폴더 구조와 인계 방식은 [`docs/repository-layout.md`](docs/repository-layout.md)를 참고합니다.
