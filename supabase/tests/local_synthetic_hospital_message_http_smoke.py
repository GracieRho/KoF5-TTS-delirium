"""Synthetic-only staff approval and paired-device Data API round trip."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-MESSAGE-HTTP"
TEXT = "오늘 오후 4시에 가상 CT 촬영 예정입니다."


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []

    def permanent(name: str) -> tuple[UUID, str]:
        email = f"kof5-message-{name}-{uuid4().hex}@example.invalid"
        password = secrets.token_urlsafe(24)
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password, "email_confirm": True})
        assert status in (200, 201), f"{name} local Auth creation: {status}"
        uid = UUID(user["id"])
        users.append(uid)
        status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST", public,
                                  payload={"email": email, "password": password})
        assert status == 200, f"{name} local Auth login: {status}"
        return uid, session["access_token"]

    try:
        proposer, proposer_token = permanent("proposer")
        approver, approver_token = permanent("approver")
        guardian, guardian_token = permanent("guardian")
        status, anonymous = request(f"{url}/auth/v1/signup", "POST", public,
                                    payload={"data": {}, "gotrue_meta_security": {"captcha_token": None}})
        assert status == 200 and anonymous["user"]["is_anonymous"] is True, \
            f"local anonymous device Auth: {status}"
        device = UUID(anonymous["user"]["id"])
        users.append(device)
        device_token = anonymous["access_token"]

        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-MESSAGE-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
            VALUES ('{ENCOUNTER}','{PATIENT}','TEST-MESSAGE-E','in_progress',now()-interval '1 day');
            INSERT INTO kof5.hospital_registry_activation
                (hospital_ref,status,institution_approval_ref,clinical_safety_approval_ref,approved_at)
            VALUES ('{HOSPITAL}','approved','TEST-INSTITUTION','TEST-SAFETY',now()-interval '1 day');
            INSERT INTO kof5.hospital_staff_membership
                (auth_user_id,hospital_ref,product_role,status,effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{proposer}','{HOSPITAL}','care_staff','verified',now()-interval '1 day','TEST-VERIFY',now()),
                   ('{approver}','{HOSPITAL}','care_staff','verified',now()-interval '1 day','TEST-VERIFY',now());
            INSERT INTO kof5.hospital_staff_assignment
                (membership_id,hospital_ref,patient_id,status,effective_at,verified_by_staff_ref,verified_at)
            SELECT membership_id,'{HOSPITAL}','{PATIENT}','verified',now()-interval '1 day','TEST-VERIFY',now()
            FROM kof5.hospital_staff_membership WHERE hospital_ref='{HOSPITAL}';
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
            INSERT INTO kof5.patient_guardian_link
                (patient_id,guardian_user_id,relationship,access_status,effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{PATIENT}','{guardian}','가상 보호자','verified',now()-interval '1 day','TEST-VERIFY',now());
        """)
        base = f"{url}/rest/v1"
        drafts = f"{base}/synthetic_hospital_message_draft"
        payload = {"patient_id": str(PATIENT), "encounter_id": str(ENCOUNTER),
                   "proposed_text": TEXT, "schedule_mode": "now"}
        status, _ = request(drafts, "POST", public, guardian_token, payload, schema="api")
        assert status in (401, 403), f"guardian proposed: {status}"
        status, _ = request(drafts, "POST", public, device_token, payload, schema="api")
        assert status in (401, 403), f"device proposed: {status}"
        status, _ = request(drafts, "POST", public, proposer_token, payload, schema="api")
        assert status == 201, f"assigned proposer insert: {status}"
        status, rows = request(f"{drafts}?select=draft_id,proposed_text,status,proposed_by_auth_user_id",
                               "GET", public, proposer_token, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["proposed_text"] == TEXT
        draft = UUID(rows[0]["draft_id"])
        assert rows[0]["proposed_by_auth_user_id"] == str(proposer)
        endpoint = f"{drafts}?draft_id=eq.{draft}&status=eq.draft"
        status, rows = request(endpoint, "PATCH", public, proposer_token,
                               {"status": "approved"}, schema="api")
        assert status == 200 and rows == [], f"self-approval changed rows: {status}"
        status, rows = request(endpoint, "PATCH", public, approver_token,
                               {"status": "approved"}, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["status"] == "approved", \
            f"distinct approval failed: {status}"
        assert rows[0]["approved_by_auth_user_id"] == str(approver)
        status, messages = request(f"{base}/hospital_message_list?message_id=eq.{draft}",
                                   "GET", public, approver_token, schema="api")
        assert status == 200 and len(messages) == 1 and messages[0]["approved_text"] == TEXT
        assert messages[0]["delivery_status"] == "pending"
        assert sql(f"SELECT approved_by_staff_ref FROM kof5.hospital_message WHERE message_id='{draft}'") == str(approver)

        due_ids = f"{base}/rpc/synthetic_due_hospital_message_ids"
        due_one = f"{base}/rpc/synthetic_due_hospital_message"
        status, ids = request(due_ids, "POST", public, device_token,
                              {"_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and ids == [], "unpaired device discovered message IDs"
        status, rows = request(due_one, "POST", public, device_token,
                               {"_patient_id": str(PATIENT), "_message_id": str(draft)}, schema="api")
        assert status == 200 and rows == [{"authorized": False, "message_id": None,
                                           "approved_text": None, "due_at": None}]
        expiry = (datetime.now(timezone.utc) + timedelta(hours=7)).isoformat()
        status, _ = request(f"{base}/patient_device_pairing", "POST", public, proposer_token,
                            {"device_user_id": str(device), "patient_id": str(PATIENT),
                             "encounter_id": str(ENCOUNTER), "expires_at": expiry}, schema="api")
        assert status == 201, f"assigned staff pairing: {status}"
        status, ids = request(due_ids, "POST", public, device_token,
                              {"_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and len(ids) == 1 and ids[0]["message_id"] == str(draft)
        status, rows = request(due_one, "POST", public, device_token,
                               {"_patient_id": str(PATIENT), "_message_id": str(draft)}, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["authorized"] is True \
            and rows[0]["approved_text"] == TEXT
        sql(f"""
            INSERT INTO kof5.hospital_staff_membership
                (auth_user_id,hospital_ref,product_role,status,effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{device}','{HOSPITAL}','registrar','verified',now()-interval '1 day','TEST-VERIFY',now());
        """)
        status, patients = request(f"{base}/hospital_patient_list?select=patient_id", "GET",
                                   public, device_token, schema="api")
        assert status == 200 and patients == [], "misissued anonymous registrar saw staff patient list"
        status, messages = request(f"{base}/hospital_message_list?select=message_id", "GET",
                                   public, device_token, schema="api")
        assert status == 200 and messages == [], "misissued anonymous registrar saw staff message list"
        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE patient_id='{PATIENT}' AND scope='ambient_processing';")
        status, ids = request(due_ids, "POST", public, device_token,
                              {"_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and ids == [], "withdrawal left due IDs visible"
        status, rows = request(due_one, "POST", public, device_token,
                               {"_patient_id": str(PATIENT), "_message_id": str(draft)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False and rows[0]["approved_text"] is None
        print("Local Auth staff propose → distinct approve → pending → paired due RPC → withdrawal/misissued deny: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.hospital_message WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.synthetic_hospital_message_draft WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_device_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_voice_profile WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.consent_record WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_guardian_link WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_membership WHERE hospital_ref='{HOSPITAL}';
                DELETE FROM kof5.hospital_encounter WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_patient WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_registry_activation WHERE hospital_ref='{HOSPITAL}';
            """)
        finally:
            for uid in users:
                status, _ = request(f"{url}/auth/v1/admin/users/{uid}", "DELETE", admin)
                assert status in (200, 204), f"synthetic Auth cleanup: {status}"


if __name__ == "__main__":
    main()
