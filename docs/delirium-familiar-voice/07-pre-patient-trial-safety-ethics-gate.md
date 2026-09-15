# Pre-Patient Trial Safety & Ethics Gate

> **문서 목적**\
> 본 문서는 섬망 환자를 위한 가족 음성 기반 대화 시스템의 실제 환자 대상 시험에 앞서 반드시 확정해야 하는 안전·윤리·운영 요구사항을 정의한다.
>
> 이 문서는 기능 PRD가 아니라 **실제 환자 시험을 시작하기 위한 Blocking Gate 문서**다.
>
> 아래 조건 중 하나라도 충족되지 않으면 실제 환자 대상 시험을 진행하지 않는다.

---

# 1. 핵심 원칙

본 제품은 다음 특성을 동시에 가진다.

- 인지적으로 취약할 수 있는 환자를 대상으로 함
- 보호자 음성을 합성해 사용함
- 병실 환경에서 상시 음성 감지를 수행함
- 환자의 발화를 기반으로 대화를 시작함
- 병원 정보 및 개인적 가족 정보를 활용함
- 위험 발화를 감지할 가능성이 있음

따라서 일반적인 음성 AI보다 더 높은 수준의 다음 요구사항이 필요하다.

```text
Identity Transparency
Consent
Ambient Audio Privacy
Clinical Escalation Safety
```

이 네 가지는 실제 환자 대상 시험 전 반드시 확정해야 한다.

---

# 2. 제품 목표의 표현 수정

## 기존 표현

> 환자가 실제 가족과 통화하고 있다고 착각하게 한다.

이 표현은 실제 환자 시험 단계에서는 사용하지 않는다.

특히 섬망 환자는 현실 판단과 지남력이 저하될 수 있기 때문에 시스템이 의도적으로 자신의 정체성을 가족 본인으로 오인시키도록 설계하는 것은 안전성과 연구 윤리 측면에서 문제가 될 수 있다.

---

## 수정 표현

> **환자가 복잡한 조작 없이, 친숙한 가족 음성과 개인적 기억을 통해 가족과 이야기할 때와 유사한 자연스러운 conversational presence를 경험하게 한다.**

즉 목표는:

```text
Deception
X

Familiarity
O
```

이다.

---

# 3. Gate 1 — Identity Transparency

## 3.1 기본 원칙

시스템은 보호자의 목소리를 재현할 수 있지만, 자신이 실제 보호자 본인이라고 적극적으로 거짓 주장하지 않는다.

환자 시험 전 다음 사실을 가능한 범위에서 명확히 고지한다.

> 이 시스템은 가족의 목소리를 바탕으로 생성된 AI 음성을 사용하며 실제 가족과 연결된 전화가 아니다.

---

## 3.2 일반 대화 중 UX

매 응답마다 반복적으로 다음을 말할 필요는 없다.

```text
"저는 AI입니다."
```

이는 사용성을 크게 해칠 수 있다.

대신 다음 원칙을 따른다.

```text
시험 참여 전 명확한 사전 고지

+

화면 또는 환경에 비침습적인 AI 사용 표시

+

환자가 정체성을 직접 질문하면 사실대로 답변

+

시스템이 실제 가족과 연결되어 있다는 거짓 정보를 먼저 생성하지 않음
```

---

## 3.3 허용되는 대화 예시

환자:

```text
"수민아?"
```

시스템:

```text
"응, 왜?"
```

이 정도의 자연스러운 대화는 허용할 수 있다.

---

## 3.4 금지되는 대화 예시

시스템이 다음과 같은 거짓 현실 정보를 생성하면 안 된다.

```text
"응, 나 진짜 수민이야."

"내가 지금 밖에서 전화하고 있어."

"지금 실제로 너랑 전화 중이야."
```

---

## 3.5 Identity Question Fallback

환자:

```text
"너 진짜 수민이냐?"
```

응답:

```text
"수민이 목소리를 바탕으로 제가 함께 이야기하고 있어요."
```

또는 연구 및 임상 프로토콜에 맞는 equivalent response를 사용한다.

핵심은:

```text
Identity question
→ truthful response
```

