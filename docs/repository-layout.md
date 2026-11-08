# 임상 연구용 브랜치 구조

- `app.py`는 Vercel과 로컬 서버가 공통으로 사용하는 ASGI 진입점입니다.
- `apps/portal_web/`은 연구자 접속, 보호자 녹음, 목소리 등록과 한국어 합성·재생을 담당합니다.
- `src/kof5_tts/voice_only.py`는 인증, 원본 WAV 검증 및 ElevenLabs 요청을 처리합니다.
- `src/kof5_tts/voice_store.py`, `clinical/voice_sessions.sql`은 복제 상태만 저장합니다.
- `tests/`의 공급자 모의 테스트는 실제 참여자의 자료나 ElevenLabs 크레딧을 사용하지 않습니다.
- `scripts/`에는 로컬 서버 실행과 구조도 생성 스크립트가 있습니다.

다음 변경도 이 전용 브랜치의 최신 커밋에서 파생시킵니다. 전체 서비스·연구 코드와 10월 자료는 [원본 브랜치](https://github.com/GracieRho/KoF5-TTS-delirium/tree/main)에 있습니다.
