# 6. 환자 앱 핵심 인터랙션 모델

환자 앱은 크게 두 상태로 나뉜다.

```text
IDLE
↓
ACTIVE CONVERSATION
↓
IDLE
```

---

# 7. Always-Listening Architecture

MVP의 가장 중요한 인터랙션 구조다.

환자가 먼저 말을 걸 수 있어야 하므로 마이크는 대기 상태에서도 활성화되어 있어야 한다.

다만 다음은 동일하지 않다.

```text
항상 듣는다
≠
항상 저장한다
```

---

## 7.1 IDLE State

대화가 진행 중이지 않은 상태.

```text
Microphone
↓
Local / streaming rolling buffer
↓
VAD
↓
Speech detected
↓
Streaming STT
↓
Activation classifier
↓
DIRECTED / AMBIENT / UNCERTAIN
```

### 예시

```text
"수민아?"
→ DIRECTED

"오늘 몇 시지?"
→ DIRECTED 가능

"나 집에 언제 가?"
→ DIRECTED 가능

TV: "오늘 오후 뉴스입니다."
→ AMBIENT

간호사: "이 환자분 혈압 다시 재주세요."
→ AMBIENT
```

---

# 8. Rolling Audio Buffer

대기 상태에서는 오디오를 장기 저장하지 않는다.

태블릿은 최근 몇 초만 임시로 유지한다.

```text
[t-5]
[t-4]
[t-3]
[t-2]
[t-1]
[now]
```

VAD가 speech start를 감지하면 이전 약 1~2초까지 포함하여 STT로 전달한다.

목적:

- 첫 음절 손실 방지
- privacy 개선
- 불필요한 병실 음성 저장 방지

ambient로 분류된 데이터는 즉시 폐기한다.

---

# 9. Activation Decision

MVP에서는 하나의 classifier만 믿지 않는다.

여러 signal을 종합한다.

```text
VAD speech detected
+
STT confidence
+
direct-address likelihood
+
conversation intent
+
optional patient voice similarity
+
current context
↓
activation score
```

예시:

```text
if activation_score >= threshold:
    open_conversation()
else:
    discard()
```

---

# 10. Speaker Verification

병원 환자 등록 화면에서 약 30초의 환자 목소리를 받는 설계는 [병원 환자·목소리 프로필](08-hospital-patient-registry-and-voice.md)에 추가한다. 등록 UI는 구현 대상이지만, 화자 유사도를 활성화 신호로 실제 적용할지는 고령 환자의 짧은 발화·컨디션 변화에 대한 오검출/누락 측정 뒤 결정한다.

MVP v1에서는 **optional feature**로 둔다.

환자 음성을 등록할 수 있다면 patient speaker embedding을 생성한다.

```text
incoming speech
↓
speaker embedding
↓
patient embedding과 similarity
↓
activation feature로 사용
```

주의:

> speaker verification은 hard gate가 아니다.

고령 환자의 목소리는 컨디션에 따라 크게 달라질 수 있기 때문이다.

따라서 다음처럼 사용한다.

```text
patient_similarity = 0.8
directed_speech = true
stt_confidence = 0.91

→ 높은 activation score
```

---

# 11. ACTIVE CONVERSATION State

한 번 대화가 시작되면 기준을 낮춘다.

IDLE:

```text
activation threshold = HIGH
```

ACTIVE:

```text
activation threshold = LOW
```

따라서 다음도 정상 대화로 처리한다.

```text
"응."
"아니."
"몰라."
"죽."
"그래."
```

---

# 12. 자연스러운 Turn Taking

환자가 듣고 있는 동안 시스템이 말하고, 환자가 응답하면 다음 turn을 처리한다.

```text
TTS response
↓
speech end
↓
listening window
↓
VAD
↓
STT
↓
silence 0.8~1.2 sec
↓
turn end
↓
LLM response
```

---

# 13. Barge-In

환자가 시스템 음성 도중 말을 시작하면 음성을 중단한다.

