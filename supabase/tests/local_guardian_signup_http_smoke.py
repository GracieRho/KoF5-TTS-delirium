"""Signup must not create a patient link or family-memory privilege in the task's local stack."""

from __future__ import annotations

import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    patient = uuid4()
    email = f"kof5-signup-{uuid4().hex}@example.invalid"
    password = secrets.token_urlsafe(24)
    user_id: UUID | None = None
    try:
        status, signup = request(f"{url}/auth/v1/signup", "POST", public,
                                 payload={"email": email, "password": password})
        assert status in (200, 201), f"local guardian signup: {status}"
        user = signup.get("user") or signup
        user_id = UUID(user["id"])
        token = (signup.get("session") or {}).get("access_token")
        if not token:
            status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST", public,
                                      payload={"email": email, "password": password})
            assert status == 200, f"local guardian login after signup: {status}"
            token = session["access_token"]

        sql(f"INSERT INTO kof5.hospital_patient "
            f"(patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref) "
            f"VALUES ('{patient}','TEST-SIGNUP','TEST-{patient}','가상 환자','TEST-STAFF');")
        base = f"{url}/rest/v1"
        status, links = request(f"{base}/guardian_links?select=patient_id", "GET", public, token, schema="api")
        assert status == 200 and links == [], f"unlinked guardian sees no patients: {status}"
        status, facts = request(f"{base}/family_context?select=content", "GET", public, token, schema="api")
        assert status == 200 and facts == [], f"unlinked guardian sees no memories: {status}"
        status, _ = request(f"{base}/family_context", "POST", public, token, schema="api",
                            payload={"patient_id": str(patient), "author_guardian_user_id": str(user_id),
                                     "category": "travel", "content": "연결 없는 가상 기억"})
        assert status in (401, 403), f"unlinked guardian cannot save a memory: {status}"
        print("Local signup → Auth login → no patient link/read/write: PASS")
    finally:
        found = sql(f"SELECT id FROM auth.users WHERE email='{email}';")
        cleanup_id = UUID(found) if found else user_id
        sql(f"DELETE FROM kof5.family_fact WHERE patient_id='{patient}'; "
            f"DELETE FROM kof5.hospital_patient WHERE patient_id='{patient}';")
        if cleanup_id is not None:
            status, _ = request(f"{url}/auth/v1/admin/users/{cleanup_id}", "DELETE", admin)
            assert status in (200, 204), f"local signup account cleanup: {status}"


if __name__ == "__main__":
    main()
