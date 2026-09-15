"""Synthetic registration gate check against only this task's local Supabase stack."""

from __future__ import annotations

import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    hospital = f"TEST-REG-{uuid4().hex}"
    patient_ref = f"TEST-P-{uuid4().hex}"
    email = f"kof5-registrar-{uuid4().hex}@example.invalid"
    password = secrets.token_urlsafe(24)
    user_id: UUID | None = None
    try:
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password, "email_confirm": True})
        assert status in (200, 201), f"local synthetic registrar create: {status}"
        user_id = UUID(user["id"])
        sql(f"""
            INSERT INTO kof5.hospital_staff_membership
                (auth_user_id, hospital_ref, product_role, status,
                 effective_at, verified_by_staff_ref, verified_at)
            VALUES ('{user_id}', '{hospital}', 'registrar', 'verified',
                    now() - interval '1 minute', 'TEST-VERIFY', now());
        """)
        status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST", public,
                                  payload={"email": email, "password": password})
        assert status == 200, f"local synthetic registrar login: {status}"
        token = session["access_token"]
        endpoint = f"{url}/rest/v1/hospital_patient_registration"
        payload = {"hospital_ref": hospital, "ehr_patient_ref": patient_ref,
                   "staff_display_name": "가상 환자"}
        status, _ = request(endpoint, "POST", public, token, payload, schema="api")
        assert status in (401, 403), f"registration without institution gate: {status}"

        sql(f"""
            INSERT INTO kof5.hospital_registry_activation
                (hospital_ref, status, institution_approval_ref,
                 clinical_safety_approval_ref, approved_at)
            VALUES ('{hospital}', 'approved', 'TEST-INSTITUTION', 'TEST-SAFETY',
                    now() - interval '1 minute');
        """)
        status, _ = request(endpoint, "POST", public, token, payload, schema="api")
        assert status == 201, f"approved synthetic registrar insert: {status}"
        recorded = sql(f"SELECT registered_by_staff_ref FROM kof5.hospital_patient "
                       f"WHERE hospital_ref='{hospital}' AND ehr_patient_ref='{patient_ref}';")
        assert recorded == str(user_id), "registrar identity did not come from Auth"
        status, _ = request(endpoint, "POST", public, token,
                            {**payload, "registered_by_staff_ref": "TEST-SPOOF"}, schema="api")
        assert status == 400, f"registration view should reject spoof field: {status}"
        status, _ = request(endpoint, "POST", public, token, payload, schema="api")
        assert status == 409, f"duplicate hospital patient ref: {status}"
        status, _ = request(endpoint, "POST", public, payload={**payload, "ehr_patient_ref": patient_ref + '-ANON'}, schema="api")
        assert status in (401, 403), f"anonymous registration: {status}"
        sql(f"UPDATE kof5.hospital_staff_membership SET status='revoked', revoked_at=now() "
            f"WHERE auth_user_id='{user_id}' AND hospital_ref='{hospital}';")
        status, _ = request(endpoint, "POST", public, token,
                            {**payload, "ehr_patient_ref": patient_ref + '-AFTER'}, schema="api")
        assert status in (401, 403), f"revoked registrar registration: {status}"
        print("Local registrar Auth → gated Data API registration → spoof/duplicate/revocation deny: PASS")
    finally:
        found = sql(f"SELECT id FROM auth.users WHERE email='{email}';")
        cleanup_id = UUID(found) if found else user_id
        try:
            sql(f"DELETE FROM kof5.hospital_patient WHERE hospital_ref='{hospital}'; "
                f"DELETE FROM kof5.hospital_staff_membership WHERE hospital_ref='{hospital}'; "
                f"DELETE FROM kof5.hospital_registry_activation WHERE hospital_ref='{hospital}';")
        finally:
            if cleanup_id is not None:
                status, _ = request(f"{url}/auth/v1/admin/users/{cleanup_id}", "DELETE", admin)
                assert status in (200, 204), f"local synthetic registrar cleanup: {status}"


if __name__ == "__main__":
    main()
