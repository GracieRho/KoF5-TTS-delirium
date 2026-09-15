"""Task-local Auth/Data API round trip for synthetic auxiliary alerts only."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-ALERT-HTTP"


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []
    emails: list[str] = []
    marker = uuid4().hex

    def staff(name: str) -> tuple[UUID, str]:
        email = f"kof5-alert-{name}-{uuid4().hex}@example.invalid"
        emails.append(email)
        password = secrets.token_urlsafe(24)
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password,
                                        "email_confirm": True})
        assert status in (200, 201), f"local {name} create: {status}"
        uid = UUID(user["id"])
        users.append(uid)
        status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST", public,
                                  payload={"email": email, "password": password})
        assert status == 200, f"local {name} login: {status}"
        return uid, session["access_token"]

    try:
        care_staff, staff_token = staff("care")
        _, unassigned_token = staff("unassigned")
        status, anonymous = request(f"{url}/auth/v1/signup", "POST", public,
                                    payload={"data": {"kof5_synthetic_run": marker},
                                             "gotrue_meta_security": {"captcha_token": None}})
        assert status == 200 and anonymous["user"]["is_anonymous"] is True, \
            f"local anonymous Auth: {status}"
        device = UUID(anonymous["user"]["id"])
        users.append(device)
        device_token = anonymous["access_token"]
        assert sql("SELECT raw_user_meta_data ->> 'kof5_synthetic_run' "
                   f"FROM auth.users WHERE id='{device}'") == marker

        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-ALERT-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
            VALUES ('{ENCOUNTER}','{PATIENT}','TEST-ALERT-E','in_progress',now()-interval '1 day');
            INSERT INTO kof5.hospital_registry_activation
                (hospital_ref,status,institution_approval_ref,clinical_safety_approval_ref,approved_at)
            VALUES ('{HOSPITAL}','approved','TEST-INSTITUTION','TEST-CLINICAL',now()-interval '1 day');
            INSERT INTO kof5.hospital_staff_membership
                (auth_user_id,hospital_ref,product_role,status,effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{care_staff}','{HOSPITAL}','care_staff','verified',now()-interval '1 day',
                    'TEST-VERIFY',now());
            INSERT INTO kof5.hospital_staff_assignment
                (membership_id,hospital_ref,patient_id,status,effective_at,verified_by_staff_ref,verified_at)
            SELECT membership_id,'{HOSPITAL}','{PATIENT}','verified',now()-interval '1 day',
                   'TEST-VERIFY',now() FROM kof5.hospital_staff_membership
            WHERE auth_user_id='{care_staff}';
            INSERT INTO kof5.consent_record
                (patient_id,scope,signer_role,signer_ref,assent_status,status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','patient_participation','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','ambient_processing','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','patient_voice_feature','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF');
            INSERT INTO kof5.patient_voice_profile
                (patient_id,encounter_id,consent_id,status,enrollment_duration_ms,
                 embedding_model,embedding_version,encrypted_embedding_ref,quality_status,
                 enrolled_by_staff_ref,enrolled_at)
            SELECT '{PATIENT}','{ENCOUNTER}',consent_id,'active',30000,'TEST-MODEL',
                   'TEST-VERSION','TEST-NOT-A-VOICE','accepted','TEST-STAFF',now()-interval '1 day'
            FROM kof5.consent_record WHERE patient_id='{PATIENT}' AND scope='patient_voice_feature';
        """)
        base = f"{url}/rest/v1"
        create = f"{base}/rpc/synthetic_alert_create"
        ready = f"{base}/rpc/synthetic_alert_staff_ready"
        listed = f"{base}/rpc/synthetic_alert_staff_list"
        receipt = f"{base}/rpc/synthetic_alert_dashboard_receipt"
        ack = f"{base}/rpc/synthetic_alert_ack"
        resolve = f"{base}/rpc/synthetic_alert_resolve"
        status, rows = request(ready, "POST", public, unassigned_token, {}, schema="api")
        assert status == 200 and rows == [{"ready": False, "patient_id": None}]
        status, rows = request(create, "POST", public, device_token,
                               {"p_patient_id": str(PATIENT), "p_risk_category": "breathing",
                                "p_idempotency_key": str(uuid4())}, schema="api")
        assert status == 200 and rows == [{"authorized": False, "alert_id": None,
                                           "state": None}], "unpaired device created alert"
        expiry = (datetime.now(timezone.utc) + timedelta(hours=7)).isoformat()
        status, _ = request(f"{base}/patient_device_pairing", "POST", public, staff_token,
                            {"device_user_id": str(device), "patient_id": str(PATIENT),
                             "encounter_id": str(ENCOUNTER), "expires_at": expiry}, schema="api")
        assert status == 201, f"staff pairing: {status}"
        key = uuid4()
        payload = {"p_patient_id": str(PATIENT), "p_risk_category": "breathing",
                   "p_idempotency_key": str(key)}
        status, rows = request(create, "POST", public, device_token, payload, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["authorized"] is True \
            and rows[0]["state"] == "created"
        alert = UUID(rows[0]["alert_id"])
        status, retry = request(create, "POST", public, device_token, payload, schema="api")
        assert status == 200 and retry[0]["alert_id"] == str(alert), "idempotency changed ID"
        status, rows = request(create, "POST", public, device_token,
                               {**payload, "p_idempotency_key": str(uuid4())}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False, "device rate limit failed"
        status, rows = request(listed, "POST", public, unassigned_token, {}, schema="api")
        assert status == 200 and rows == [], "unassigned staff read alerts"
        status, rows = request(listed, "POST", public, staff_token, {}, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["state"] == "created" \
            and rows[0]["acknowledged_at"] is None
        status, rows = request(ack, "POST", public, staff_token,
                               {"p_alert_id": str(alert)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False, "created row was ACKed"
        status, rows = request(receipt, "POST", public, device_token,
                               {"p_alert_id": str(alert)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False, "device marked delivery"
        status, rows = request(receipt, "POST", public, staff_token,
                               {"p_alert_id": str(alert)}, schema="api")
        assert status == 200 and rows[0]["state"] == "delivered"
        status, rows = request(ack, "POST", public, staff_token,
                               {"p_alert_id": str(alert)}, schema="api")
        assert status == 200 and rows[0]["state"] == "acknowledged"
        status, rows = request(resolve, "POST", public, staff_token,
                               {"p_alert_id": str(alert)}, schema="api")
        assert status == 200 and rows[0]["state"] == "resolved"
        assert sql(f"SELECT count(*) FROM kof5.safety_audit_event WHERE patient_id='{PATIENT}'") == "5"
        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE patient_id='{PATIENT}' AND scope='ambient_processing'")
        status, rows = request(create, "POST", public, device_token,
                               {**payload, "p_idempotency_key": str(uuid4())}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False, "withdrawal allowed alert"
        status, rows = request(listed, "POST", public, staff_token, {}, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["state"] == "resolved", \
            "staff lost historical synthetic review after withdrawal"
        print("Task-local Auth paired device → alert created → staff receipt/ACK/resolve → withdrawal: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.synthetic_aux_alert WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.safety_audit_event WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_device_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_voice_profile WHERE patient_id='{PATIENT}';
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
            found = sql("SELECT id FROM auth.users WHERE is_anonymous IS TRUE "
                        f"AND raw_user_meta_data ->> 'kof5_synthetic_run'='{marker}'")
            if found:
                recovered.add(UUID(found))
            for uid in recovered:
                status, _ = request(f"{url}/auth/v1/admin/users/{uid}", "DELETE", admin)
                assert status in (200, 204), f"synthetic Auth cleanup: {status}"


if __name__ == "__main__":
    main()