다.

---

# 4. Gate 2 — Consent Architecture

본 시스템에서는 하나의 동의서로 모든 사항을 처리하지 않는다.

최소한 다음 세 가지 동의를 분리해서 생각한다.

---

## 4.1 Patient Participation Consent

환자의 연구 참여 동의.

포함해야 할 내용:

- 연구 목적
- 시스템 작동 방식
- AI 음성 사용
- 가족 음성 사용
- 병실 음성 처리
- 대화 transcript 저장 여부
- 잠재적 위험
- 참여 철회 방법
- 기존 진료와의 관계

---

## 4.2 Guardian Voice Cloning Consent

보호자의 음성을 합성하기 위한 별도 동의.

포함:

- voice sample 사용 목적
- voice cloning 여부
- 사용 범위
- 저장 기간
- 삭제 방법
- 제3자 provider 사용 여부
- provider의 데이터 처리 정책
- 연구 종료 후 삭제 정책

---

## 4.3 Ambient Audio Processing Notice / Consent

병실에서 음성 감지를 수행하기 때문에 환자 외 주변인의 음성이 일시적으로 처리될 가능성이 있다.

따라서 다음 사항을 명확히 해야 한다.

```text
무엇을 듣는가
무엇을 서버로 전송하는가
무엇을 저장하는가
무엇을 즉시 폐기하는가
누가 접근할 수 있는가
얼마나 오래 보관하는가
```

---

# 5. 섬망 환자의 동의 문제

섬망 환자는 의사결정 능력이 시간에 따라 변동할 수 있다.

따라서 단순히 다음처럼 처리해서는 안 된다.

```text
보호자 동의 완료
→ 무조건 사용
```

---

# 6. 권장 Consent Flow

```text
환자가 충분한 동의 능력을 가짐
        ↓
Patient informed consent

환자의 동의 능력이 불충분함
        ↓
IRB protocol에 따른 대리인 동의
        ↓
환자가 이해 가능한 수준에서 assent 시도

환자가 명확히 거부함
        ↓
사용 중단
```

---

# 7. Patient Dissent

환자의 거부는 별도의 safety event로 처리한다.

예:

```text
"이거 꺼."

"말 걸지 마."

"싫어."

"그만해."
```

이러한 표현이 반복되거나 명확하게 확인되면:

```text
patient_dissent = true
```

로 처리한다.

후속 동작:

```text
ACTIVE
↓
conversation stop
↓
scheduled proactive conversation pause
↓
staff / study operator review
```

보호자의 동의가 있다고 해서 환자의 명백한 거부를 무시하지 않는다.

---

# 8. Gate 3 — Ambient Audio Privacy

핵심 원칙:

```text
Always Listening
≠
Always Recording
```

---

# 9. 권장 Audio Pipeline

```text
Tablet Microphone
↓
On-device VAD
↓
Speech detected
↓
Ephemeral Rolling Buffer
↓
STT / activation processing
↓
DIRECTED or AMBIENT
```

분기:

```text
AMBIENT
↓
즉시 폐기
↓
audio 저장 X
↓
transcript 저장 X
```

```text
DIRECTED
↓
conversation session
↓
필요한 transcript만 저장
```

---

# 10. Idle Audio Policy

IDLE 상태에서는 병실 음성을 장기간 저장하지 않는다.

태블릿에는 최근 몇 초 수준의 temporary rolling buffer만 유지한다.

예:

```text
[t-5]
[t-4]
[t-3]
[t-2]
[t-1]
[now]
```

speech detection 시 직전 약 1~2초를 포함해 STT 처리한다.

목적:

- 첫 음절 손실 방지
- privacy 보호
- 병실 주변 음성의 불필요한 저장 방지

---

# 11. On-Device VAD

가능하면 VAD는 기기에서 처리한다.

즉:

```text
병실 음성이 존재한다
≠
항상 cloud로 audio stream을 보낸다
```

권장:

```text
Idle
↓
Local VAD
↓
Speech candidate detected
↓
필요한 audio만 후속 처리
```

---

# 12. Ambient Speech Handling

예:

