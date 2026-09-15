# 22. Memory Architecture

이 제품에서 TTS보다 중요한 부분이다.

구현 현황: 보호자 연결이 검증된 경우의 `family_fact` 저장·읽기와 철회 후 접근 차단은 로컬 합성 자료로 검사했다. 기존 `companion.relevant_facts`와 문자열 포함 검색은 서로 다른 표현의 한국어 질문을 찾지 못할 수 있다. 고정 합성 환자에는 별도 [pgvector 가족 기억 색인](../../supabase/migrations/20260916123000_synthetic_family_embedding_rag.sql)을 추가했다. 보호자 화면은 일반 기억이 저장된 뒤 실제 `fact_id`를 확인했을 때만 서버 색인을 요청하고, 서버는 보호자 JWT·현재 연결·사실을 확인한 다음 임시 모델 `text-embedding-3-small`로 색인한다. 결속된 iPad 기기 JWT의 [단일 의미 검색 RPC](../../supabase/migrations/20260916123000_synthetic_family_embedding_rag.sql)는 현재 입원·동의·보호자 연결과 일반 가족 기억을 한 DB 조회에서 대조해 최대 세 건을 반환한다. 로컬 pgTAP 37개와 GoTrue/Data API의 색인·검색·수정·철회 검사가 통과했다. 실제 한국어 임베딩 정확도, 임상 내용 검토, 후속 질문 생성 품질, 실제 iPad·원격 공급자·환자 기억은 검증되지 않았다.

별도 **고정 합성 환자 내부 시험**에서 보호자는 저장된 일반 기억 한 건을 골라 후속 질문을 요청할 수 있다. 서버는 보호자 JWT와 현재 연결·기억을 다시 확인한 뒤 시험용 [Responses API](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)에 그 기억 원문을 보내며 `store=false`를 요청한다. 모델 출력은 원문에 실제로 있는 짧은 구절과 제한된 질문 초점의 JSON만 받아 서버가 한국어 질문을 조립한다. 반환 직전에 보호자 연결과 원문을 다시 확인한다. 질문은 보호자 화면에 검토용으로만 보이고 새 사실로 자동 저장되지 않는다. 로컬 모의 API와 웹 경합 검사만 통과했다. 실제 공급자 호출·한국어 질문 품질, 공급자 보존 계약과 실제 가족 정보 처리는 검증되지 않았다.

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
