# 동의 성인 예비실험·음성 주석 프로토콜

작성일: 2026-10-27. [연구 계획](adaptive-care-plan.md)의 실행 절차다. **현재 완료한 것은 도구·빈 양식·합성 selfcheck이며 참여자 실험 결과는 없다.** 실제 환자 모집·자료 입력·병실 녹음은 하지 않는다. 연구용 개인화 점수는 섬망 진단·예방·치료 효과가 아니다.

## 시작 전 확정할 것

- 소속기관에서 사람 대상 연구·음성 자료 수집의 심의/면제 판단이 필요한지 확인한다. 이 문서는 심의 승인이나 최종 동의서가 아니다.
- 성인 본인의 자발적 동의만 사용한다. 거절·중단에 불이익이 없고, 목소리 등록·개인화 평가·녹음 보관·발표 공개를 각각 선택할 수 있게 한다. 실제 음성 복제는 이번 자동화에서 실행하지 않는다.
- 실명·연락처·관계·환자 자료는 분석 CSV에 넣지 않는다. 무작위 가명과 동의 기록의 연결표가 필요하면 분석 데이터와 분리하여 접근을 제한한다.
- 보관 위치, 접근 담당자, 보관 만료일, 철회 창구, 철회 시 원본·파생 자료·모델 삭제 범위와 이미 공개된 집계의 한계를 수집 전에 적는다. 구체 기한·담당자가 비어 있으면 수집을 시작하지 않는다.
- 총 표본, 분석 대상 결과변수, 포함/제외 규칙, 질문 은행·heldout 상황·사전 모델 버전, 조건별 예산과 종료 규칙을 동결한다. 10–20명은 절차 확인용 예비 규모이며 검정력을 보장하지 않는다.

동의 설명 초안에는 다음 내용을 포함한다: “이 연구는 AI가 상황별 표현 선호를 반영하는 정도를 조사합니다. AI는 실제 가족 본인이나 통화 연결이 아닙니다. 의료 상담과 환자 치료를 제공하지 않습니다. 원치 않는 질문은 건너뛰거나 언제든 중단할 수 있습니다. 원본 응답과 음성의 이용·보관·공개 범위는 별도로 선택합니다.” 실제 적용 문구는 기관 검토 후 확정한다.

## 1. 질문 예산별 표현 선호 예측

**주 분석은 동일 참여자의 동결한 응답 은행을 이용한 오프라인 replay**로 설계한다. 고정·무작위·적응형 인터뷰를 같은 사람이 연이어 반복하면 앞 조건의 질문·정답 기억이 뒤 조건에 영향을 준다. 이를 단순한 paired 실험으로 숨기지 않는다.

1. 참여자는 elicitation 상황과 분리된 heldout 상황에 자신의 선호 답변을 고르거나 작성한다. heldout 정답은 선택 알고리즘에 전달하지 않는다. 순서와 수집 시점을 고정하고 정답 피드백을 주지 않는다.
2. 모든 elicitation 항목의 응답과 항목별 실제 응답 시간을 별도 응답 은행에 기록한다. 학습·하이퍼파라미터 조정에 쓴 참여자와 평가 참여자는 분리한다. 본인 평가용 heldout 정답으로 prior를 만들지 않는다.
3. 같은 초기 prior·질문 후보·최대 예산에서 세 알고리즘이 요청한 항목의 응답만 순서대로 공개한다. adaptive가 보지 않은 항목·heldout 정답에 접근하지 않는지 실행 로그로 검사한다. random seed도 수집 전에 고정한다.
4. 미관측 상황의 예측과 동결한 본인 정답의 일치(0/1)를 `preferences.csv`에 기록한다. 질문 수가 같은 조건끼리, 같은 참여자·같은 상황의 차이를 계산한다.
5. 반복 seed는 참여자를 늘리지 않는다. 같은 참여자의 완전한 상황 쌍을 먼저 평균한 뒤 참여자 단위로 resample한다. 주 분석과 seed 민감도 분석을 구분한다.

