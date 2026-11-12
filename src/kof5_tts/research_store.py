"""연구 보관에 별도 동의한 음성만 저장한다. 목록과 파일은 별도로 조회한다."""
from datetime import datetime, timezone
from uuid import uuid4

PAGE_SIZE = 20
CONSENTS = "favilium_research_consents"
SPEECH = "favilium_research_speech"
INDEX = "favilium_research_voice_index"
VOICE_FIELDS = "reference,state,updated_at,consented_at,has_sample,speech_count"
SPEECH_FIELDS = "id,created_at,text_content"

SQLITE_ARCHIVE = """
CREATE TABLE IF NOT EXISTS favilium_research_consents (
    reference TEXT PRIMARY KEY REFERENCES favilium_voice_sessions(reference) ON DELETE CASCADE,
    consented_at TEXT NOT NULL, original BLOB
);
CREATE TABLE IF NOT EXISTS favilium_research_speech (
    id TEXT PRIMARY KEY, reference TEXT NOT NULL REFERENCES favilium_research_consents(reference) ON DELETE CASCADE,
    created_at TEXT NOT NULL, text_content TEXT NOT NULL, audio BLOB NOT NULL
);
CREATE INDEX IF NOT EXISTS favilium_research_speech_voice_date
    ON favilium_research_speech (reference, created_at DESC, id);
CREATE VIEW IF NOT EXISTS favilium_research_voice_index AS
    SELECT v.reference, v.state, v.updated_at, c.consented_at, c.original IS NOT NULL AS has_sample,
           (SELECT count(*) FROM favilium_research_speech s WHERE s.reference=v.reference) AS speech_count
    FROM favilium_voice_sessions v LEFT JOIN favilium_research_consents c USING (reference);
"""


class SQLiteArchive:
    def __init__(self, database):
        self.db = database

    def consent(self, reference, sample=None):
        self.db._execute(
            f"INSERT INTO {CONSENTS} (reference, consented_at, original) VALUES (?, ?, ?) "
            "ON CONFLICT (reference) DO NOTHING",
            (reference, datetime.now(timezone.utc).isoformat(), sample),
        )

    def opted_in(self, reference):
        return self.db._execute(f"SELECT 1 FROM {CONSENTS} WHERE reference=?", (reference,), fetch=True) is not None

    def save_speech(self, reference, text, audio):
        self.db._execute(
            f"INSERT INTO {SPEECH} (id, reference, created_at, text_content, audio) VALUES (?, ?, ?, ?, ?)",
            (str(uuid4()), reference, datetime.now(timezone.utc).isoformat(), text, audio),
        )

    def voices(self, offset, search):
        return self.db._execute(
            f"SELECT {VOICE_FIELDS} FROM {INDEX} WHERE reference LIKE ? ORDER BY updated_at DESC, reference LIMIT ? OFFSET ?",
            (f"%{search}%", PAGE_SIZE + 1, offset), many=True,
        )

    def by_reference(self, reference):
        row = self.db._execute("SELECT * FROM favilium_voice_sessions WHERE reference=?", (reference,), fetch=True)
        return dict(row) if row else None

    def messages(self, reference, offset):
        return self.db._execute(
            f"SELECT {SPEECH_FIELDS} FROM {SPEECH} WHERE reference=? ORDER BY created_at DESC, id LIMIT ? OFFSET ?",
            (reference, PAGE_SIZE + 1, offset), many=True,
        )

    def audio(self, reference, speech_id=None):
        if speech_id is None:
            row = self.db._execute(f"SELECT original FROM {CONSENTS} WHERE reference=?", (reference,), fetch=True)
        else:
            row = self.db._execute(f"SELECT audio FROM {SPEECH} WHERE reference=? AND id=?", (reference, speech_id), fetch=True)
        return row[0] if row else None


class SupabaseArchive:
    def __init__(self, database):
        self.db = database

    def consent(self, reference, sample=None):
        body = {"reference": reference}
        if sample is not None:
            body["original"] = "\\x" + sample.hex()
        self.db._rows("POST", {"on_conflict": "reference", "select": "reference"}, table=CONSENTS,
                      body=body, prefer="resolution=ignore-duplicates,return=representation")

    def opted_in(self, reference):
        return bool(self.db._rows("GET", {"reference": f"eq.{reference}", "select": "reference"}, table=CONSENTS))

    def save_speech(self, reference, text, audio):
        self.db._rows("POST", {"select": "id"}, table=SPEECH, prefer="return=representation",
                      body={"id": str(uuid4()), "reference": reference, "text_content": text, "audio": "\\x" + audio.hex()})

    def voices(self, offset, search):
        params = {"select": VOICE_FIELDS, "order": "updated_at.desc,reference", "offset": offset, "limit": PAGE_SIZE + 1}
        if search:
            params["reference"] = f"like.*{search}*"
        return self.db._rows("GET", params, table=INDEX, max_rows=PAGE_SIZE + 1)

    def by_reference(self, reference):
        rows = self.db._rows("GET", {"reference": f"eq.{reference}"})
        return rows[0] if rows else None

    def messages(self, reference, offset):
        params = {"reference": f"eq.{reference}", "select": SPEECH_FIELDS, "order": "created_at.desc,id",
                  "offset": offset, "limit": PAGE_SIZE + 1}
        return self.db._rows("GET", params, table=SPEECH, max_rows=PAGE_SIZE + 1)

    def audio(self, reference, speech_id=None):
        field, table = ("original", CONSENTS) if speech_id is None else ("audio", SPEECH)
        params = {"reference": f"eq.{reference}", "select": field}
        if speech_id is not None:
            params["id"] = f"eq.{speech_id}"
        rows = self.db._rows("GET", params, table=table)
        if not rows or rows[0][field] is None:
            return None
        return bytes.fromhex(rows[0][field].removeprefix("\\x"))
