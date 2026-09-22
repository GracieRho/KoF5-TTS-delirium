# Familiar Voice 표면 디자인

루트 [`DESIGN.md`](../../DESIGN.md)가 제품·안전 계약의 최종 기준이고, 이 문서는 구현용 시각 규칙만 좁혀 기록한다.

## 단일 레퍼런스

- Mobbin app: [Acctual Web](https://mobbin.com/apps/acctual-web-061f9247-bc8e-4bcc-9d21-deb0aa2b2cf8/4b3f6020-01ec-4e1e-9916-98976ddf3efb/screens)
- Highlight screens:
  - [`99b2fcf7-a4e2-4b55-bb7d-642dcf1bd6a4`](https://mobbin.com/screens/99b2fcf7-a4e2-4b55-bb7d-642dcf1bd6a4)
  - [`64fc965a-d486-4181-9129-e61ca5cf176b`](https://mobbin.com/screens/64fc965a-d486-4181-9129-e61ca5cf176b)
  - [`4d45d9bc-2fa2-44a3-9e67-c476bbc9b5b8`](https://mobbin.com/screens/4d45d9bc-2fa2-44a3-9e67-c476bbc9b5b8)
  - [`fc8e6275-f856-44da-9b2e-894d54b41a1e`](https://mobbin.com/screens/fc8e6275-f856-44da-9b2e-894d54b41a1e)
  - [`3bf71644-d8e1-4da4-9553-7ead9b198756`](https://mobbin.com/screens/3bf71644-d8e1-4da4-9553-7ead9b198756)
  - [`4a1d40e2-0783-4f20-a0f7-c27c52338cad`](https://mobbin.com/screens/4a1d40e2-0783-4f20-a0f7-c27c52338cad)
  - [`511ecfa5-8eda-4afd-bb07-6f49211b2518`](https://mobbin.com/screens/511ecfa5-8eda-4afd-bb07-6f49211b2518)

Acctual의 중립 작업면, 강한 제목/본문 계층, 절제된 경계·라운드, 명확한 폼·버튼·목록·상세 패널을 차용한다. 금융 제품의 숫자 중심 밀도, 장식적 지표, 의료 승인으로 오해될 상태 의미는 복제하지 않는다.

### 직접 감사 범위

- 다운로드 PNG: 205장 (`/private/tmp/kof5-acctual.u7ywPI`, 감사 당시의 임시 작업 사본)
- 환자 변형 대표: `0, 20, 23, 34, 38, 40, 48, 56, 61, 63, 68`
- 보호자 대표: `83, 88, 108`
- 병원 대표: `84, 85, 123, 126, 139, 145, 148, 158, 176–181, 184–185, 193, 194, 201`

임시 다운로드는 저장소 근거가 아니다. 재검토에는 위 Mobbin app URL과 고정 highlight ID를 사용한다.

## 공통 언어

- 색상 역할: canvas `#F3F3F1`, workspace `#FFFFFF`, near-black 본문과 검정 primary CTA를 기본으로 한다. 경고·위험은 필요한 곳에서만 별도 의미색과 문구를 함께 쓴다.
- 글꼴: 제목은 `Nanum Myeongjo`, 본문은 `Pretendard` 계열을 우선하고 설치되지 않으면 한국어 시스템 글꼴로 대체한다.
- 형태: 4px/8px 간격, 절제된 라운드, hairline 경계, 그림자 최소화.
- 컴포넌트: 보호자와 병원 포털은 같은 rail, table, drawer, 버튼 높이, 입력 라벨, 상태 배지, 패널 제목, 빈 상태와 오류 문구를 공유한다. 화면마다 여러 강조 CTA를 만들지 않고 검정 primary CTA 하나만 둔다.
- 안전: 저장, 승인, 예약, 재생 완료, 직원 확인, 해결을 서로 다른 상태로 유지한다. 키·토큰·API origin의 실제 값은 표시하지 않는다.

## 세 모드의 변형

- 환자: Acctual의 색상·타입·여백만 Flutter theme으로 옮긴다. rail, table, drawer, 내비게이션, 버튼, 폼, 스크롤은 공유하지 않고 큰 시간·날짜, 병원 장소, 다음 일정, 수동적 음성 상태만 넓은 여백에 배치한다. AI 정체성 표시는 하지 않으며 이 결정의 Gate 07 충돌 상태를 유지한다.
- 보호자: 모바일은 단일 열과 한 번에 한 작업을 기본으로 하고, 데스크톱은 환자·음성 보조 열과 기억 관리 주 작업 열의 2열 그리드를 사용한다. 기억·음성·동의의 설명과 다음 행동을 가까이 둔다.
- 병원: 데스크톱 우선 마스터-디테일과 높은 정보 밀도를 허용한다. 모바일에서는 목록→상세 순차 탐색으로 바꾸고 핵심 승인·경고 작업을 hover나 넓은 표에만 두지 않는다.

내부 진단은 위 세 제품 모드가 아니다. `apps/patient_ipad/lib/main_debug.dart` 별도 Flutter target으로만 실행하며 환자 화면에 route나 숨은 제스처를 추가하지 않는다.

## 금지

- 환자 정보 장식화, 중첩 카드, 그라디언트, 자동 재생 애니메이션
- 환자 화면에 포털의 메뉴·버튼·폼·디버그 정보를 축소 복제
- Acctual의 금융 지표나 카피를 제품 의미 검토 없이 복제
- 포털 표시를 의료진 확인 또는 임상 해결로 과장
- eyebrow·kicker·overline·pretitle과 이를 큰 제목·설명문 위에 쌓는 장식적 히어로 구조
- 동작 결과·로딩·성공·실패를 본문 안의 색상 `div`, 배너, 카드로 계속 점유하는 상태 표시. 일시적 피드백은 한 번에 하나의 접근 가능한 toast/snackbar로 표시한다.
- 카드·callout·aside·목록 행 왼쪽에 색상 선을 붙이는 left accent border, accent stroke, accent stripe
- 수정 버튼 뒤에 편집 폼이나 임시 작업 `div`를 본문 흐름에 삽입해 기존 레이아웃을 미는 방식. 데스크톱은 우측 drawer/sheet, 모바일은 동일 컴포넌트의 bottom sheet를 사용하고 짧은 확인에만 중앙 modal을 쓴다.