`timing_kind=replay-answer-sum`의 시간은 선택된 항목의 기록된 응답시간 합이다. 이는 질문 생성·화면 전환·후속 설명 비용을 포함한 실제 인터뷰 경과 시간이 아니므로 “5분이면 학습 완료” 같은 주장에 쓰지 않는다. 실제 총시간을 조사할 후속 실험은 독립 집단 무작위 배정 또는 별도의 동등한 비중복 질문 풀을 사용하고 `timing_kind=live-interview`로 기록한다. 두 시간 종류를 섞은 분석은 도구가 거부한다. 현재 paired 도구는 집단 간 무작위 실험의 효과 추정 도구가 아니다.

배정표의 `strategy_order`는 6순열을 균형 배정한다. 이는 별도 사용성 관찰의 순서표로도 사용할 수 있지만 반복 학습의 carryover를 제거하지는 않는다. replay 평가에서는 세 알고리즘을 독립 초기 상태로 시작한다.

## 2. 블라인드 쌍대 표현 평가

- 같은 상황·같은 사실을 표현한 후보 응답을 조건명을 숨긴 C1/C2/C3 ID로 준비한다. 실제 provider를 실행하지 않은 템플릿 결과는 템플릿이라고 표시한다.
- `coordinator_blind_key.csv`는 배정 담당자만 보관하고 평가자에게 제공하지 않는다. 평가 순서와 좌우 위치를 seed로 고정·무작위화한다.
- 참여자는 자신의 표현 선호에 가까운 후보를 `left`, `right`, `tie`로 선택한다. 평가자가 참여자 본인이 아닌 경우의 기준은 별도로 정하고 결과를 합치지 않는다.
- 분석은 target 후보 승리 1, 무승부 0.5, 패배 0을 참여자별 평균한다. 이는 임상 안정감이나 인격 복제 정답률이 아니다.
- 사실 정확성은 이 선호 평정과 분리한다. 근거 ID·출처·시간·철회 조건을 확인할 평가자 2명에게 조건명을 숨긴 원자적 주장 단위 주석을 맡기고 일치도·불일치 해결 규칙을 별도로 기록한다. 더 가족답다는 점수로 사실 오류를 정당화하지 않는다.

## 3. 친숙한 목소리 × 개인화 내용의 2×2 실험

조건은 `familiar_generic`, `familiar_personalized`, `unfamiliar_generic`, `unfamiliar_personalized`다. 실제로 서로 아는 동의 성인 쌍을 모집해야 친숙함을 검증할 수 있으며, 임의 TTS 목소리에 “가족”이라는 이름만 붙인 것을 친숙 조건으로 간주하지 않는다.

- 4조건의 Williams 순서표를 사용하여 각 위치와 1차 순서효과를 균형화한다. 불완전한 모집 수의 잔여 불균형은 보고한다.
- 동일 시나리오마다 내용 조건의 사실·길이·정보량을 가능한 맞추고, 음량·스피커·출력 경로·음원 포맷을 고정한다. 친숙/낯선 화자의 성별·음색·품질 같은 교란을 기록한다.
- 모든 조건에 동일하게 AI 생성 또는 실제 녹음 여부를 설명한다. 한 조건만 AI임을 숨기거나 가족과 실제 연결되었다고 암시하지 않는다.
- 사전에 정한 1차 결과변수를 선택한다. 준비 양식은 친숙함(`familiarity`), 내용 적합성(`content_fit`), 자연스러움(`naturalness`)의 1–7 정수 평정을 제공한다. 친숙함은 조작 점검이며 임상 결과가 아니다.
- 같은 참여자·같은 상황·같은 결과변수의 4조건이 모두 완료된 세트만 대비에 포함한다. 참여자별 평균한 목소리 주효과, 내용 주효과, 차이의 차이 상호작용과 bootstrap 구간을 보고한다. 다중 결과변수는 탐색적이며 선택적 유의성 보고를 하지 않는다.

## 4. 핵심 정보 보존과 실제 청취 지연

`critical_information.csv`는 `sample_id,category,reference,heard,assessed` 열을 사용한다. 범주는 name/place/time/negation이고 같은 sample·범주에 하나의 구간을 둔다. 사람이 실제 들은 문구를 기록한다. ASR 재전사를 정답으로 쓰지 않는다.

