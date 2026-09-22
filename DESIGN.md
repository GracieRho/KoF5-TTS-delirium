# Design

## Source of truth

- Status: Needs refresh
- Last refreshed: 2026-09-22
- Primary product surfaces: 환자 병상 iPad, 보호자 반응형 웹, 병원 직원 반응형 웹, 내부 진단 화면
- Evidence reviewed: `docs/delirium-familiar-voice/01-vision-and-scope.md`, `02-patient-conversation.md`, `03-context-and-guardian.md`, `04-apps-and-backend.md`, `05-interface-and-runtime.md`, `07-pre-patient-trial-safety-ethics-gate.md`, `08-hospital-patient-registry-and-voice.md`, `09-phase5-and-patient-trial-status.md`, `apps/patient_ipad/`, 기존 `src/kof5_tts/*_portal.html`
- Current direction: 환자 화면은 조작용 앱이 아니라 병상 환경 정보와 음성 상태를 수동적으로 보여주는 디스플레이다. 보호자와 병원 직원의 입력·운영 작업은 `apps/portal_web/`의 React 웹에서 담당한다.
- Safety status: 환자 화면에서 AI 정체성 표시는 제공하지 않는다는 제품 지시는 기존 Gate 07의 Identity Transparency 요구와 충돌한다. 이 문서는 그 충돌을 해소하지 않으며, 임상·기관 검토로 대체 고지·동의·정체성 질문 응답 정책이 승인되기 전 실제 환자 사용은 차단한다.

### Reference patterns

보호자 포털:

