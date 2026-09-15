# 54. 개인정보 원칙

반드시 구분한다.

```text
Always listening
vs
Always recording
```

기본 정책:

- idle audio 저장 금지
- ambient audio 저장 금지
- conversation transcript만 저장
- audio recording 저장은 opt-in
- 보호자 voice sample 명시적 consent
- 환자 화자 특징 등록은 별도 동의·assent/거부 확인과 원본 샘플 폐기를 전제로 함
- voice clone deletion 지원
- audit log 유지

---

# 55. 개발 Phase

아래 Phase는 기능 구현 순서다. 합성 데이터·팀 내부 검증과 실제 환자 대상 시험은 구분한다. 실제 환자 데이터 처리와 시험은 [안전·윤리 게이트](07-pre-patient-trial-safety-ethics-gate.md)의 네 조건 및 기관 검토가 완료된 뒤에만 시작한다. 권한·동의·데이터 처리·장애 대응은 환자 시험을 위한 선행 조건이며 Phase 5까지 미뤄도 된다는 뜻이 아니다.

## Phase 0 — Core Prototype

목표:

```text
환자 음성
→ STT
→ LLM
→ cloned TTS
```

기능:

- single patient
- single guardian voice
- manual text memory
- push test screen
- latency 측정

---

## Phase 1 — Natural Conversation

추가:

- VAD
- IDLE / ACTIVE
- spontaneous speech activation
- turn detection
- barge-in
- session timeout

이 단계가 본 제품의 핵심 MVP.

---

## Phase 2 — Memory

추가:

- family context DB
- pgvector
- retrieval
- guardian onboarding
- dynamic follow-up

---

## Phase 3 — Hospital

추가:

- hospital dashboard
- context management
- immediate message
- scheduled message
- transcript review

---

## Phase 4 — Safety

추가:

- unsafe medical request detection
- unsupported fact detection
- hospital/family namespace enforcement
- high-risk speech alert

---

## Phase 5 — Pilot Readiness

추가:

- auth/role 검증
- 승인된 consent·철회 흐름 구현
- audit
- deletion
- observability
- failure handling
- hospital security review

---

# 56. 개발 우선순위

실제 구현은 아래 순서로 한다.

```text
1. Voice cloning API 확인
2. STT → LLM → TTS end-to-end
3. Flutter audio streaming
4. VAD
5. conversation state machine
6. spontaneous patient activation
7. barge-in
8. family memory RAG
9. guardian onboarding
10. hospital dashboard
11. scheduler
12. safety rules
13. logging / evaluation
```

---

# 57. 가장 먼저 만들어야 하는 Demo

첫 데모는 이것 하나면 된다.

```text
환자 역할 사람이 침대에 누워 있음

"수민아?"

↓ 자동 감지

가족 목소리:
"응, 왜?"

환자:
"오늘이 며칠이야?"

가족 목소리:
"오늘은 9월 15일 화요일이야."

환자:
"우리 제주도 언제 갔었지?"

↓ family context retrieval

가족 목소리:
"2024년 5월에 같이 갔었어.
아빠가 흑돼지를 되게 좋아했잖아."
```

여기까지 자연스럽게 되면 제품의 핵심 가설은 이미 상당 부분 검증된다.

---

# 58. KPI

## Voice

- voice similarity
- Korean intelligibility
- TTS latency

## Speech

- STT accuracy
- elderly speech accuracy
- speech start detection
- speech end detection

## Activation

- patient initiation recall
- false activation rate
- TV false activation rate
- ambient conversation false activation

## Conversation

- end-to-end latency
- successful turn rate
- barge-in success rate
- conversation abandonment

## Memory

- retrieval precision
- unsupported fact rate
- family fact hallucination rate

## Hospital

- message fidelity
- schedule delivery rate

## Guardian

- onboarding completion
- onboarding duration
- question completion
- voice enrollment completion

---

# 59. MVP Success Criteria

최초 MVP에서는 아래 정도를 목표로 한다.

```text
환자가 먼저 말 걸기
→ 대부분 정상 activation

TV / 주변 음성
→ 대부분 무시

대화 turn
→ 3초 전후 응답

가족 관련 질문
→ DB 기반 답변

모르는 정보
→ hallucination하지 않음

병원 메시지
→ 원문 의미 그대로 전달
```

---

# 60. 핵심 기술적 차별화

이 제품의 차별화는 자체 TTS 모델이 아니다.

핵심은 다음 세 가지다.

## 60.1 Familiar Voice

보호자 음성 기반 interaction.

