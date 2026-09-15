# 33. 앱 구성

MVP에서는 앱을 세 개 모두 native로 만들 필요 없다.

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
- today transcript
- hospital context
- message composer
- schedule configuration

---

# 34. 추천 기술 스택

```text
Patient Client
Flutter

Guardian / Hospital
Next.js

Backend
FastAPI

Auth
Supabase Auth

Database
Supabase Postgres

Vector
pgvector

Object Storage
Supabase Storage

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

환자가 통증, 낙상, 호흡곤란, 위험 상황을 말하면 정상 conversational response보다 **의료진 호출 pathway**를 우선한다.

예:

```text
"숨이 너무 차."
"가슴이 아파."
"넘어졌어."
```

→ staff alert candidate

MVP에서는 자동 응급 판단 대신 **high-risk keyword/LLM classifier → staff notification** 수준으로 구현한다.

---

# 42. Hospital Message Fidelity

병원 메시지는 fidelity가 가장 중요하다.

목표:

```text
meaning preservation = 100%
```

LLM creative generation보다 source fidelity를 우선한다.

---
