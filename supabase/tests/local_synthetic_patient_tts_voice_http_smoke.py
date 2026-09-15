"""Task-local Auth/Data API TTS selection test; synthetic metadata, no audio."""

from __future__ import annotations

import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
HOSPITAL = "TEST-PATIENT-TTS-HTTP"


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []
    emails: list[str] = []

    def guardian(name: str) -> tuple[UUID, str]:
        email = f"kof5-patient-tts-{name}-{uuid4().hex}@example.invalid"
        emails.append(email)
        password = secrets.token_urlsafe(24)
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password,
                                        "email_confirm": True})
        assert status in (200, 201), f"local synthetic Auth create: {status}"
        uid = UUID(user["id"])
        users.append(uid)
        status, session = request(f"{url}/auth/v1/token?grant_type=password",
                                  "POST", public,
                                  payload={"email": email, "password": password})
        assert status == 200, f"local synthetic Auth login: {status}"
        return uid, session["access_token"]

    try:
        first, first_token = guardian("first")
        second, _ = guardian("second")
        sql(f"""
            INSERT INTO kof5.hospital_registry_activation
                (hospital_ref,status,institution_approval_ref,
                 clinical_safety_approval_ref,approved_at)
            VALUES ('{HOSPITAL}','approved','TEST-INSTITUTION','TEST-SAFETY',
                    now()-interval '1 day');
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,
                 registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-TTS-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (patient_id,ehr_encounter_ref,status,admitted_at)
            VALUES ('{PATIENT}','TEST-TTS-E','in_progress',now()-interval '1 day');
            INSERT INTO kof5.patient_guardian_link
                (patient_id,guardian_user_id,relationship,access_status,
                 effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{PATIENT}','{first}','가상 가족 1','verified',
                    now()-interval '1 day','TEST-VERIFY',now()),
                   ('{PATIENT}','{second}','가상 가족 2','verified',
                    now()-interval '1 day','TEST-VERIFY',now());
            INSERT INTO kof5.consent_record
                (patient_id,scope,signer_role,signer_ref,assent_status,
                 status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','patient_participation','patient','TEST-PATIENT',
                    'assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','ambient_processing','patient','TEST-PATIENT',
                    'assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','patient_voice_feature','patient','TEST-PATIENT',
                    'assented','active',now()-interval '1 day','TEST-STAFF');
            INSERT INTO kof5.consent_record
                (patient_id,guardian_ref,scope,signer_role,signer_ref,
                 assent_status,status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','{first}','guardian_voice_clone','guardian','{first}',
                    'not_required','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','{second}','guardian_voice_clone','guardian','{second}',
                    'not_required','active',now()-interval '1 day','TEST-STAFF');
        """)
        base = f"{url}/rest/v1/rpc"
        select_rpc = f"{base}/synthetic_patient_tts_voice_ready"
        begin_rpc = f"{base}/synthetic_guardian_voice_begin"
        result_rpc = f"{base}/synthetic_guardian_voice_provider_result"
        delete_rpc = f"{base}/synthetic_guardian_voice_request_deletion"
        patient_arg = {"p_patient_id": str(PATIENT)}

        status, rows = request(select_rpc, "POST", public, first_token,
                               patient_arg, schema="api")
        assert status in (401, 403, 404), f"guardian reached server voice selector: {status}"
        status, rows = request(select_rpc, "POST", admin, payload=patient_arg,
                               schema="api")
        assert status == 200 and len(rows) == 1 and rows[0] == {
            "authorized": False, "guardian_user_id": None, "clone_id": None,
            "provider": None, "voice_id": None,
        }, "zero candidates leaked identifiers or returned wrong row count"

        def created_clone(uid: UUID, provider: str) -> tuple[UUID, str]:
            consent_id = UUID(sql("SELECT consent_id FROM kof5.consent_record "
                                  f"WHERE patient_id='{PATIENT}' "
                                  f"AND scope='guardian_voice_clone' "
                                  f"AND guardian_ref='{uid}'"))
            status, rows = request(begin_rpc, "POST", admin, payload={
                "p_patient_id": str(PATIENT), "p_guardian_user_id": str(uid),
                "p_consent_id": str(consent_id), "p_provider": provider,
                "p_request_key": str(uuid4()),
                "p_sample_durations_ms": [20000, 25000, 30000],
            }, schema="api")
            assert status == 200 and rows[0]["authorized"] is True \
                and rows[0]["newly_created"] is True
            clone = UUID(rows[0]["clone_id"])
            voice_id = "synthetic-tts-" + uuid4().hex
            status, rows = request(result_rpc, "POST", admin, payload={
                "p_clone_id": str(clone), "p_voice_id": voice_id,
                "p_verification_confirmed": True,
            }, schema="api")
            assert status == 200 and rows[0]["status"] == "created"
            return clone, voice_id

        first_clone, first_voice = created_clone(first, "elevenlabs")
        status, rows = request(select_rpc, "POST", admin, payload=patient_arg,
                               schema="api")
        assert status == 200 and len(rows) == 1 and rows[0] == {
            "authorized": True, "guardian_user_id": str(first),
            "clone_id": str(first_clone), "provider": "elevenlabs",
            "voice_id": first_voice,
        }, "one current clone was not selected exactly"
        status, rows = request(select_rpc, "POST", admin,
                               payload={"p_patient_id": str(uuid4())}, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["authorized"] is False \
            and rows[0]["voice_id"] is None, "other patient ID reached synthetic clone"

        second_clone, _ = created_clone(second, "other_provider")
        status, rows = request(select_rpc, "POST", admin, payload=patient_arg,
                               schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["authorized"] is False \
            and all(rows[0][key] is None for key in
                    ("guardian_user_id", "clone_id", "provider", "voice_id")), \
            "ambiguous guardian voices leaked a chosen provider ID"
        status, rows = request(delete_rpc, "POST", admin,
                               payload={"p_clone_id": str(second_clone)}, schema="api")
        assert status == 200 and rows[0]["status"] == "deletion_pending"
        status, rows = request(select_rpc, "POST", admin, payload=patient_arg,
                               schema="api")
        assert status == 200 and rows[0]["clone_id"] == str(first_clone)
        sql(f"UPDATE kof5.consent_record SET status='expired' "
            f"WHERE patient_id='{PATIENT}' AND scope='ambient_processing'")
        status, rows = request(select_rpc, "POST", admin, payload=patient_arg,
                               schema="api")
        assert status == 200 and rows[0]["authorized"] is False \
            and rows[0]["voice_id"] is None, "revoked ambient consent reached TTS"
        print("Task-local Auth/Data API patient TTS selection 0/1/2/revocation: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.synthetic_guardian_voice_clone WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.consent_record WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_guardian_link WHERE patient_id='{PATIENT}';
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
