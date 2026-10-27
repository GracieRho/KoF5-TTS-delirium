# Scripts

저장소 도구와 제품 실험 명령의 얇은 실행 진입점을 둡니다. 재사용 가능한 로직은 `src/kof5_tts/`에 구현합니다. 현재 전처리 명령은 기존 연구 도구이며 클라우드 중심 MVP의 필수 실행 단계가 아닙니다.

현재 제공하는 저장소 도구:

- `run_research.py`: 명시적 opt-in과 loopback에서 가상 개인화 연구 화면을 실행. 공급자·로그인 없이 사용
- `benchmark_research.py`: 고정/무작위/적응형 질문·근거 처리 비교와 JSON/CSV/HTML 보고서, 외부 수동 주석 결과의 오프라인 채점
- `prepare_research_study.py`: 균형 배정표·빈 주석 양식·명시적 합성 예시 생성
- `analyze_research_study.py`: 참여자 단위 대응 분석, 블라인드 선호, 음성 2×2 대비, 첫 청취음·핵심정보 오류 집계
- `demo_companion_text.py`: 합성 사실·발화로 PRD의 첫 대화 흐름을 확인(오디오·클라우드 호출 없음)
- `run_backend.py`: `127.0.0.1`에서 합성 환자 전용 텍스트 API를 실행
- `demo_cloud_pipeline.py`: 합성 WAV와 동의된 시험용 voice ID로 후보 WAV 준비→첫 TTS 바이트 수신 및 hosted API 응답 완료를 단조 시계로 따로 측정합니다(MP3는 Git 제외 `runs/`에 저장). 실제 공급업체 호출만 실측이며 로컬 mock 검사는 계측 경로 검증일 뿐 지연 KPI가 아닙니다. iPad 발화 종료·재생 시작을 포함하지 않으므로 PRD의 첫 **청취** 오디오 3초 목표를 이 CLI만으로 판정하지 않습니다.
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

연구 도구의 실행·해석·비용 경계는 [`docs/research/README.md`](../docs/research/README.md), 실제 참여자 자료 수집 전에 필요한 절차는 [`실험 프로토콜`](../docs/research/experiment-protocol.md)을 따릅니다. 도구 준비와 합성 검증은 참여자 수집·치료 효과의 검증을 뜻하지 않습니다.