```text
TTS playing
↓
patient speech detected
↓
stop TTS
↓
capture speech
↓
STT
↓
response
```

예:

```text
AI:
"오늘 날씨가 좋아서—"

환자:
"근데 민수는 어디 있어?"

AI:
[TTS 중단]
"민수는 지금 회사에 있어."
```

MVP의 naturalness를 크게 높이는 기능이다.

---

# 14. Conversation Session 종료

다음 조건 중 하나면 ACTIVE → IDLE.

```text
30~60초 무응답
OR
명시적 종료 표현
OR
병원 staff 종료
OR
앱 lifecycle 종료
```

예:

```text
"나 좀 잘게."
"이제 됐다."
"나중에 얘기하자."
```

---

# 15. 환자 대화 Pipeline

최종 구조:

```text
Patient speech
↓
VAD
↓
Streaming STT
↓
Activation / Turn detection
↓
Context retrieval
↓
Safety / Policy layer
↓
LLM
↓
Response validation
↓
Voice Clone TTS
↓
Patient
```

---

# 16. 대화가 시작되는 3가지 경로

시스템의 Conversation Engine은 시작점만 다르고 이후 동일하다.

```text
                    ┌─────────────────────┐
                    │ Conversation Engine │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
Patient Speech          Scheduled Event      Hospital Message
환자가 먼저 말함         시스템이 먼저 말함       병원이 먼저 말함
```

---

# 17. Patient-Initiated Conversation

환자가 spontaneous speech를 시작하면 시스템이 이를 감지한다.

예:

```text
환자:
"수민아 지금 몇 시야?"

↓
IDLE activation
↓
STT
↓
conversation start
↓
current_time tool/context
↓
TTS

"지금 오후 3시 20분이야."
```

---

# 18. Scheduled Conversation

MVP에서 “agent”라는 표현은 사용하지 않는다.

실제 구현은 deterministic scheduler다.

예:

```text
08:00 Morning Orientation
12:00 Lunch Check-in
15:00 Memory Prompt
18:00 Evening Orientation
21:00 Good-night
```

실행:

```text
Scheduler
↓
intervention type 선택
↓
approved facts retrieve
↓
1~2 sentence 생성
↓
safety validation
↓
TTS
```

---

# 19. Hospital-Initiated Message

병원에서 특정 정보를 환자에게 전달할 수 있다.

예:

```text
오늘 오후 4시에 CT 촬영 예정입니다.
```

MVP에서는 의료진 메시지를 LLM이 자유롭게 rewrite하지 않는다.

```text
Hospital message
↓
Family Voice TTS
↓
Patient
```

추후 기능:

```text
[원문 그대로]
[친근한 표현 제안]
```

단, rewrite된 문장은 직원의 승인을 받은 후에만 발송한다.

---

# 20. Conversation Personality

시스템의 음성은 가족 목소리를 사용하지만, 응답 원칙은 안전하게 제한한다.

목표:

> Familiar Presence

즉 친숙한 가족의 목소리와 말투를 활용하되, 의료 정보나 현실 정보를 임의로 창작하지 않는다.

---

# 21. Reality / Identity Policy

제품 UX는 친숙하고 자연스러워야 하지만 시스템이 실제 가족 본인이나 실제 전화 연결이라고 주장해서는 안 된다. 시험 전 AI 음성 사용을 고지하고, 정체성을 직접 질문받으면 사실대로 답한다.

피해야 할 표현:

```text
"나 지금 너랑 실제로 전화하고 있어."
"내가 지금 병원 밖에서 전화한 거야."
```

허용되는 자연스러운 표현:

```text
"응, 왜?"
"오늘은 화요일이야."
"점심은 먹었어?"
"지난번 제주도 이야기 기억나?"
```

실제 환자 대상 시험 전 고지 방식과 응답 문구는 의료진·기관 검토를 거쳐 확정한다. 세부 조건은 [안전·윤리 게이트](07-pre-patient-trial-safety-ethics-gate.md)의 Gate 1을 따른다.

---
