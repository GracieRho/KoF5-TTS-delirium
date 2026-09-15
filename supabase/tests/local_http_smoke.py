"""One synthetic Supabase Auth→Data API smoke check against the task's local stack."""

from __future__ import annotations

import json
from pathlib import Path
import secrets
import subprocess
import tomllib
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from uuid import UUID, uuid4

ROOT = Path(__file__).resolve().parents[2]
PROJECT = "kof5-familiar-voice-mvp"


def local_keys() -> dict[str, str]:
    result = subprocess.run(
        ["supabase", "status", "-o", "env"], check=True, capture_output=True, text=True,
        cwd=ROOT,
    )
    return {
        name: value.strip('"')
        for line in result.stdout.splitlines()
        if "=" in line
        for name, value in [line.split("=", 1)]
    }


def verify_local_target(keys: dict[str, str]) -> None:
    config = tomllib.loads((ROOT / "supabase/config.toml").read_text())
    api = urlparse(keys["API_URL"])
    if (config["project_id"] != PROJECT or api.scheme != "http"
            or api.hostname != "127.0.0.1" or api.port != config["api"]["port"]
            or api.port != 54341):
        raise ValueError("작업 전용 로컬 Supabase API 주소가 아닙니다")


def request(url: str, method: str, key: str, token: str | None = None,
            payload: dict | None = None, schema: str | None = None) -> tuple[int, object]:
    headers = {"apikey": key, "Authorization": f"Bearer {token or key}"}
    if schema:
        headers["Content-Profile" if method == "POST" else "Accept-Profile"] = schema
    body = None if payload is None else json.dumps(payload).encode()
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = Request(url, data=body, headers=headers, method=method)
    try:
        response = urlopen(req, timeout=10)
    except HTTPError as error:
        response = error
    with response:
        data = response.read()
        return response.status, json.loads(data) if data else None


def sql(command: str) -> str:
    result = subprocess.run(
        ["docker", "exec", "supabase_db_kof5-familiar-voice-mvp", "psql",
         "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-qAt", "-c", command],
        check=True, capture_output=True, text=True,
    )
    return result.stdout.strip()


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url = keys["API_URL"]
    public = keys["ANON_KEY"]
    admin = keys["SERVICE_ROLE_KEY"]
    patient = uuid4()
    user_id: UUID | None = None
    password = secrets.token_urlsafe(24)
    email = f"kof5-local-{uuid4().hex}@example.invalid"

    try:
        status, user = request(
            f"{url}/auth/v1/admin/users", "POST", admin,
            payload={"email": email, "password": password, "email_confirm": True},
        )
        assert status in (200, 201), f"local admin create: {status}"
        user_id = UUID(user["id"])

        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
            VALUES ('{patient}', 'TEST-HTTP', 'TEST-HTTP-{patient}', '가상 환자', 'TEST-STAFF');
            INSERT INTO kof5.patient_guardian_link
                (patient_id, guardian_user_id, relationship, access_status,
                 effective_at, verified_by_staff_ref, verified_at)
            VALUES ('{patient}', '{user_id}', '가상 보호자', 'verified',
                    now() - interval '1 minute', 'TEST-VERIFY', now());
        """)

        status, session = request(
            f"{url}/auth/v1/token?grant_type=password", "POST", public,
            payload={"email": email, "password": password},
        )
        assert status == 200, f"local password login: {status}"
        token = session["access_token"]
        base = f"{url}/rest/v1"
        status, links = request(f"{base}/guardian_links?select=patient_id", "GET", public, token, schema="api")
        assert status == 200 and links == [{"patient_id": str(patient)}], f"verified link read: {status}"
        status, _ = request(
            f"{base}/family_context", "POST", public, token,
            payload={"patient_id": str(patient), "author_guardian_user_id": str(user_id),
                     "category": "travel", "content": "가상 가족 여행 기억"},
            schema="api",
        )
        assert status == 201, f"verified family write: {status}"
        status, facts = request(f"{base}/family_context?select=content", "GET", public, token, schema="api")
        assert status == 200 and facts == [{"content": "가상 가족 여행 기억"}], f"family read: {status}"

        sql(f"UPDATE kof5.patient_guardian_link SET access_status='revoked', revoked_at=now() "
            f"WHERE patient_id='{patient}' AND guardian_user_id='{user_id}';")
        status, facts = request(f"{base}/family_context?select=content", "GET", public, token, schema="api")
        assert status == 200 and facts == [], f"revoked family read: {status}"
        status, _ = request(
            f"{base}/family_context", "POST", public, token,
            payload={"patient_id": str(patient), "author_guardian_user_id": str(user_id),
                     "category": "food", "content": "철회 후 기억"}, schema="api",
        )
        assert status in (401, 403), f"revoked family write: {status}"
        status, _ = request(f"{base}/family_context?select=content", "GET", public, schema="api")
        assert status in (401, 403), f"anonymous family read: {status}"
        print("Local Auth login → Data API family read/write → revocation/anon deny: PASS")
    finally:
        found = sql(f"SELECT id FROM auth.users WHERE email='{email}';")
        cleanup_id = UUID(found) if found else user_id
        if cleanup_id is not None:
            try:
                sql(f"DELETE FROM kof5.family_fact WHERE patient_id='{patient}'; "
                    f"DELETE FROM kof5.patient_guardian_link WHERE patient_id='{patient}'; "
                    f"DELETE FROM kof5.hospital_patient WHERE patient_id='{patient}';")
            finally:
                status, _ = request(f"{url}/auth/v1/admin/users/{cleanup_id}", "DELETE", admin)
                assert status in (200, 204), f"local synthetic user cleanup: {status}"


if __name__ == "__main__":
    main()
