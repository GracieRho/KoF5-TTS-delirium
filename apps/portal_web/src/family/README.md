# 가족·보호자 화면

- `guardian/`: 로그인과 권한 검증을 거치는 보호자 포털(`/guardian`).
- `studio/`: 가족 소개·목소리 등록·기억·대화(`/studio`).
- `components/VoiceWave.tsx`, `styles/motion.css`: 가족 환영 영역의 장식 파형과 모션 제어. 음성 입출력 상태와는 연결하지 않는다.
- 병원 직원 업무나 병원 팔레트는 `../hospital/`에 둔다. 공용 인증·API 타입·셸·폼·시트는 `../shared/`에서 가져온다.

전체 규격은 루트 `DESIGN.md`를 따른다. URL이나 백엔드 API는 소스 폴더 이동으로 변경하지 않는다.
