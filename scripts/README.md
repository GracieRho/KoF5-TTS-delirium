# Scripts

전처리, 학습, 평가, 내보내기 명령의 얇은 실행 진입점을 둡니다. 재사용 가능한 로직은 `src/kof5_tts/`에 구현합니다.

현재 제공하는 저장소 도구:

- `generate_architecture.py`: 코드·설정·파이프라인 구조를 `architecture/generated/`에 생성
- `test_generate_architecture.py`: 생성기의 기본 동작과 결정성 검증

```bash
python3 scripts/generate_architecture.py
python3 scripts/generate_architecture.py --check
python3 -m unittest scripts/test_generate_architecture.py
```
