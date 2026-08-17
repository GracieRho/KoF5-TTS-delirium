"""저장소를 설치하지 않고 scripts 진입점을 실행하기 위한 경로 설정."""

from __future__ import annotations

import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = REPOSITORY_ROOT / "src"
if str(SOURCE_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_ROOT))


def env_search_roots() -> tuple[Path, ...]:
    roots = [REPOSITORY_ROOT]
    parts = REPOSITORY_ROOT.parts
    if ".worktrees" in parts:
        roots.append(Path(*parts[: parts.index(".worktrees")]))
    return tuple(roots)
