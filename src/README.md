# Source Code

재사용 가능한 로직은 `src/kof5_tts/` 아래에서 역할별로 분리합니다. 현재 `preprocessing/`에는 기존 AI Hub CLI 호출과 WAV→24 kHz mono 16-bit FLAC 변환 로직이 있습니다. 제품 초안은 Vercel FastAPI 진입점, 합성 대화 화면과 Supabase Auth/Data API를 쓰는 보호자 웹 화면을 포함합니다. 호스팅 STT/TTS 공급업체와 실서비스 구조는 아직 실측·선정 전입니다.