```text
TV 뉴스
간호사 간 대화
보호자와 의료진 대화
옆 병상 환자 음성
```

이러한 음성은 activation 판단 과정에서 일시적으로 처리될 수 있다.

그러나 대화 개시 대상으로 판단되지 않은 경우:

```text
audio delete
transcript delete
conversation log 생성 X
```

를 기본 정책으로 한다.

---

# 13. 연구계획서에 명시할 내용

다음과 같은 내용을 명시한다.

> 병실 내 주변 발화가 환자 발화 감지를 위해 일시적으로 처리될 수 있으나, 대화 개시 대상으로 판정되지 않은 음성은 저장하지 않는다.

실제 문구는 기관 IRB 및 법률 검토에 따라 수정한다.

---

# 14. Cloud Provider Data Review

실제 환자 데이터를 사용하기 전 다음을 확인한다.

## STT Provider

- audio retention
- transcript retention
- training usage
- logging policy
- data residency
- deletion
- enterprise privacy option

## TTS Provider

- guardian voice sample retention
- cloned voice retention
- voice deletion
- training usage
- impersonation safeguards
- enterprise agreement

## LLM Provider

- prompt retention
- transcript retention
- training usage
- healthcare / sensitive-data policy
- data residency
- deletion

---

# 15. Gate 4 — Clinical Escalation Safety

현재 MVP의 가장 중요한 safety concern 중 하나다.

환자가 다음과 같은 발화를 할 수 있다.

```text
"가슴이 아파."

"숨을 못 쉬겠어."

"넘어졌어."

"너무 어지러워."

"살려줘."
```

시스템이 이를 감지할 수 있더라도 초기 patient pilot에서는 **의료진 호출을 보장하는 시스템으로 취급하지 않는다.**

---

# 16. 초기 Pilot 원칙

시스템은 기존 nurse-call system을 대체하지 않는다.

권장 응답:

```text
"의료진의 도움이 필요한 상황일 수 있어요.
기존 호출 버튼을 이용해주세요."
```

동시에 가능하다면 staff dashboard에 보조 alert를 생성할 수 있다.

하지만 이를:

```text
Emergency Call
```

또는:

```text
Nurse Call Replacement
```

로 표현하면 안 된다.

---

# 17. 금지되는 Failure Pattern

다음 구조는 사용하면 안 된다.

```text
Patient:
"숨이 너무 차."

↓

POST /alert

↓

Server: 200 OK

↓

Assistant:
"의료진에게 알려드렸어요."
```

HTTP request가 성공했다는 것은 의료진이 실제로 확인했다는 의미가 아니다.

---

# 18. Closed-Loop Alert Model

향후 의료진 호출 기능을 개발한다면 반드시 상태 머신을 사용한다.

```text
DETECTED
↓
ALERT_CREATED
↓
DELIVERED
↓
ACKNOWLEDGED
↓
RESOLVED
```

---

# 19. Alert State Definition

## DETECTED

위험 가능성이 있는 발화가 감지됨.

---

## ALERT_CREATED

backend에 alert record가 생성됨.

---

## DELIVERED

병원 dashboard 또는 지정 시스템까지 전달된 것이 확인됨.

---

## ACKNOWLEDGED

실제 의료진이 alert를 확인함.

---

## RESOLVED

의료진이 후속 조치를 완료했음을 표시.

---

# 20. Failure Path

다음 상태도 반드시 존재해야 한다.

```text
ALERT_CREATED
↓
DELIVERY_TIMEOUT
↓
FAILED
```

또는:

```text
DELIVERED
↓
NO_ACK
↓
ESCALATION_TIMEOUT
```

---

# 21. Patient-Facing Failure Message

확인이 되지 않은 상태에서:

```text
"의료진에게 전달했습니다."
```

라고 말하면 안 된다.

대신:

```text
"의료진에게 전달됐는지 확인할 수 없어요.
기존 호출 버튼을 이용해주세요."
```

같은 사실 기반 응답을 사용한다.

---

# 22. Pilot 단계별 Alert 범위

## Phase A — Internal

```text
위험 발화 감지
→ log
```

