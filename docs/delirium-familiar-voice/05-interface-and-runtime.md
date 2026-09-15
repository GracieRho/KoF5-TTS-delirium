# 43. Patient Screen

화면은 최대한 단순하게 한다.

예:

```text
┌─────────────────────────────┐
│                             │
│        가족 사진            │
│                             │
│      9월 15일 화요일        │
│        오후 3:20            │
│                             │
│                             │
│     [대화 상태 visual]      │
│                             │
└─────────────────────────────┘
```

환자가 눌러야 하는 핵심 버튼은 두지 않는다.

---

# 44. Conversation Visual

대화 상태는 작고 비언어적으로 보여줄 수 있다.

예:

```text
Idle
작은 breathing indicator

Listening
부드러운 waveform

Speaking
voice animation
```

텍스트 instruction:

```text
"버튼을 누르세요"
"말씀해주세요"
```

같은 UI는 사용하지 않는다.

---

# 45. MVP 화면 목록

## Patient

- Idle / Presence
- Listening
- Speaking
- Temporary connection/error state

## Guardian

- Login
- Patient connect
- Voice enrollment
- Core memory questionnaire
- Memory review/edit

## Hospital

- Patient list
- Patient registration / current encounter
- Patient voice profile enrollment / refresh / withdrawal
- Patient dashboard
- Conversation history
- Message composer
- Schedule editor
- Context editor

---

# 46. API 초안

## Patient

```text
POST /patients/{id}/conversation/start
POST /patients/{id}/conversation/turn
POST /patients/{id}/conversation/end
WS   /patients/{id}/audio
```

## Guardian

```text
POST /patients/{id}/guardian
POST /patients/{id}/voice
GET  /patients/{id}/memories
POST /patients/{id}/memories
PATCH /memories/{id}
```

## Hospital

```text
GET  /hospital/patients
GET  /hospital/patients/{id}
POST /hospital/patients/{id}/voice-profile
DELETE /hospital/patients/{id}/voice-profile
POST /hospital/patients/{id}/message
POST /hospital/patients/{id}/schedule
PATCH /hospital/patients/{id}/context
```

환자 목소리 등록·삭제 API는 병원 직원 권한, 유효한 환자/대리인 동의·assent, 거부 및 원본 폐기 검사가 선행돼야 한다. 컬럼과 권한은 [병원 환자·목소리 프로필 설계](08-hospital-patient-registry-and-voice.md)에 둔다. 최초 iPad 경로는 후보 구간별 HTTP 처리부터 측정하고, 위 WS 초안은 지연 평가 뒤 선택한다.

---

# 47. Recommended State Machine

```text
BOOT
 ↓
IDLE
 ↓ speech detected
CANDIDATE_SPEECH
 ↓ directed
ACTIVE_LISTENING
 ↓ transcript ready
THINKING
 ↓ response ready
SPEAKING
 ↓
ACTIVE_LISTENING
 ↓ timeout
IDLE
```

예외:

```text
SPEAKING
 ↓ barge-in
ACTIVE_LISTENING
```

---

# 48. Candidate Speech Logic

pseudo:

```python
if vad.detected:
    transcript = stt.partial()

    score = activation_classifier(
        transcript=transcript,
        stt_confidence=confidence,
        speaker_similarity=optional_similarity,
        conversation_state=state
    )

    if score >= threshold:
        state = ACTIVE_LISTENING
    else:
        discard_buffer()
```

---

# 49. Activation Classifier

MVP에서는 별도 ML 모델을 학습하지 않는다.

작은 LLM classifier 또는 rule + LLM hybrid.

output:

```json
{
  "label": "DIRECTED",
  "confidence": 0.91
}
```

labels:

```text
DIRECTED
AMBIENT
UNCERTAIN
```

---

# 50. Prompt Architecture

System prompt는 최소 네 부분으로 분리한다.

```text
ROLE
SAFETY
KNOWN FACTS
CONVERSATION
```

---

# 51. Example Prompt

```text
You are a familiar conversational companion speaking in the registered guardian's voice.

Rules:
- Keep responses to 1-2 short Korean sentences.
- Never invent family facts.
- Never invent hospital information.
- Medical diagnosis or treatment advice is forbidden.
- Use the provided family context naturally.
- If the patient asks something unknown, do not pretend to know.

Hospital Context:
...

Family Context:
...

Recent Conversation:
...

Patient:
오늘이 며칠이냐?
```

---

# 52. Latency Budget

통화처럼 느끼려면 latency가 매우 중요하다.

목표:

```text
speech end
→ first TTS audio
```

가능하면:

```text
1.5~3 seconds
```

초기 MVP에서는 3초 내외까지 허용 가능.

---

# 53. Streaming 전략

가능하면 다음을 streaming한다.

```text
audio → STT
LLM → tokens
text chunks → TTS
```

단 MVP 초기에는 복잡도를 줄이기 위해:

```text
Streaming STT
+
non-streaming short LLM response
+
TTS
```

부터 시작 가능.

응답을 1~2문장으로 제한하면 latency가 줄어든다.

---
