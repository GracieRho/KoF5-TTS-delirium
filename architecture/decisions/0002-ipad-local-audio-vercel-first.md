# ADR-0002: iPad 기기 내 발화 감지와 Vercel 우선 배포

- 상태: 승인됨
- 작성일: 2026-09-15
- 관련 문서: [MVP PRD](../../docs/Delirium_Familiar_Voice_MVP_PRD.md), [환자 시험 전 안전 게이트](../../docs/delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md), [ADR-0001](0001-cloud-first-familiar-voice-mvp.md)

## 배경

첫 기능 시험은 사용자가 가진 iPad에서 할 수 있어야 한다. 대기 중 병실 음성을 계속 클라우드로 보내지 않고, 기기에서 발화를 감지한 뒤 필요한 요청만 백엔드로 전달한다. 웹 화면과 짧은 API는 Vercel에서 시작할 수 있다.

## 검토한 선택지

- **대기 오디오의 상시 서버 스트리밍:** 원격 처리가 단순해지지만 병실 주변 음성 전송과 연결·운영 부담이 크다.
- **iPad 로컬 감지 후 후보 구간만 전송:** Flutter에서 짧은 임시 버퍼·VAD·재생 중단을 맡아 대기 음성의 서버 전송을 줄인다. 발화 후보에 주변인이 섞일 수 있어 활성화 판정과 즉시 폐기 정책은 별도로 필요하다.
- **Vercel HTTP/필요 시 WebSocket:** [FastAPI 배포](https://vercel.com/docs/frameworks/backend/fastapi)와 [FastAPI WebSocket 베타](https://vercel.com/docs/functions/websockets)가 가능하다. 연결은 함수 시간 제한에 따라 끊길 수 있으며 재연결 뒤의 상태는 외부 저장소가 필요하다.

## 결정

1. 첫 환자 앱 시험 대상은 **iPad**다. Flutter로 기기 내 마이크 입력, 최근 몇 초의 휘발성 버퍼, 발화 후보 감지, 음성 재생과 barge-in 중단을 구현한다. 기기 내 처리는 온디바이스 TTS 추론을 뜻하지 않는다.
2. IDLE 중 오디오는 서버에 상시 전송하지 않는다. 로컬 VAD가 후보를 찾으면 직전 약 1~2초를 포함한 짧은 구간만 후속 처리한다. 초기에는 후보별 HTTP 요청을 사용하고, 실제 지연·오활성화 측정으로 필요한 경우에만 해당 구간의 스트리밍을 추가한다.
3. 보호자·병원 웹과 짧은 FastAPI 요청은 **Vercel을 첫 배포 대상으로 준비**한다. Vercel WebSocket을 쓸 수 있으나 베타 동작, 함수 시간 제한, 재연결, 비용과 상태 저장을 실제 iPad 시험에서 검증한 뒤 실시간 경로를 확정한다. 현재 메모리 세션 API는 로컬 합성 시험 전용이며 Vercel의 영속 상태 모델이 아니다.
4. Flutter의 녹음 기능은 보호자 음성 **채집**을 맡을 수 있다. 복제 생성, 음성 소유자 동의 기록 검증, 제3자 전송, voice ID 보관과 삭제는 백엔드·TTS 제공업체 흐름으로 분리한다. 보호자 UI를 Flutter로 만들지 웹으로 만들지는 온보딩 시험에서 정한다.

## 결과와 남은 검증

- 작업 전용 iPad 앱은 로컬 PCM 후보를 Apple Speech의 기기 내 한국어 인식에만 넘기는 경로를 컴파일했다. [Apple Speech 요청 설정](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)에 따라 해당 언어·기기가 `supportsOnDeviceRecognition`을 보고해야 전사를 켜고 `requiresOnDeviceRecognition`을 적용한다. 실제 iPad의 한국어 지원·정확도는 미검증이다.
- VAD와 전사만으로 DIRECTED와 AMBIENT 또는 환자·의료진·TV 화자를 구분할 수 없다. 로컬 활성화가 충분한지 측정하기 전에는 수동 자가 음성 시험의 후보 오디오가 hosted STT로 일시 전송될 수 있다. 실제 환자 시험 전에 안전 게이트 Gate 3의 전송·폐기·고지 절차와 제공업체 정책을 확정한다.
- Vercel은 배포 선호이며 운영 검증을 통과한 확정 인프라가 아니다. 임상 데이터 저장·권한·지역·장애 대응과 WebSocket 재연결 상태를 별도 검증한다.
- 이 ADR은 실제 환자 대상 시험을 승인하지 않는다. ADR-0001의 네 안전 게이트와 기관 검토가 계속 적용된다.
