# 가족 파형 모션·병원 테마 검증

검증일: 2026-10-15. 작업 브랜치: `feat/guardian-voice-mvp`.

## 변경

- 기존 `src/guardian/`, `src/studio/`를 `src/family/` 아래로 이동하고 상대 import와 테스트 경로를 함께 갱신했다. URL, API, 인증 방식은 변경하지 않았다.
- `family/components/VoiceWave`가 가족 환영 화면의 7개 파형 막대와 멈춤/재생을 관리한다. CSS transform만 사용하는 4.8초 순환 모션이며 마이크·실제 음성 출력과 무관한 장식이다. `prefers-reduced-motion: reduce`에서는 정적으로 표시한다.
- 병원 전용 `hospital/styles/hospital.css`와 청록색 심볼·파비콘을 추가했다. 지정 팔레트 `#2F39A9`, `#2E6FA0`, `#49A4BB`, `#15D8B3`를 사용하고 공용 워드마크·셸·폼·시트를 재사용했다.
- 로그인 전 업무 소개와 로그인 후 기존 담당 환자·승인 정보·메시지·기기 기능을 유지했다. 연결되지 않은 로그인을 활성화하거나 환자 자료를 임의로 넣지 않았다.

## 확인

- `npm run check --prefix apps/portal_web`: 19개 파일, 32개 테스트 및 TypeScript/Vite 빌드 통과.
- 추가 회귀: 파형 멈춤/재생 전환, 병원 미연결 로그인 비활성, 테스트 세션에서 담당 환자 선택과 전체 전달 대기 전환.
- `python3 scripts/generate_architecture.py --check`, `python3 -m unittest scripts/test_generate_architecture.py`: 최신 구조 확인, 7개 테스트 통과.
- `git diff --check`: 통과.
- 네이티브 브라우저 `http://127.0.0.1:8766`: 가족·병원 1280px 데스크톱 및 390px 모바일 확인. 두 화면 모두 모바일 document width 390px로 가로 넘침 없음. 병원 심볼 정상 로딩, 계산된 주 색상 `#2f39a9`, 제목 `Favilium · 병원` 확인.
- 가족 파형의 각 막대에서 `family-voice-wave`와 서로 다른 transform을 확인했고, 멈춤 버튼 클릭 시 7개 막대 모두 `animation-play-state: paused`, 다시 재생 시 제어 상태가 복구되는 것을 확인했다.
- 스크린샷: `family-desktop.png`, `family-mobile.png`, `hospital-desktop.png`, `hospital-mobile.png`.

## 미검증

- 실제 원격 Supabase 직원 계정, 병원 데이터·음성 공급자 연결, Vercel 배포는 검증하지 않았다. 로그인 후 회귀는 로컬 테스트용 세션/자료를 사용했다.
- 운영체제의 동작 줄이기 설정을 직접 전환하지는 않았다. CSS의 정적 대체 규칙을 구현했으며 기본 모션과 수동 멈춤은 실제 브라우저에서 확인했다.
- 환자 iPad의 화면·모션·임상 사용 범위는 변경하지 않았다. 색상·장식 모션 변경은 임상 효능이나 환자 시험 승인을 의미하지 않는다.
