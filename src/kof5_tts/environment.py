"""로컬 서버의 공급자 키를 읽되 관리 토큰은 주입하지 않는다."""

import os
from pathlib import Path


def read_env_value(path: Path, key: str) -> str | None:
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        name, separator, raw_value = line.partition("=")
        if not separator or name.strip() != key:
            continue
        value = raw_value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        return value
    return None


SERVER_KEYS = ("OPENAI_API_KEY", "ELEVENLABS_API_KEY", "DEEPGRAM_API_KEY", "OPENROUTER_API_KEY")


def load_server_env(root: Path | None = None, *, keys: tuple[str, ...] = SERVER_KEYS) -> None:
    if not set(keys) <= set(SERVER_KEYS):
        raise ValueError("관리 토큰은 서버 환경에 주입할 수 없습니다.")
    if os.environ.get("VERCEL"):
        return
    root = root if root is not None else Path(__file__).resolve().parents[2]
    roots = [root]
    if root.parent.name == ".worktrees":
        roots.append(root.parent.parent)
    for directory in roots:
        path = directory / ".env"
        if not path.is_file():
            continue
        for key in keys:
            value = read_env_value(path, key)
            if value:
                os.environ.setdefault(key, value)
