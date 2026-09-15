"""Synthetic staff Auth→PostgREST read/revocation check for the task-owned local stack."""

from __future__ import annotations

import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    email = f"kof5-staff-{uuid4().hex}@example.invalid"
    password = secrets.token_urlsafe(24)
    patient, other, encounter, other_encounter, membership = (uuid4() for _ in range(5))
    user_id: UUID | None = None
    try:
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password, "email_confirm": True})
        assert status in (200, 201), f"local staff create: {status}"
        user_id = UUID(user["id"])
        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
            VALUES ('{patient}', 'TEST-STAFF-H1', 'TEST-{patient}', '가상 환자 A', 'TEST-STAFF'),
                   ('{other}', 'TEST-STAFF-H2', 'TEST-{other}', '가상 환자 B', 'TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
            VALUES ('{encounter}', '{patient}', 'TEST-{encounter}', 'in_progress', now()),
                   ('{other_encounter}', '{other}', 'TEST-{other_encounter}', 'in_progress', now());
            INSERT INTO kof5.hospital_staff_membership
                (membership_id, auth_user_id, hospital_ref, product_role, status,
                 effective_at, verified_by_staff_ref, verified_at)
            VALUES ('{membership}', '{user_id}', 'TEST-STAFF-H1', 'registrar', 'verified',
                    now() - interval '1 minute', 'TEST-VERIFY', now());
            INSERT INTO kof5.hospital_context_fact
                (patient_id, encounter_id, category, content, source_staff_ref,
                 approved_by_staff_ref, verified_at, status)
            VALUES ('{patient}', '{encounter}', 'room', '가상 병실 A', 'TEST-STAFF',
                    'TEST-APPROVER', now() - interval '1 minute', 'approved'),
                   ('{other}', '{other_encounter}', 'room', '가상 병실 B', 'TEST-STAFF',
                    'TEST-APPROVER', now() - interval '1 minute', 'approved');
            INSERT INTO kof5.hospital_message
                (patient_id, encounter_id, approved_text, approved_by_staff_ref, approved_at, due_at)
            VALUES ('{patient}', '{encounter}', '가상 예약 메시지 A', 'TEST-APPROVER', now(), now()),
                   ('{other}', '{other_encounter}', '가상 예약 메시지 B', 'TEST-APPROVER', now(), now());
        """)
        status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST", public,
                                  payload={"email": email, "password": password})
        assert status == 200, f"local staff login: {status}"
        token = session["access_token"]
        base = f"{url}/rest/v1"
        for path, field, expected in (
            ("hospital_patient_list", "patient_id", str(patient)),
            ("hospital_context_current", "content", "가상 병실 A"),
            ("hospital_message_list", "approved_text", "가상 예약 메시지 A"),
        ):
            status, rows = request(f"{base}/{path}?select={field}", "GET", public, token, schema="api")
            assert status == 200 and rows == [{field: expected}], f"staff {path}: {status}"
        status, facts = request(
            f"{base}/hospital_context_current?patient_id=eq.{patient}&select=category,content,encounter_id,verified_at,valid_until",
            "GET", public, token, schema="api",
        )
        assert status == 200 and len(facts) == 1 and facts[0]["verified_at"] and facts[0]["valid_until"] is None
        status, messages = request(
            f"{base}/hospital_message_list?patient_id=eq.{patient}&select=approved_text,approved_by_staff_ref,approved_at,due_at,delivery_status,delivered_at,cancelled_at,encounter_id",
            "GET", public, token, schema="api",
        )
        assert status == 200 and len(messages) == 1 and messages[0]["approved_by_staff_ref"] == "TEST-APPROVER"
        assert messages[0]["approved_at"] and messages[0]["due_at"] and messages[0]["delivery_status"] == "pending"
        status, _ = request(f"{base}/hospital_patient_list?select=patient_id", "GET", public, schema="api")
        assert status in (401, 403), f"anonymous patient read: {status}"

        sql(f"UPDATE kof5.hospital_staff_membership SET status='revoked', revoked_at=now() "
            f"WHERE membership_id='{membership}';")
        for path in ("hospital_patient_list", "hospital_context_current", "hospital_message_list"):
            status, rows = request(f"{base}/{path}?select=patient_id", "GET", public, token, schema="api")
            assert status == 200 and rows == [], f"revoked staff {path}: {status}"
        print("Local staff Auth → hospital RLS views → revocation/anon deny: PASS")
    finally:
        found = sql(f"SELECT id FROM auth.users WHERE email='{email}';")
        cleanup_id = UUID(found) if found else user_id
        try:
            sql(f"""
                DELETE FROM kof5.hospital_message WHERE patient_id IN ('{patient}', '{other}');
                DELETE FROM kof5.hospital_context_fact WHERE patient_id IN ('{patient}', '{other}');
                DELETE FROM kof5.hospital_staff_membership WHERE membership_id='{membership}';
                DELETE FROM kof5.hospital_encounter WHERE patient_id IN ('{patient}', '{other}');
                DELETE FROM kof5.hospital_patient WHERE patient_id IN ('{patient}', '{other}');
            """)
        finally:
            if cleanup_id is not None:
                status, _ = request(f"{url}/auth/v1/admin/users/{cleanup_id}", "DELETE", admin)
                assert status in (200, 204), f"local synthetic staff cleanup: {status}"


if __name__ == "__main__":
    main()