- [Base44 Memory](https://mobbin.com/screens/0e4f499d-670b-4c3e-98bf-8eca59297b32): 한 번에 하나의 기억을 부담 없이 작성하는 입력 흐름을 참고한다. 자유 대시보드처럼 기능을 늘리지 않는다.
- [komoot photo/share](https://mobbin.com/screens/c83a4224-e1cd-4e66-9c1f-dd943c44969d): 사진과 설명을 함께 확인하는 검토 구조를 참고한다. 공개 공유·소셜 반응 패턴은 사용하지 않는다.
- [Delphi voice enrollment](https://mobbin.com/screens/904d476f-dd99-40e0-a4f6-6cea3ddb4f36): 음성 등록의 단계, 준비 상태와 재시도를 참고한다. 성공 표시가 실제 삭제·보존·임상 사용 승인을 뜻하게 만들지 않는다.
- [Oyster checklist](https://mobbin.com/screens/b36e49cb-4dce-41aa-a161-696caedaef44): 온보딩의 남은 작업과 완료 상태를 참고한다. 안전 게이트를 단순 체크박스로 대체하지 않는다.
- [Gusto consent](https://mobbin.com/screens/8b9abf72-9ad1-45ca-9d20-f754ecb16cb9): 동의 내용을 읽고 명시적으로 확인하는 구조를 참고한다. 목적별 동의를 하나의 포괄 동의로 합치지 않는다.

병원 포털:

- [Fresha table](https://mobbin.com/screens/a1f76a62-568f-4b2d-9c9f-6a610dd3ebf7): 검색 가능한 고밀도 환자 목록과 상태 스캔 패턴을 참고한다. 모바일에서 데스크톱 표를 그대로 축소하지 않는다.
- [Time2book detail panel](https://mobbin.com/screens/c101a468-c2e9-4803-957e-b49489612815): 목록 문맥을 유지한 상세 패널을 참고한다. 중요한 승인·오류를 패널 안에 숨기지 않는다.
- [Deputy approval queue](https://mobbin.com/screens/40b0eeda-18ea-4067-ba0f-1b757cdbe424): 대기 항목, 근거, 승인 작업을 한 흐름에서 비교하는 패턴을 참고한다. 자기 승인이나 일괄 안전 승인을 허용하지 않는다.
- [Deputy schedule](https://mobbin.com/screens/a0e97f81-c13c-4ca3-ba74-1e00efd1ad19): 시간순 일정과 상태 구분을 참고한다. 승인되지 않은 일정을 환자 화면에 노출하지 않는다.
- [incident.io alerts](https://mobbin.com/screens/1d72b14c-95e4-4d38-affb-039c4dc40139): 경고의 생성·수신·확인·해결 상태 분리를 참고한다. 포털 표시를 의료진 확인이나 임상 해결로 표현하지 않는다.

## Brand

- Personality: 차분함, 익숙함, 존중, 임상적 신뢰성
- Trust signals: 승인 상태와 출처가 분명한 병원 정보, 최근 저장·전달 상태, 오류를 숨기지 않는 운영 피드백
- Avoid: 소비자용 AI 챗봇 외형, 자극적인 그라데이션·과도한 애니메이션, 환자에게 조작을 요구하는 CTA, 실제 가족 통화라고 주장하는 표현, 환자 화면의 API 주소·토큰·키·디버그 로그

## Product goals

- Goals: 환자에게 현재 시간·날짜·장소·가까운 병원 일정을 안정적으로 제시하고, 보호자와 직원이 각자의 권한 범위에서 맥락·음성·메시지를 관리하게 한다.
- Non-goals: 환자용 설정 화면, 환자 직접 데이터 입력, 의료 진단·처방, 기존 간호 호출 대체, 실제 가족과 연결된 통화라는 기만
- Success signals: 환자 화면이 별도 조작 없이 읽히고, 보호자·병원 핵심 흐름이 휴대전화와 데스크톱에서 완료되며, 민감 설정과 진단 기능이 환자 화면에 노출되지 않는다.

## Personas and jobs

- Primary personas: 화면 조작이 어렵거나 불가능한 섬망 환자, 가족 기억·음성을 제공하는 보호자, 환자·입원·일정·메시지·안전 상태를 관리하는 병원 직원
- User jobs: 환자는 현재 상황을 수동적으로 확인한다. 보호자는 환자 연결, 기억 관리, 피해야 할 소재 관리, 동의된 음성 등록 상태 확인을 수행한다. 직원은 환자·입원 조회, 승인된 병원 사실과 일정·메시지 관리, 경고·기기 연결 상태 확인을 수행한다.
- Key contexts of use: 환자 iPad는 병상에서 장시간 켜져 있고 사용자가 터치하지 않는 상황을 기본으로 한다. 보호자 웹은 모바일 우선의 짧은 세션, 병원 웹은 데스크톱 중심의 빈번한 조회와 모바일 보조 사용을 전제로 한다.

## Information architecture

- Primary navigation: 환자 화면에는 내비게이션이 없다. 보호자 웹은 환자 선택, 기억, 음성, 계정으로 단순화한다. 병원 웹은 환자 목록과 선택된 환자 상세를 중심으로 개요, 일정·메시지, 맥락, 안전·기기 상태를 구분한다.
- Core routes/screens: `/guardian`, `/hospital`, `apps/patient_ipad/lib/main.dart`의 환자 iPad 기본 화면, `apps/patient_ipad/lib/main_debug.dart`의 내부 진단 화면
- Content hierarchy: 환자 화면은 시간·날짜, 현재 장소/병실 맥락, 오늘의 다음 일정, 음성 시스템 상태 순이다. 운영 웹은 즉시 조치가 필요한 상태, 현재 입원 정보, 편집 가능한 콘텐츠, 감사·기술 세부 순이다.
- Boundary: 진단 화면은 환자 기본 화면의 설정 패널이 아니다. 숨은 제스처나 라우트 없이 별도 Flutter target으로만 실행하며 키·토큰의 실제 값은 그 화면에서도 표시하지 않는다.

## Design principles

- Passive before interactive: 환자에게 누르기, 스크롤, 입력, 메뉴 탐색을 요구하지 않는다.
- Orientation before conversation: 환자 화면의 중심은 날짜·시간·장소·오늘 일정이며, 대화 상태는 보조 정보다.
- Role-specific complexity: 보호자에게는 가족 맥락만, 직원에게는 병원 운영 정보만 보이고 기술 진단은 제품 화면과 분리한다.
- Safety is explicit in operations: 웹에서 동의, 승인, 전달, 실패 상태를 서로 다른 상태로 보여주고 성공처럼 뭉뚱그리지 않는다.
- Tradeoffs: 환자 화면에서 AI 정체성 표시는 제거하지만 이 선택은 Gate 07을 통과한 것으로 간주하지 않는다. 실제 환자 사용 전 대체 고지 방식과 정체성 질문 응답을 별도로 승인받아야 한다.

## Visual language

- Color: 따뜻한 중립 배경, 높은 명도 대비의 본문, 상태 색상은 의미가 고정된 소수만 사용한다. 색만으로 상태를 전달하지 않는다.
- Typography: 환자 화면은 멀리서 읽히는 큰 한국어 숫자·본문과 짧은 행 길이. 웹은 기본 16px 이상과 명확한 제목 계층을 사용한다.
- Spacing/layout rhythm: 환자 화면은 넓은 여백과 세 영역 이하의 고정 구획. 웹은 4/8px 계열의 일관된 간격과 카드 남용 없는 정보 그룹을 사용한다.
- Shape/radius/elevation: 완만한 모서리와 낮은 대비의 경계선을 우선하고, 그림자는 중첩 관계가 필요할 때만 사용한다.
- Motion: 음성 상태 변화에 짧고 잔잔한 전환만 사용하며 지속적인 파형·맥박 효과는 피한다.
- Imagery/iconography: 장식용 사진보다 시간·일정·장소 정보의 가독성을 우선한다. 아이콘은 텍스트 라벨을 대체하지 않는다.

## Components

- Existing components to reuse: 현재 Supabase Auth/RLS 흐름, 환자·입원·기억·메시지·경고 상태 모델, Flutter의 기존 오디오·세션 로직
- New/changed components: 환자 `Clock`, `DateAndPlace`, `ScheduleCard`, `PassiveAudioStatus`; 공통 웹 `AppShell`, `StatusBadge`, `EmptyState`, `InlineNotice`; 보호자 기억·음성 폼; 병원 환자 목록·상세·승인/메시지 패널
- Variants and states: 일정 없음/다음 일정/진행 중, 오디오 대기/듣는 중/말하는 중/일시적 연결 문제, 웹 로딩/빈 상태/권한 없음/저장 중/저장됨/실패
- Token/component ownership: React 포털의 토큰과 공통 컴포넌트는 `apps/portal_web/`가 소유한다. Flutter 환자 화면은 같은 의미 체계를 따르되 Dart 구현을 공유하려는 별도 디자인시스템 패키지는 만들지 않는다.

## Accessibility

- Target standard: 보호자·병원 웹은 WCAG 2.2 AA를 목표로 한다. 환자 화면은 이 기준에 더해 큰 글자, 낮은 인지 부하, 비조작 사용을 우선한다.
- Keyboard/focus behavior: 웹의 모든 폼·대화상자·탭·행 작업은 키보드로 접근 가능하고, 포커스 표시와 오류 후 포커스 이동이 명확해야 한다.
- Contrast/readability: 본문과 핵심 상태는 AA 대비를 충족하고 작은 회색 글자에 핵심 정보를 두지 않는다. 환자 화면은 한 화면에 핵심 정보만 유지한다.
- Screen-reader semantics: 웹의 제목, 랜드마크, 필드 라벨, 오류 연결, 라이브 저장 상태를 의미론적으로 제공한다.
- Reduced motion and sensory considerations: `prefers-reduced-motion`에서 비필수 전환을 제거한다. 환자 화면은 깜빡임, 자동 스크롤, 경고음 중심 피드백을 사용하지 않는다.

## Responsive behavior

- Supported breakpoints/devices: 보호자 웹은 360px 이상 휴대전화부터, 병원 웹은 1280px 전후 데스크톱을 주 화면으로 하되 390px 모바일에서 조회·핵심 조치가 가능해야 한다. 환자 화면은 iPad 가로·세로의 안전 영역을 지원한다.
- Layout adaptations: 보호자는 단일 열 폼에서 넓은 화면의 보조 설명 열로 확장한다. 병원은 데스크톱의 목록/상세 분할을 모바일에서 목록→상세 순차 화면으로 바꾼다. 표는 카드로 무조건 변환하지 않고 핵심 열 고정, 수평 스크롤 또는 상세 이동 중 정보 밀도에 맞는 방식을 선택한다.
- Touch/hover differences: 최소 44×44px 터치 목표를 사용한다. hover에만 있는 정보나 작업을 만들지 않는다.

## Interaction states

- Loading: 기존 정보를 지우지 않는 국소 로딩을 우선하며 첫 진입에는 구조를 보존하는 간단한 스켈레톤을 사용한다.
- Empty: 권한 없음, 아직 등록되지 않음, 오늘 일정 없음처럼 원인과 가능한 다음 행동을 구분한다.
- Error: 민감한 내부 오류나 키 값을 보여주지 않고 재시도 가능 여부와 운영자 조치를 알려준다.
- Success: 저장·승인·예약·전달 완료를 구분해 표시한다. iPad 재생 완료는 환자가 내용을 이해하거나 임상 전달이 완료됐다는 뜻으로 표시하지 않는다.
- Disabled: 비활성 이유를 인접한 설명으로 제공한다.
- Offline/slow network: 환자 화면은 마지막으로 검증된 시간·일정의 시각을 표시하고 오래된 정보임을 구분한다. 웹 편집은 실패한 저장을 성공처럼 낙관적으로 확정하지 않는다.

## Content voice

- Tone: 짧고 차분한 존댓말, 판단하거나 재촉하지 않는 표현
- Terminology: 환자 화면은 `오늘 일정`, `현재 시간`, `잠시 연결을 확인하고 있어요`처럼 생활 언어를 사용한다. 운영 웹은 `승인`, `예약`, `재생 완료`, `직원 확인`, `해결`을 구분한다.
- Microcopy rules: 환자에게 버튼 조작을 지시하지 않는다. 실제 가족과 통화 중이라고 주장하지 않는다. 환자 화면에는 AI 정체성 문구를 표시하지 않지만, 정체성 질문 대응과 대체 고지 정책은 임상·기관 검토 전 미확정이다.

## Implementation constraints

- Framework/styling system: 환자 앱은 Flutter, 보호자·병원 포털은 `apps/portal_web/`의 React/TypeScript 반응형 웹, API는 FastAPI, 인증·데이터는 Supabase Auth/Postgres/RLS를 유지한다.
- Design-token constraints: 포털 안에서 CSS 변수와 소수의 공통 컴포넌트를 재사용한다. Flutter와 웹 사이 토큰 코드 생성을 추가하지 않는다.
- Performance constraints: 환자 시계는 네트워크 없이 계속 갱신되어야 한다. 포털의 초기 화면은 필요한 역할 데이터만 불러오며 대형 UI 프레임워크를 새로 추가하지 않는다.
- Compatibility constraints: 환자 화면에는 빌드 설정, API origin, publishable key, 내부 토큰 입력이나 로그를 노출하지 않는다. 진단은 별도 진입점에서만 접근하며 비밀 값은 서버/빌드 환경에서 주입한다.
- Test/screenshot expectations: 환자 iPad 가로·세로, 보호자 390px/데스크톱, 병원 390px/데스크톱을 시각 확인한다. 역할별 로딩·빈 상태·오류·성공과 키보드 포커스를 회귀 검사한다.

## Open questions

- [ ] 임상·기관 책임자: 환자 화면의 AI 표시를 제거하면서 Gate 07 Identity 요구를 충족할 대체 사전 고지, 재고지, 정체성 질문 응답 정책은 무엇인가? 미해결 시 실제 환자 사용 차단.
- [ ] 임상 책임자: 환자 화면에 표시할 병원 일정 범주와 문구를 누가 승인하고 얼마나 자주 갱신하는가?
- [ ] 제품/임상 책임자: 연결 장애 때 환자에게 보여줄 최소 문구와 직원 알림 경로는 무엇인가?
- [ ] 엔지니어링: `main_debug.dart` target이 환자 배포 빌드와 배포 절차에서 제외되는지 검증한다.
