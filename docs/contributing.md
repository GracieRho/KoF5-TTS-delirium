# 협업 및 PR 방식

이 프로젝트는 작업별 Git 워크트리와 PR을 기본으로 사용합니다. 새 구현은 최신 `origin/main`에서 작업별 워크트리로 시작합니다. 사용자가 명시적으로 요청한 직접 작업과 작은 문서 유지보수는 상위 작업 규칙의 예외를 따릅니다.

## 1. 작업 폴더 만들기

저장소 루트에서 최신 원격 상태를 받은 뒤 작업별 브랜치와 워크트리를 만듭니다.

```bash
git fetch origin main
git worktree add -b feat/<task-name> .worktrees/<task-name> origin/main
cd .worktrees/<task-name>
```

문서, 버그 수정, 초기 설정과 실험은 각각 `docs/`, `fix/`, `chore/`, `experiment/` 접두사를 사용할 수 있습니다. 한 워크트리에는 한 가지 목적의 변경만 담습니다.

## 2. 작업 및 검증

- 원본 데이터와 체크포인트가 Git에 섞이지 않았는지 확인합니다.
- 코드·설정 구조가 바뀌면 아키텍처 문서를 다시 생성합니다.
- 가장 작은 관련 테스트를 먼저 실행한 뒤 공통 검증을 수행합니다.

```bash
python3 scripts/generate_architecture.py
python3 scripts/generate_architecture.py --check
python3 -m unittest scripts/test_generate_architecture.py
git diff --check
git status --short
```

## 3. PR 만들기

작업 브랜치를 원격에 올리고 `main` 대상 PR을 만듭니다. PR에는 변경 이유, 검증 결과, 데이터·체크포인트 영향과 남은 위험을 적습니다.

리뷰어는 최소한 다음을 확인합니다.

- 실제 환자 데이터나 비밀정보가 포함되지 않았는가
- 클라우드 제공업체·데이터 처리·안전 게이트에 영향이 있는가
- 기존 연구용 체크포인트를 포함한 경우에만 기준 모델과 설정·저장 방식을 추적할 수 있는가
- 자동 생성 아키텍처 문서가 현재 코드·설정과 일치하는가
- 임상 문구나 환자 대상 동작 변경에 검토가 필요한가

## 4. 병합

- 최소 1명의 승인을 권장합니다.
- 오래된 승인은 새 변경이 푸시되면 다시 확인합니다.
- 리뷰 대화를 모두 해결한 뒤 병합합니다.
- 기본적으로 squash merge를 사용해 작업 단위를 하나의 명확한 커밋으로 남깁니다.
- 강제 푸시와 `main` 삭제는 허용하지 않습니다.
- 병합이 끝나면 `.github/workflows/delete-merged-branch.yml`이 동일 저장소에서 생성된 원격 작업 브랜치를 자동 삭제합니다.
- 자동 삭제는 fork의 브랜치에는 접근하지 않으며, `main`은 삭제 대상이 아닙니다.
- GitHub Actions는 각 개발자의 로컬 파일을 삭제할 수 없으므로 로컬 워크트리와 브랜치는 병합 여부와 dirty 상태를 확인한 뒤 별도로 정리합니다.

## 직접 작업 예외

사용자가 `main`에서의 직접 작업을 명시한 경우와 작은 문서 유지보수는 상위 작업 규칙에 따라 진행할 수 있습니다. 새 기능 구현은 별도 요청이 없는 한 작업별 워크트리·PR 흐름을 따릅니다.

## 권장 GitHub `main` 보호 규칙

저장소 관리자 계정에서 다음을 설정합니다.

- Require a pull request before merging: 켜기
- Required approvals: 1
- Dismiss stale pull request approvals: 켜기
- Require conversation resolution before merging: 켜기
- Do not allow bypassing the above settings: 켜기
- Allow force pushes: 끄기
- Allow deletions: 끄기

CI가 추가되면 신뢰할 수 있는 테스트를 required status check로 지정합니다. 아직 CI가 없으므로 존재하지 않는 체크를 미리 필수로 걸어 병합을 막지 않습니다.
