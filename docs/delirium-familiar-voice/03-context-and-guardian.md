# 22. Memory Architecture

이 제품에서 TTS보다 중요한 부분이다.

구현 현황: 보호자 연결이 검증된 경우의 `family_fact` 저장·읽기와 철회 후 접근 차단은 로컬 합성 자료로 검사했다. 기존 `companion.relevant_facts`는 합성 `Fact` 목록을 검색한다. 새 [합성 iPad 기기 연결 설계](../../architecture/decisions/0006-ipad-anonymous-device-pairing.md)는 병원 담당자가 현재 입원에 연결한 익명 Auth 기기 JWT를 확인하고, `patient_family_turn_context`로 기기 권한과 보호자 DB의 일반 기억 최대 세 건을 매 턴 같이 확인해 FastAPI의 합성 글 응답에 공급한다. 로컬 GoTrue/Data API→FastAPI 모의 공급자 경로와 철회 차단은 통과했다. 실제 iPad·원격 공급자·실제 환자 기억은 사용하지 않았고, 한국어 검색 품질 측정·dynamic follow-up·pgvector/임베딩 모델은 남아 있다.

환자의 memory context는 fine-tuning하지 않고 RAG 구조로 관리한다.

---

# 23. Personal Memory

보호자가 입력.

예시 category:

```text
family
relationship
hometown
occupation
travel
food
hobby
friend
pet
family_event
daily_routine
favorite_story
recent_event
avoid_topic
comfort_topic
```

---

# 24. Clinical / Orientation Facts

병원 staff만 수정 가능.

예:

```text
current_date
current_time
hospital
ward
room
doctor
scheduled_exam
meal
visit_schedule
discharge_plan_if_confirmed
```

---

# 25. Context Namespace 분리

세 가지 context를 분리한다.

```text
hospital_context
family_context
conversation_context
```

절대 한 번에 하나의 비정형 vector pool로 섞지 않는다.

---

# 26. Fact Data Model

예:

```sql
patient_fact

id
patient_id
namespace
category
content
source_type
source_id
sensitivity
valid_from
valid_until
verified_at
embedding
created_at
updated_at
```

예:

```json
{
  "namespace": "family_context",
  "category": "travel",
  "content": "2024년 5월 딸 수민과 제주도 여행을 갔으며 흑돼지를 특히 좋아했다.",
  "source_type": "guardian",
  "source_id": "guardian_123",
  "verified_at": "2026-09-14"
}
```

---

# 27. Retrieval

환자:

```text
"우리 수민이는 요즘 뭐하니?"
```

retrieval:

```text
[relationship]
수민은 환자의 딸

[current]
수민은 회사에 다니고 있음

[shared_memory]
2024년 제주 여행
```

LLM input:

```text
Use only the provided facts.
Do not invent family information.
Keep the response short and conversational.
```

response:

```text
"수민이는 요즘 회사 잘 다니고 있어.
아빠랑 제주도 갔던 얘기도 기억하고 있어."
```

---

# 28. Guardian Onboarding

100문항 고정 설문은 사용하지 않는다.

초기에는 20~30개의 core question만 제공한다.

---

# 29. Core Question Categories

예:

1. 환자와 어떤 관계인가?
2. 평소 환자를 어떻게 부르는가?
3. 환자는 보호자를 어떻게 부르는가?
4. 배우자는 누구인가?
5. 자녀는 누구인가?
6. 손자녀는 누구인가?
7. 고향은 어디인가?
8. 오래 살았던 지역은 어디인가?
9. 이전 직업은 무엇인가?
10. 가장 좋아했던 일은 무엇인가?
11. 좋아하는 음식은?
12. 싫어하는 음식은?
13. 좋아하는 음악은?
14. 좋아하는 가수는?
15. 좋아하는 TV 프로그램은?
16. 최근 함께한 여행은?
17. 가장 기억에 남는 여행은?
18. 가족의 중요한 행사는?
19. 친한 친구는?
20. 반려동물이 있었는가?
21. 평소 하루 일과는?
22. 자주 하는 말은?
23. 환자가 자랑스러워하는 일은?
24. 환자를 안심시키는 이야기는?
25. 피해야 하는 이야기는?
26. 환자가 걱정하는 사람은?
27. 최근 가족에게 있었던 일은?
28. 종교/의례 관련 선호가 있는가?
29. 좋아하는 계절/장소는?
30. 가장 편안해하는 대화 주제는?

---

# 30. Dynamic Follow-Up

고정 100문항 대신 LLM이 후속 질문을 생성한다.

예:

```text
Q. 최근 함께 여행한 곳이 어디인가요?

A. 제주도요.

→ 제주도에서 가장 기억에 남았던 장소가 어디인가요?

A. 성산일출봉이요.

→ 그날 환자분이 특히 좋아했던 음식이나 일이 있었나요?
```

목적:

> 많은 질문이 아니라 **높은 정보 밀도의 autobiographical memory 구축**

---

# 31. Guardian Voice Enrollment

MVP에서는 긴 recording session을 만들지 않는다.

권장:

```text
20~30초 × 3
```

예:

1. 평상시 말투
2. 다정한 말투
3. 천천히 또렷한 말투

총 약 1~2분 이내.

---

# 32. Voice Data Flow

```text
Guardian recording
↓
Voice Clone Provider
↓
voice_id
↓
DB
```

DB:

```json
{
  "guardian_id": "guardian_123",
  "patient_id": "patient_001",
  "provider": "hosted_voice_provider",
  "voice_id": "voice_xyz",
  "consent_verified": true
}
```

---
