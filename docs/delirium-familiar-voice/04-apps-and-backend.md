# 33. 앱 구성

MVP에서는 앱을 세 개 모두 native로 만들 필요 없다.

첫 환자 클라이언트는 사용자 시험 가능성을 위해 **iPad Flutter**로 정했다. 보호자·병원 웹 프레임워크는 아래 후보를 유지한다. 기기 내 VAD 뒤 발화 후보만 보내는 경로와 Vercel 우선 배포는 [ADR-0002](../../architecture/decisions/0002-ipad-local-audio-vercel-first.md)를 따른다.

---

## 33.1 Patient

```text
Flutter tablet app
```

이유:

- microphone streaming
- audio playback
- kiosk-like usage
- 앱 foreground 유지
- 향후 iOS/Android 확장

---

## 33.2 Guardian

```text
Next.js Responsive Web
```

기능:

- 회원가입
- 환자 연결
- voice enrollment
- memory onboarding
- memory 수정

---

## 33.3 Hospital

```text
Next.js Responsive Web
```

기능:

- patient list
- patient detail
- patient registration / active encounter
- patient voice enrollment, refresh and deletion (about 30-second test sample)
- today transcript
- hospital context
- message composer
- schedule configuration

---

# 34. 추천 기술 스택

로그인과 관계형 환자 데이터는 [ADR-0004](../../architecture/decisions/0004-supabase-auth-postgres.md)에 따라 Supabase Auth/Postgres로 결정했다. 다른 제공업체·웹 프레임워크·객체 저장·벡터 검색은 품질·지연·데이터 처리·운영 조건을 확인할 후보로 남긴다.

```text
Patient Client
Flutter

Guardian / Hospital
Next.js

Backend
FastAPI

Auth
Supabase Auth (확정)

Database
Supabase Postgres (확정)

Vector
pgvector (후보)

Object Storage
Supabase Storage (후보)

STT
Hosted streaming STT

LLM
Hosted LLM API

TTS
Hosted voice-cloning TTS API

Scheduler
Backend scheduler / managed cron

Deployment
Cloud Run / ECS / equivalent managed container
```

현재 구현 우선순위는 Vercel의 FastAPI/웹 배포다. 위 관리형 컨테이너 목록은 운영·실시간 시험 결과에 따른 대안으로 남긴다. Vercel WebSocket은 베타로 지원되지만, 첫 경로는 iPad 후보 발화별 짧은 HTTP 요청으로 측정한다. 화자 프로필·동의·병원 환자 컬럼은 [별도 설계](08-hospital-patient-registry-and-voice.md)를 참고한다.

---

# 35. Backend Logical Components

```text
API Gateway / FastAPI
│
├── Auth Service
├── Patient Service
├── Guardian Service
├── Hospital Service
├── Memory Service
├── Conversation Orchestrator
├── Audio Session Service
├── Scheduler
├── Safety Engine
├── TTS Adapter
├── STT Adapter
└── Audit / Logging
```

---

# 36. Conversation Orchestrator

핵심 backend module.

input:

```json
{
  "patient_id": "...",
  "trigger": "patient_speech",
  "transcript": "...",
  "session_id": "..."
}
```

tasks:

```text
1. trigger identify
2. required context retrieve
3. safety constraints load
4. LLM prompt construct
5. response generate
6. response validate
7. TTS request
8. conversation log
```

---

# 37. STT Adapter

Provider dependency를 직접 application logic에 박지 않는다.

interface 예시:

```python
class STTProvider:
    async def stream(self, audio_stream): ...
    async def transcribe(self, audio): ...
```

나중에 provider 변경 가능.

---

# 38. TTS Adapter

```python
class TTSProvider:
    async def create_voice(self, samples): ...
    async def synthesize(self, voice_id, text): ...
```

MVP provider가 바뀌어도 business logic은 유지한다.

---

# 39. Conversation DB

```sql
conversation_session

id
patient_id
started_at
ended_at
trigger_type
status
```

```sql
conversation_turn

id
session_id
speaker
transcript
source
started_at
ended_at
confidence
audio_url_nullable
```

speaker:

```text
patient
assistant
hospital
```

---

# 40. Trigger Types

```text
patient_spontaneous
scheduled_orientation
scheduled_memory
hospital_immediate
hospital_scheduled
```

---

# 41. Safety Rules

최소한 다음 rule은 hard-coded policy로 둔다.

---

## Rule 1

의료 진단 금지.

---

## Rule 2

약물 복용 결정 금지.

---

## Rule 3

병원 일정은 hospital_context에 있는 정보만 사용.

---

## Rule 4

가족 정보는 family_context에 있는 정보만 사용.

---

## Rule 5

모르는 가족 사실을 추측하지 않는다.

---

## Rule 6

응답은 원칙적으로 1~2문장.

---

## Rule 7

환자가 통증, 낙상, 호흡곤란, 위험 상황을 말하면 정상 conversational response보다 **기존 의료진 호출 수단 안내와 보조 알림 후보**를 우선한다.

예:

```text
"숨이 너무 차."
"가슴이 아파."
"넘어졌어."
```

→ staff alert candidate

초기 환자 시험에서 이 알림은 기존 nurse-call을 대체하지 않는다. 알림 생성·전달·의료진 확인을 구분하고, 확인되지 않은 상태에서 의료진에게 알렸다고 말하지 않는다. 상세 조건은 [안전·윤리 게이트](07-pre-patient-trial-safety-ethics-gate.md)의 Gate 4를 따른다.

---

# 42. Hospital Message Fidelity

병원 메시지는 fidelity가 가장 중요하다.

목표:

```text
meaning preservation = 100%
```

LLM creative generation보다 source fidelity를 우선한다.

---
