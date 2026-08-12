# 프로젝트 문서

`docs/`는 제품, 임상, 연구 및 운영에 관한 문서를 보관합니다. 시스템 구조와 기술 결정은 `architecture/`에서 별도로 관리합니다.

## 권장 문서 구성

상세 요구사항이 준비되면 아래 문서를 순서대로 추가합니다.

1. `repository-layout.md`: 폴더별 역할과 팀 작업 흐름
2. `product-requirements.md`: 해결하려는 문제, 사용자, 사용 시나리오, 범위
3. `clinical-requirements.md`: 임상 콘텐츠, 금기·주의사항, 검토 및 승인 절차
4. `data-governance.md`: 동의, 비식별화, 보관 기간, 접근 권한, 폐기 절차
5. `model-evaluation.md`: 한국어 TTS 품질, 명료도, 안전 문구 보존 평가
6. `device-requirements.md`: 목표 IoT 기기의 CPU, 메모리, 저장공간, 전력, 지연 시간
7. `development.md`: 개발 환경, 실행, 테스트 및 재현 방법

## 작성 원칙

- 확정된 사실, 가정, 미결정 사항을 구분합니다.
- 환자 대상 문구에는 출처, 버전, 임상 검토 상태를 기록합니다.
- 실험 문서에는 데이터 버전, 모델 버전, 환경과 평가 결과를 남깁니다.
- 환자 식별정보나 실제 임상 데이터는 문서 예시에도 포함하지 않습니다.

현재 프로젝트 개요는 [project-scope.md](project-scope.md), 폴더 구조는 [repository-layout.md](repository-layout.md)에 정리되어 있습니다.
