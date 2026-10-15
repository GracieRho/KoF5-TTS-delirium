# Favilium 브랜드 자산

2026-10-15 사용자가 승인한 2번 대화 고리 심볼과 소문자 워드마크를 웹에 적용했다.

## 원본과 벡터

- `symbol-reference.png`: 사용자가 첨부한 심볼 크롭. 외곽선과 중앙 V의 형태를 Bézier 곡선으로 정리하고, 겹치는 리본은 원본을 참고해 4색 그라데이션으로 재구성했다. 래스터 질감·명암의 픽셀 단위 복제는 아니다.
- `wordmark-reference.png`: 사용자가 첨부한 영문명 크롭. 어두운 글자 영역의 외곽선과 내부 공간을 추출해 path로 변환했다. 배경은 제거했으며 폰트 설치에 의존하지 않는다.
- 실제 자산: `apps/portal_web/src/shared/assets/brand/`의 `favilium-symbol.svg`, `favilium-wordmark.svg`, 정사각 여백의 `favilium-icon.svg`.
- 앱 아이콘: 동일 SVG에서 렌더링한 `favilium-touch-icon.png`(180px), `favilium-app-icon.png`(512px). 바탕은 `#FAFBF6`이다.
- SVG에는 외부 참조, 내장 래스터, 스크립트가 없다. 워드마크는 `#283025`, 심볼은 `#6CA651`, `#BBCB2E`, `#839705`, `#6B7445`와 접힌 부분의 어두운 올리브를 사용한다.

## 적용·검증

- 공용 AppHeader를 통해 `/studio`, `/guardian`, `/hospital`에 동일하게 적용한다. 링크의 접근 가능한 이름은 `Favilium` 하나다.
- 웹 제목·공용 각주·파비콘·Apple touch icon을 함께 변경했다. Flutter 앱 패키지는 이번 작업 범위가 아니다.
- `npm run check --prefix apps/portal_web`: 웹 29개 테스트와 TypeScript/Vite 빌드 통과.
- 실제 `http://127.0.0.1:8766/studio`의 1280px 데스크톱, 390px 모바일을 확인했다. 이미지 로딩 성공, 390px 가로 넘침 없음. `desktop.png`, `mobile.png`가 해당 화면이다.
- 사용자 승인은 시각 방향에 대한 승인이다. 상표 등록·유사성 검토를 완료했다는 의미는 아니다.