- `assessed=1`에서 청취 문구 공란은 빠진 정보로 센다. 공란/0은 미평가 결측으로 별도 센다.
- Unicode NFC만 정규화하고 띄어쓰기·문장부호를 보존한 핵심 구간 CER와 범주별 정확 일치 오류율을 별도 보고한다. 핵심 구간 CER를 전체 발화 CER로 이름 붙이지 않는다.
- 이름·부정 오류는 낮은 전체 문자 오류와 함께 발생할 수 있으므로 각 범주의 분모·오류 수를 항상 제시한다. 임의 가중치나 자동 임상 안전 판정을 넣지 않는다.

`audio_timestamps.csv`는 외부 녹음의 발화 종료와 첫 들리는 응답을 같은 시간축에 수동 표기한 값이다. 각 recording_id는 한 발화–응답 구간이며 clock_id·출력 경로를 기록한다. `playback_command_seconds`는 로그를 이 녹음 시간축에 정렬한 경우만 입력한다. 명령 시각을 첫 소리로 대체하지 않는다. 마이크·볼륨·연결 경로·네트워크·반복 횟수와 주석 기준은 함께 기록한다. 발화 종료 이전의 소리, 음수·NaN·공란 필수값, 시간축이 다른 시각은 제외 사유를 기록하고 수정 전에는 분석하지 않는다. 도구는 숫자의 정합성만 검사하며 실제 시간축 정렬을 증명하지 않는다.

출력은 관측 p50/p95/min/max와 표본 수다. 여러 장치·출력 경로의 수치는 별도 파일로 분석한다. 이 수치가 환자의 실제 청취·이해 또는 임상적 적절성을 증명하지 않는다.

## 도구 실행과 입력 규칙

준비 명령은 외부 호출·모집·음성 생성 없이 빈 양식과 별도 `synthetic-example/`만 만든다. 참가자 ID는 실제 등록과 무관한 자리표시자다. `heldout-01..04`도 자리표시자이므로 수집 전 실제 동결한 상황과 대응표를 확정한다. 입력 파일과 보고서는 Git 제외 `runs/research/` 아래 보관하고 접근권한을 제한한다.

```bash
python3 scripts/prepare_research_study.py --output runs/research/study-v1 --participants 12 --seed 7
python3 scripts/analyze_research_study.py preferences runs/research/study-v1/preferences.csv --output runs/research/study-v1/preferences-report.json --data-kind consenting-adult
python3 scripts/analyze_research_study.py pairwise runs/research/study-v1/pairwise.csv --key runs/research/study-v1/coordinator_blind_key.csv --output runs/research/study-v1/pairwise-report.json --data-kind consenting-adult
python3 scripts/analyze_research_study.py voice runs/research/study-v1/voice_ratings.csv --output runs/research/study-v1/voice-report.json --data-kind consenting-adult
python3 scripts/analyze_research_study.py audio runs/research/study-v1/audio_timestamps.csv --output runs/research/study-v1/audio-report.json --data-kind consenting-adult
python3 scripts/analyze_research_study.py critical runs/research/study-v1/critical_information.csv --output runs/research/study-v1/critical-report.json --data-kind consenting-adult
```

위 분석 예시는 **수집·주석 완료 후** 사용하는 명령이며 지금 사람 자료가 있다는 뜻이 아니다. selfcheck에는 입력 경로를 `synthetic-example/` 파일로 바꾸고 `--data-kind synthetic`을 지정한다. 합성 수치는 설명용 숫자로 실제 사람·음성·모델의 측정 결과가 아니다.

preferences의 `correct` 공란, pairwise의 `choice` 공란, voice의 `rating` 공란은 대체하지 않는다. 결과에는 관측된 완전 쌍·세트와 결측 수를 보고한다. 양쪽 조건의 행 전체가 파일에서 빠지면 분석 도구는 그 누락을 알 수 없으므로 수집 담당자가 배정표·동결된 상황표와 원자료 행 수를 대조한다. 참여자 0명은 추정값 null, 1명은 인구 수준 bootstrap 구간 null로 보고한다.

보고서는 원문 응답·이름·전사 내용을 재출력하지 않고 집계·방법·입력 SHA256을 기록한다. 파일 해시는 익명화가 아니다. 기존 출력 폴더·보고서는 덮어쓰지 않으며, 수정 분석은 새 경로와 새 버전으로 남긴다. 철회/제외 전후 분모와 계획에서 벗어난 분석을 보고한다.
