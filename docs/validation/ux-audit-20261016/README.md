# Favilium 기능·UX 감사

2026-10-16 · GPT-6 Astra high · 기준 HEAD `fb28d0c`

**판정: REJECT — 전체 업무 흐름 재작업 필요.** P1 4건, P2 4건.

- [검토 보고서와 수정 우선순위](ASTRA-REVIEW.ko.md)
- [24개 화면 갤러리](INDEX.html)
- [캡처 목록](SCREENSHOTS.json)
- [실제 UI 재현](REPRODUCTION.ko.md)
- [모바일 실제 크기 확인](VIEWPORTS.json)

병원 최상위 4개 메뉴, 환자 상세 5개 탭, 보호자 5개 탭, 주요 입력 시트와 모바일 보완 화면을 촬영했다. 24개 상태에 viewport/전체 길이 이미지 각 1개와 접근성 트리를 남겼다. 이미지 파일은 native browser screenshot 원본이며 확장자는 기존 캡처 규칙을 따랐다.

검토용 임시 병원 탭은 닫고 viewport override를 복원했다. 기존 두 탭과 가상 자료는 보존했다. 이번 작업에서는 앱 구현을 수정하지 않았다.

증거 목록 24개/파일 72개 존재 검사, architecture check·생성기 7개 테스트, diff 공백 검사를 통과했다. 프론트 테스트는 구현 변경이 없어 재실행하지 않았다. 실제 공급자·환자 기기·장애 주입은 이번 검토에 포함하지 않았다.
