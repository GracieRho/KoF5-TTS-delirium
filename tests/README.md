# Tests

- `unit/`: 외부 데이터나 모델 없이 실행 가능한 단위 테스트
- `integration/`: 작은 비식별 테스트 픽스처를 이용한 파이프라인 통합 테스트

실제 환자 데이터나 대형 모델을 테스트 픽스처로 커밋하지 않습니다.

AI Hub 테스트는 가짜 로컬 CLI와 가짜 API key만 사용합니다. 오디오 통합 테스트는 표준 라이브러리로 짧은 합성 WAV를 임시 생성하고 설치된 `ffmpeg`/`ffprobe`로 출력 규격을 검증합니다.

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```