---

## Phase B — Healthy Volunteer

```text
위험 발화 감지
→ simulated alert
```

---

## Phase C — Supervised Patient Pilot

```text
위험 발화 감지
→ staff dashboard auxiliary alert
→ 기존 nurse-call 사용 안내
```

---

## Phase D — Future Clinical Integration

```text
위험 발화 감지
→ hospital system
→ delivered
→ acknowledged
→ escalation
→ failure handling
```

Phase D는 별도의 integration 및 safety validation 없이는 진행하지 않는다.

---

# 23. Pre-Patient Trial Gate

실제 환자 대상 시험 전 반드시 다음 네 가지를 완료한다.

| Gate | 완료 조건 |
|---|---|
| Identity | AI 및 voice cloning 사용 사실 고지 방식 확정 |
| Consent | 환자·대리인·보호자 동의 및 환자 거부 protocol 확정 |
| Ambient Audio | 처리·전송·저장·폐기 data flow 확정 |
| Clinical Escalation | alert 성공·ACK·실패·fallback 정의 |

---

# 24. Blocking Rule

```text
Identity = incomplete
OR
Consent = incomplete
OR
Ambient Audio = incomplete
OR
Clinical Escalation = incomplete

↓

REAL PATIENT TEST = BLOCKED
```

---

# 25. 권장 검증 순서

```text
Synthetic / Team Test
        ↓
Functional MVP
        ↓
Pre-Patient Safety Review
        ├─ Identity
        ├─ Consent
        ├─ Ambient Audio
        ├─ Clinical Escalation
        └─ IRB / institutional review
        ↓
Healthy Volunteer Test
        ↓
Supervised Patient Pilot
        ↓
Clinical Validation
```

---

# 26. Patient Trial 전 확정할 Deliverables

## Identity

- participant explanation wording
- identity question fallback
- AI indication policy
- forbidden deception examples

## Consent

- patient consent form
- proxy consent protocol
- guardian voice cloning consent
- withdrawal procedure
- patient dissent handling

## Ambient Audio

- end-to-end data-flow diagram
- rolling buffer duration
- cloud transmission rules
- storage policy
- deletion policy
- provider data-retention review

## Clinical Escalation

- risk utterance definition
- alert state machine
- delivery confirmation
- staff acknowledgment mechanism
- timeout
- failure message
- fallback to existing nurse-call

---

# 27. Recommended Safety Events

backend에는 최소 다음 event를 남긴다.

```text
patient_dissent
identity_question
ambient_audio_discarded
high_risk_utterance_detected
alert_created
alert_delivered
alert_acknowledged
alert_failed
conversation_force_stopped
```

개인정보를 최소화하는 범위에서 audit 가능해야 한다.

---

# 28. 핵심 제품 원칙

최종적으로 다음 원칙을 유지한다.

1. 가족 목소리를 활용하되 실제 가족 본인이라고 거짓 주장하지 않는다.
2. natural conversation은 유지하되 identity 질문에는 사실대로 답한다.
3. 환자 대상 시험 전에 informed consent 구조를 확정한다.
4. 환자의 명시적 거부를 별도 safety signal로 취급한다.
5. 보호자 voice cloning 동의를 별도로 받는다.
6. Always Listening을 Always Recording으로 구현하지 않는다.
7. ambient audio는 최소한으로 처리하고 불필요한 데이터는 저장하지 않는다.
8. 가능하면 VAD를 device에서 처리한다.
9. 의료진 호출 기능은 초기 pilot에서 기존 nurse-call을 대체하지 않는다.
10. alert 생성과 실제 의료진 확인을 구분한다.
11. confirmation 없는 상태에서 "의료진에게 알렸다"고 말하지 않는다.
12. 실제 환자 시험 전 네 개의 Safety Gate를 모두 통과한다.

---

# 29. 한 줄 결론

> **이 제품의 환자 대상 시험은 기능 구현 완료만으로 시작하지 않는다. Identity, Consent, Ambient Audio Privacy, Clinical Escalation의 네 가지 safety gate가 모두 확정된 뒤에만 시작한다.**
