# Scripts

저장소 도구와 제품 실험 명령의 얇은 실행 진입점을 둡니다. 재사용 가능한 로직은 `src/kof5_tts/`에 구현합니다. 현재 전처리 명령은 기존 연구 도구이며 클라우드 중심 MVP의 필수 실행 단계가 아닙니다.

현재 제공하는 저장소 도구:

- `demo_companion_text.py`: 합성 사실·발화로 PRD의 첫 대화 흐름을 확인(오디오·클라우드 호출 없음)
- `run_backend.py`: `127.0.0.1`에서 합성 환자 전용 텍스트 API를 실행
- `generate_architecture.py`: 코드·설정 목록과 MVP 목표 흐름을 `architecture/generated/`에 생성
- `test_generate_architecture.py`: 생성기의 기본 동작과 결정성 검증
- `download_aihub.py`: AI Hub 데이터셋·파일 목록 조회 및 승인 데이터 다운로드
- `convert_wav_to_flac.py`: WAV 트리를 24 kHz mono 16-bit FLAC으로 변환·검증
- `run_preprocessing_pipeline.py`: AI Hub 다운로드와 FLAC 변환을 한 번에 실행

```bash
python3 scripts/generate_architecture.py
python3 scripts/generate_architecture.py --check
python3 -m unittest scripts/test_generate_architecture.py
```

전처리 명령과 API key 보관 방법은 [`docs/data-preprocessing.md`](../docs/data-preprocessing.md)를 따릅니다.
