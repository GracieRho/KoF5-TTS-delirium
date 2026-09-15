# 프로젝트 문서

`docs/`는 제품, 임상, 연구 및 운영에 관한 문서를 보관합니다. 시스템 구조와 기술 결정은 `architecture/`에서 별도로 관리합니다.

## 권장 문서 구성

현재 제품 방향과 향후 검토 문서를 아래에서 찾을 수 있습니다.

1. `repository-layout.md`: 폴더별 역할과 팀 작업 흐름
2. `contributing.md`: 워크트리, 브랜치, PR과 리뷰 절차
3. [MVP PRD 인덱스](Delirium_Familiar_Voice_MVP_PRD.md): 제품 방향, 기능, 평가와 주제별 문서
4. [환자 시험 전 안전·윤리 게이트](delirium-familiar-voice/07-pre-patient-trial-safety-ethics-gate.md): 실제 환자 시험을 막는 선행 조건
5. [ADR-0001](../architecture/decisions/0001-cloud-first-familiar-voice-mvp.md): 클라우드 중심 전환과 MVP 정책
6. 향후 임상·데이터 거버넌스 문서: 승인된 발화, 동의, 보관 기간, 접근 권한과 폐기 절차
7. 향후 평가·개발 문서: 한국어 음성 품질, 오작동, 지연 시간, 장애 처리와 재현 방법

## 작성 원칙

- 확정된 사실, 가정, 미결정 사항을 구분합니다.
- 환자 대상 문구에는 출처, 버전, 임상 검토 상태를 기록합니다.
- 실험 문서에는 데이터 버전, 모델 버전, 환경과 평가 결과를 남깁니다.
- 환자 식별정보나 실제 임상 데이터는 문서 예시에도 포함하지 않습니다.

현재 프로젝트 개요는 [project-scope.md](project-scope.md), 폴더 구조는 [repository-layout.md](repository-layout.md), 협업 방식은 [contributing.md](contributing.md)에 정리되어 있습니다.
