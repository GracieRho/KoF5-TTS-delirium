"""Task-local GoTrue/Data API check of first synthetic voice enrollment readiness."""

from __future__ import annotations

import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-ENROLL-HTTP"


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []
    emails: list[str] = []

    def permanent(name: str) -> tuple[UUID, str]:
        email = f"kof5-enroll-{name}-{uuid4().hex}@example.invalid"
        emails.append(email)
        password = secrets.token_urlsafe(24)
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password,
                                        "email_confirm": True})
        assert status in (200, 201), f"local Auth {name} create: {status}"
        uid = UUID(user["id"])
        users.append(uid)
        status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST", public,
                                  payload={"email": email, "password": password})
        assert status == 200, f"local Auth {name} login: {status}"
        return uid, session["access_token"]

    try:
        staff, staff_token = permanent("care")
        _, unassigned_token = permanent("unassigned")
        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-ENROLL-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
            VALUES ('{ENCOUNTER}','{PATIENT}','TEST-ENROLL-E','in_progress',now()-interval '1 day');
            INSERT INTO kof5.hospital_registry_activation
                (hospital_ref,status,institution_approval_ref,clinical_safety_approval_ref,approved_at)
            VALUES ('{HOSPITAL}','approved','TEST-INSTITUTION','TEST-CLINICAL',now()-interval '1 day');
            INSERT INTO kof5.hospital_staff_membership
                (auth_user_id,hospital_ref,product_role,status,effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{staff}','{HOSPITAL}','care_staff','verified',now()-interval '1 day',
                    'TEST-VERIFY',now());
            INSERT INTO kof5.hospital_staff_assignment
                (membership_id,hospital_ref,patient_id,status,effective_at,verified_by_staff_ref,verified_at)
            SELECT membership_id,'{HOSPITAL}','{PATIENT}','verified',now()-interval '1 day',
                   'TEST-VERIFY',now() FROM kof5.hospital_staff_membership
            WHERE auth_user_id='{staff}';
            INSERT INTO kof5.consent_record
                (patient_id,scope,signer_role,signer_ref,assent_status,status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','patient_participation','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','patient_voice_feature','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF');
        """)
        assert sql(f"SELECT count(*) FROM kof5.patient_voice_profile WHERE patient_id='{PATIENT}'") == "0"
        rpc = f"{url}/rest/v1/rpc/synthetic_voice_enrollment_ready"
        status, rows = request(rpc, "POST", public, unassigned_token, {}, schema="api")
        assert status == 200 and rows == [{"ready": False, "patient_id": None,
                                           "voice_profile_state": None}], \
            "unassigned staff saw enrollment readiness"
        status, rows = request(rpc, "POST", public, staff_token, {}, schema="api")
        assert status == 200 and rows == [{"ready": True, "patient_id": str(PATIENT),
                                           "voice_profile_state": "none"}], \
            "assigned staff could not start first synthetic enrollment"
        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE patient_id='{PATIENT}' AND scope='patient_voice_feature'")
        status, rows = request(rpc, "POST", public, staff_token, {}, schema="api")
        assert status == 200 and rows == [{"ready": False, "patient_id": str(PATIENT),
                                           "voice_profile_state": "none"}], \
            "withdrawal left enrollment ready"
        print("Task-local Auth assigned staff → ready without voice profile → withdrawal deny: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.consent_record WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_membership WHERE hospital_ref='{HOSPITAL}';
                DELETE FROM kof5.hospital_encounter WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_patient WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_registry_activation WHERE hospital_ref='{HOSPITAL}';
            """)
        finally:
            recovered = set(users)
            for email in emails:
                found = sql(f"SELECT id FROM auth.users WHERE email='{email}'")
                if found:
                    recovered.add(UUID(found))
            for uid in recovered:
                status, _ = request(f"{url}/auth/v1/admin/users/{uid}", "DELETE", admin)
                assert status in (200, 204), f"synthetic Auth cleanup: {status}"


if __name__ == "__main__":
    main()
