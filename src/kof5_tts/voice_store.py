"""복제 등록의 세션·상태·공급자 ID만 저장한다."""

from __future__ import annotations

from contextlib import closing
from dataclasses import dataclass
from datetime import datetime, timezone
import os
from pathlib import Path
import sqlite3
from urllib.parse import urlsplit

import httpx


class StoreUnavailable(RuntimeError):
    """설정이나 저장소 문제를 공급자 응답·접속 정보 없이 전달한다."""


class StoreNotConfigured(StoreUnavailable):
    """No storage backend has been configured yet."""


@dataclass(frozen=True)
class VoiceRecord:
    session_id: str
    reference: str
    state: str
    voice_id: str | None
    updated_at: datetime

    @classmethod
    def from_row(cls, row):
        return cls(
            row["session_id"], row["reference"], row["state"], row["voice_id"],
            datetime.fromisoformat(row["updated_at"]),
        )


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# Hosted table and grants are defined in clinical/voice_sessions.sql.
_SQLITE_SCHEMA = """
CREATE TABLE IF NOT EXISTS favilium_voice_sessions (
    session_id TEXT PRIMARY KEY NOT NULL,
    reference TEXT NOT NULL UNIQUE,
    state TEXT NOT NULL CHECK (state IN ('creating', 'ready', 'verification', 'deleting')),
    voice_id TEXT,
    updated_at TEXT NOT NULL
)
"""


class SQLiteStore:
    def __init__(self, path: Path):
        self.path = path
        try:
            path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            # Create the metadata file with owner-only access regardless of process umask.
            descriptor = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
            os.close(descriptor)
            self._execute(_SQLITE_SCHEMA)
        except OSError:
            raise StoreUnavailable("음성 상태 저장소를 열 수 없습니다.") from None

    def _execute(self, query: str, params: tuple = (), *, fetch: bool = False):
        try:
            with closing(sqlite3.connect(self.path, timeout=5)) as connection:
                connection.row_factory = sqlite3.Row
                with connection:
                    cursor = connection.execute(query, params)
                    return cursor.fetchone() if fetch else cursor.rowcount
        except sqlite3.Error:
            raise StoreUnavailable("음성 상태 저장소에 연결할 수 없습니다.") from None

    def get(self, session: str) -> VoiceRecord | None:
        row = self._execute(
            "SELECT * FROM favilium_voice_sessions WHERE session_id = ?", (session,), fetch=True
        )
        return VoiceRecord.from_row(row) if row is not None else None

    def create(self, session: str, reference: str) -> bool:
        return self._execute(
            """INSERT INTO favilium_voice_sessions (session_id, reference, state, updated_at)
               VALUES (?, ?, 'creating', ?) ON CONFLICT (session_id) DO NOTHING""",
            (session, reference, _now()),
        ) == 1

    def transition(
        self, session: str, reference: str, expected_states: tuple[str, ...],
        state: str, voice_id: str | None,
    ) -> bool:
        placeholders = ",".join("?" for _ in expected_states)
        return self._execute(
            f"""UPDATE favilium_voice_sessions SET state = ?, voice_id = ?, updated_at = ?
                WHERE session_id = ? AND reference = ? AND state IN ({placeholders})""",
            (state, voice_id, _now(), session, reference, *expected_states),
        ) == 1

    def clear(self, session: str, reference: str, expected_states: tuple[str, ...]) -> bool:
        placeholders = ",".join("?" for _ in expected_states)
        return self._execute(
            f"""DELETE FROM favilium_voice_sessions
                WHERE session_id = ? AND reference = ? AND state IN ({placeholders})""",
            (session, reference, *expected_states),
        ) == 1


class SupabaseStore:
    def __init__(self, url: str, key: str):
        self.endpoint = f"{url.rstrip('/')}/rest/v1/favilium_voice_sessions"
        # New sb_secret_ keys belong only in apikey. Legacy service_role is a JWT.
        self.headers = {"apikey": key}
        if not key.startswith("sb_secret_"):
            self.headers["Authorization"] = f"Bearer {key}"

    def _rows(self, method: str, params: dict, *, body: dict | None = None, prefer: str = ""):
        headers = {**self.headers, "Prefer": prefer} if prefer else self.headers
        try:
            response = httpx.request(
                method, self.endpoint, params=params, headers=headers, json=body, timeout=8
            )
            response.raise_for_status()
            rows = response.json()
            if not isinstance(rows, list) or len(rows) > 1:
                raise ValueError
            return rows
        except (httpx.HTTPError, ValueError):
            raise StoreUnavailable("음성 상태 저장소의 요청을 완료할 수 없습니다.") from None

    def get(self, session: str) -> VoiceRecord | None:
        rows = self._rows("GET", {"session_id": f"eq.{session}"})
        if not rows:
            return None
        try:
            return VoiceRecord.from_row(rows[0])
        except (KeyError, TypeError, ValueError):
            raise StoreUnavailable("음성 상태 저장 기록을 읽을 수 없습니다.") from None

    def create(self, session: str, reference: str) -> bool:
        return bool(self._rows(
            "POST", {"on_conflict": "session_id", "select": "session_id"},
            body=dict(session_id=session, reference=reference, state="creating", updated_at=_now()),
            prefer="resolution=ignore-duplicates,return=representation",
        ))

    @staticmethod
    def _conditions(session: str, reference: str, expected_states: tuple[str, ...]) -> dict:
        return {
            "session_id": f"eq.{session}",
            "reference": f"eq.{reference}",
            "state": f"in.({','.join(expected_states)})",
            "select": "session_id",
        }

    def transition(
        self, session: str, reference: str, expected_states: tuple[str, ...],
        state: str, voice_id: str | None,
    ) -> bool:
        return bool(self._rows(
            "PATCH", self._conditions(session, reference, expected_states),
            body=dict(state=state, voice_id=voice_id, updated_at=_now()),
            prefer="return=representation",
        ))

    def clear(self, session: str, reference: str, expected_states: tuple[str, ...]) -> bool:
        return bool(self._rows(
            "DELETE", self._conditions(session, reference, expected_states),
            prefer="return=representation",
        ))


def get_store() -> SQLiteStore | SupabaseStore:
    url = os.environ.get("FAVILIUM_SUPABASE_URL", "").strip()
    key = os.environ.get("FAVILIUM_SUPABASE_SERVICE_KEY", "").strip()
    if url or key or os.getenv("VERCEL"):
        if not url and not key:
            raise StoreNotConfigured("서버에 전용 Supabase 설정이 필요합니다.")
        parts = urlsplit(url)
        if (
            not key or parts.scheme != "https" or not parts.hostname or parts.username
            or parts.password or parts.path.strip("/") or parts.query or parts.fragment
        ):
            raise StoreUnavailable("서버에 전용 Supabase 설정이 필요합니다.")
        return SupabaseStore(url, key)
    path = os.environ.get("FAVILIUM_DB_PATH", "").strip()
    if not path:
        raise StoreNotConfigured("서버에 영구 저장소 경로를 설정해 주세요.")
    if path == ":memory:":
        raise StoreUnavailable("서버에 영구 저장소 경로를 설정해 주세요.")
    return SQLiteStore(Path(path).expanduser())
