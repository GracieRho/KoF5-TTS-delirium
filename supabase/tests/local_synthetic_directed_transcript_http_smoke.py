"""Task-local synthetic Auth→device directed turn→staff today transcript smoke."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-DIRECTED-TRANSCRIPT-HTTP"
TRANSCRIPT = "가상 환자 질문"


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []
    emails: list[str] = []
    marker = uuid4().hex

    def permanent(name: str) -> tuple[UUID, str]:
        email = f"kof5-transcript-{name}-{uuid4().hex}@example.invalid"
        emails.append(email)
        password = secrets.token_urlsafe(24)
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password,
                                        "email_confirm": True})
        assert status in (200, 201), f"local {name} Auth create: {status}"
        uid = UUID(user["id"])
        users.append(uid)
        status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST", public,
                                  payload={"email": email, "password": password})
        assert status == 200, f"local {name} Auth login: {status}"
        return uid, session["access_token"]

    try:
        staff, staff_token = permanent("staff")
        _, guardian_token = permanent("guardian")
        _, unassigned_token = permanent("unassigned")
        status, anonymous = request(f"{url}/auth/v1/signup", "POST", public,
                                    payload={"data": {"kof5_synthetic_run": marker},
                                             "gotrue_meta_security": {"captcha_token": None}})
        assert status == 200 and anonymous["user"]["is_anonymous"] is True, \
            f"local anonymous device Auth: {status}"
        device = UUID(anonymous["user"]["id"])
        users.append(device)
        device_token = anonymous["access_token"]
        assert sql("SELECT raw_user_meta_data ->> 'kof5_synthetic_run' "
                   f"FROM auth.users WHERE id='{device}';") == marker

        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-DIRECTED-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
            VALUES ('{ENCOUNTER}','{PATIENT}','TEST-DIRECTED-E','in_progress',now()-interval '1 day');
            INSERT INTO kof5.hospital_registry_activation
                (hospital_ref,status,institution_approval_ref,clinical_safety_approval_ref,approved_at)
            VALUES ('{HOSPITAL}','approved','TEST-INSTITUTION','TEST-SAFETY',now()-interval '1 day');
            INSERT INTO kof5.hospital_staff_membership
                (auth_user_id,hospital_ref,product_role,status,effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{staff}','{HOSPITAL}','care_staff','verified',now()-interval '1 day','TEST-VERIFY',now());
            INSERT INTO kof5.hospital_staff_assignment
                (membership_id,hospital_ref,patient_id,status,effective_at,verified_by_staff_ref,verified_at)
            SELECT membership_id,'{HOSPITAL}','{PATIENT}','verified',now()-interval '1 day','TEST-VERIFY',now()
            FROM kof5.hospital_staff_membership WHERE auth_user_id='{staff}';
            INSERT INTO kof5.consent_record
                (patient_id,scope,signer_role,signer_ref,assent_status,status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','patient_participation','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','ambient_processing','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','patient_voice_feature','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF');
            INSERT INTO kof5.patient_voice_profile
                (patient_id,encounter_id,consent_id,status,enrollment_duration_ms,embedding_model,
                 embedding_version,encrypted_embedding_ref,quality_status,enrolled_by_staff_ref,enrolled_at)
            SELECT '{PATIENT}','{ENCOUNTER}',consent_id,'active',30000,'TEST-MODEL','TEST-VERSION',
                   'TEST-NOT-A-VOICE','accepted','TEST-STAFF',now()-interval '1 day'
            FROM kof5.consent_record WHERE patient_id='{PATIENT}' AND scope='patient_voice_feature';
        """)

        base = f"{url}/rest/v1"
        turn_url = f"{base}/rpc/record_synthetic_directed_turn"
        today_url = (f"{base}/synthetic_today_transcript?patient_id=eq.{PATIENT}"
                     f"&encounter_id=eq.{ENCOUNTER}"
                     "&select=turn_id,patient_id,encounter_id,transcript,captured_at")
        turn_id = uuid4()

        def record(token: str, text: str, client_id: UUID = turn_id) -> tuple[int, object]:
            return request(turn_url, "POST", public, token,
                           {"p_patient_id": str(PATIENT), "p_client_turn_id": str(client_id),
                            "p_transcript": text}, schema="api")

        for token in (device_token, guardian_token, staff_token, unassigned_token):
            status, result = record(token, TRANSCRIPT)
            assert status == 200 and result is False, "unpaired/non-device role recorded a turn"
        status, _ = request(f"{base}/patient_device_pairing", "POST", public, staff_token,
                            {"device_user_id": str(device), "patient_id": str(PATIENT),
                             "encounter_id": str(ENCOUNTER),
                             "expires_at": (datetime.now(timezone.utc)
                                            + timedelta(hours=7)).isoformat()}, schema="api")
        assert status == 201, f"verified assigned care_staff pairing: {status}"
        status, result = record(device_token, f" {TRANSCRIPT} ")
        assert status == 200 and result is True, "paired device could not record"
        status, result = record(device_token, TRANSCRIPT)
        assert status == 200 and result is True, "identical replay was not idempotent"
        status, result = record(device_token, "가상 다른 질문")
        assert status == 200 and result is False, "conflicting replay replaced patient text"
        for token in (device_token, guardian_token, unassigned_token):
            status, rows = request(today_url, "GET", public, token, schema="api")
            assert status == 200 and rows == [], "nonstaff read today's patient transcript"
        status, rows = request(today_url, "GET", public, staff_token, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["transcript"] == TRANSCRIPT
        assert set(rows[0]) == {"turn_id", "patient_id", "encounter_id", "transcript",
                                "captured_at"}, "staff view exposed additional columns"
        assert sql(f"SELECT count(*) FROM kof5.synthetic_directed_turn "
                   f"WHERE patient_id='{PATIENT}';") == "1", "replay made duplicate row"

        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE patient_id='{PATIENT}' AND scope='ambient_processing';")
        status, result = record(device_token, "철회 후 가상 질문", uuid4())
        assert status == 200 and result is False, "withdrawn patient allowed new text"
        status, result = record(device_token, TRANSCRIPT)
        assert status == 200 and result is False, "withdrawn patient allowed replay"
        status, rows = request(today_url, "GET", public, staff_token, schema="api")
        assert status == 200 and rows == [], "withdrawn text remained visible to staff"
        print("Task-local Auth → directed record/idempotency → staff today → withdrawal: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.synthetic_directed_turn WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_device_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_voice_profile WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.consent_record WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_membership WHERE hospital_ref='{HOSPITAL}';
                DELETE FROM kof5.hospital_encounter WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_registry_activation WHERE hospital_ref='{HOSPITAL}';
                DELETE FROM kof5.hospital_patient WHERE patient_id='{PATIENT}';
            """)
        finally:
            recovered = set(users)
            for email in emails:
                found = sql(f"SELECT id FROM auth.users WHERE email='{email}';")
                if found:
                    recovered.add(UUID(found))
            found = sql("SELECT id FROM auth.users WHERE is_anonymous IS TRUE "
                        f"AND raw_user_meta_data ->> 'kof5_synthetic_run'='{marker}';")
            if found:
                recovered.add(UUID(found))
            for uid in recovered:
                status, _ = request(f"{url}/auth/v1/admin/users/{uid}", "DELETE", admin)
                assert status in (200, 204), f"local synthetic Auth cleanup: {status}"


if __name__ == "__main__":
    main()