## 60.2 Familiar Memory

환자와 가족이 공유하는 autobiographical memory.

## 60.3 Safe Context Orchestration

가족 정보, 병원 정보, 현재 대화 정보를 분리하고 안전하게 조합.

---

# 61. 연구 방향 재정의

기존:

> F5-TTS의 한국어 성능을 향상시켜 섬망 환자용 음성합성 기술 기반을 구축한다.

수정:

> **기존 zero-shot voice cloning 및 대화형 AI 모델을 활용하여 별도의 모델 학습 없이 보호자 음성을 재현하고, 환자의 개인적 맥락과 병원 정보를 바탕으로 지남력 메시지와 짧은 양방향 대화를 제공하는 클라우드 기반 시스템을 구축한다.**

연구 포인트는 다음으로 이동한다.

```text
Model Training
↓
System Validation
```

---

# 62. 시스템 평가 항목

```text
Voice similarity
Korean intelligibility
TTS latency

STT accuracy
Turn detection accuracy
Patient-initiated activation accuracy

False activation by TV
False activation by ambient speech

End-to-end response latency

Memory retrieval accuracy
Unsupported-fact rate
Hallucination rate

Hospital-message fidelity

Usability
Guardian onboarding burden
```

---

# 63. 최종 Architecture

```text
                       ┌──────────────────────┐
                       │    Guardian Web      │
                       │ voice / memory input │
                       └──────────┬───────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────┐
│                         Backend                          │
│                                                          │
│ Supabase                                                 │
│ ├── Auth                                                 │
│ ├── Postgres                                             │
│ ├── pgvector                                             │
│ └── Storage                                              │
│                                                          │
│ Conversation Orchestrator                                │
│ ├── Trigger Router                                       │
│ ├── Context Retrieval                                    │
│ ├── Safety Engine                                        │
│ ├── Scheduler                                            │
│ └── LLM                                                  │
│                                                          │
│ Audio Layer                                              │
│ ├── Streaming STT                                        │
│ ├── VAD                                                  │
│ ├── Activation Classifier                                │
│ ├── optional Speaker Verification                        │
│ └── Voice Clone TTS                                      │
└─────────────┬─────────────────────────────┬──────────────┘
              │                             │
              ▼                             ▼
       Patient Flutter               Hospital Web
       Tablet App                    Next.js
              │
              │ microphone
              ▼
       Always-Listening
       State Machine
```

---

# 64. 제품 구현 원칙

이 문서에서 가장 중요한 의사결정만 다시 정리한다.

1. **F5-TTS fine-tuning 하지 않는다.**
2. **모델 경량화 하지 않는다.**
3. **자체 GPU infrastructure 만들지 않는다.**
4. **Hosted voice clone API를 사용한다.**
5. **가족 정보는 RAG로 관리한다.**
6. **병원 정보와 가족 정보를 분리한다.**
7. **병원 메시지를 LLM이 임의 재작성하지 않는다.**
8. **Patient UI에 push-to-talk 버튼을 두지 않는다.**
9. **환자가 먼저 말을 걸 수 있도록 always-listening 구조를 만든다.**
10. **Always listening은 always recording이 아니다.**
11. **IDLE과 ACTIVE의 activation threshold를 다르게 한다.**
12. **TV/ambient speech는 activation classifier로 걸러낸다.**
13. **speaker verification은 hard gate가 아니라 보조 feature다.**
14. **barge-in을 지원한다.**
15. **스케줄링은 agent가 아니라 deterministic scheduler로 시작한다.**
16. **응답은 짧게 유지한다.**
17. **의료 판단은 하지 않는다.**
18. **제품의 핵심 moat는 TTS model이 아니라 memory + context + safe orchestration이다.**

---

# 65. 첫 구현 목표

첫 번째 milestone은 아래 interaction을 성공시키는 것이다.

```text
IDLE

환자:
"수민아?"

SYSTEM
speech detected
→ directed speech
→ conversation opens

가족 목소리:
"응, 왜?"

환자:
"오늘이 며칠이야?"

SYSTEM
hospital/orientation context retrieval

가족 목소리:
"오늘은 9월 15일 화요일이야."

환자:
"제주도 갔을 때 뭐 먹었지?"

SYSTEM
family memory retrieval

가족 목소리:
"흑돼지 먹었잖아.
아빠가 그때 되게 좋아했어."

30~60 sec silence

SESSION CLOSED
→ IDLE
```

**이 흐름이 자연스럽게 동작하는 것이 MVP의 첫 번째 정의다.**
