"""Task-local Auth/Data API metadata test; no actual audio or provider request."""

from __future__ import annotations

from datetime import datetime, timezone
import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
HOSPITAL = "TEST-GUARDIAN-VOICE-HTTP"


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []
    emails: list[str] = []

    def permanent(name: str) -> tuple[UUID, str]:
        email = f"kof5-guardian-voice-{name}-{uuid4().hex}@example.invalid"
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
        guardian, guardian_token = permanent("owner")
        unlinked, unlinked_token = permanent("unlinked")
        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-GUARDIAN-VOICE-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.patient_guardian_link
                (patient_id,guardian_user_id,relationship,access_status,
                 effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{PATIENT}','{guardian}','가상 가족','verified',now()-interval '1 day',
                    'TEST-VERIFY',now());
            INSERT INTO kof5.consent_record
                (patient_id,guardian_ref,scope,signer_role,signer_ref,
                 assent_status,status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','{guardian}','guardian_voice_clone','guardian','{guardian}',
                    'not_required','active',now()-interval '1 day','TEST-STAFF');
        """)
        consent = UUID(sql("SELECT consent_id FROM kof5.consent_record "
                           f"WHERE patient_id='{PATIENT}' AND guardian_ref='{guardian}'"))
        base = f"{url}/rest/v1/rpc"
        status_rpc = f"{base}/synthetic_guardian_voice_status"
        begin_rpc = f"{base}/synthetic_guardian_voice_begin"
        provider_rpc = f"{base}/synthetic_guardian_voice_provider_result"
        tts_rpc = f"{base}/synthetic_guardian_voice_tts_ready"
        deletion_rpc = f"{base}/synthetic_guardian_voice_request_deletion"
        absence_rpc = f"{base}/synthetic_guardian_voice_confirm_remote_absence"
        status, rows = request(status_rpc, "POST", public, unlinked_token,
                               {"p_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False
        status, rows = request(status_rpc, "POST", public, guardian_token,
                               {"p_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is True \
            and rows[0]["ready"] is True and rows[0]["consent_id"] == str(consent) \
            and rows[0]["status"] == "none"
        request_key = uuid4()
        begin = {"p_patient_id": str(PATIENT), "p_guardian_user_id": str(guardian),
                 "p_consent_id": str(consent), "p_provider": "elevenlabs",
                 "p_request_key": str(request_key),
                 "p_sample_durations_ms": [20000, 25000, 30000]}
        status, _ = request(begin_rpc, "POST", public, guardian_token, begin, schema="api")
        assert status in (401, 403, 404), f"guardian invoked server writer: {status}"
        status, rows = request(begin_rpc, "POST", admin, payload={**begin,
                               "p_guardian_user_id": str(unlinked)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False
        status, rows = request(begin_rpc, "POST", admin, payload=begin, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["authorized"] is True \
            and rows[0]["status"] == "pending" and rows[0]["newly_created"] is True
        clone = UUID(rows[0]["clone_id"])
        assert rows[0]["provider_name"].startswith("KoF5 internal self-voice test ")
        status, retry = request(begin_rpc, "POST", admin, payload=begin, schema="api")
        assert status == 200 and retry[0]["clone_id"] == str(clone) \
            and retry[0]["newly_created"] is False, "retry could duplicate provider create"
        status, rows = request(tts_rpc, "POST", admin, payload=
                               {"p_patient_id": str(PATIENT),
                                "p_guardian_user_id": str(guardian)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False, "pending ID reached TTS"
        voice_id = "synthetic-voice-" + uuid4().hex
        status, rows = request(provider_rpc, "POST", admin, payload=
                               {"p_clone_id": str(clone), "p_voice_id": voice_id,
                                "p_verification_confirmed": None}, schema="api")
        assert status == 200 and rows[0]["status"] == "verification_pending"
        status, rows = request(provider_rpc, "POST", admin, payload=
                               {"p_clone_id": str(clone), "p_voice_id": voice_id,
                                "p_verification_confirmed": True}, schema="api")
        assert status == 200 and rows[0]["status"] == "created"
        status, rows = request(tts_rpc, "POST", admin, payload=
                               {"p_patient_id": str(PATIENT),
                                "p_guardian_user_id": str(guardian)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is True \
            and rows[0]["voice_id"] == voice_id
        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE consent_id='{consent}'")
        status, rows = request(tts_rpc, "POST", admin, payload=
                               {"p_patient_id": str(PATIENT),
                                "p_guardian_user_id": str(guardian)}, schema="api")
        assert status == 200 and rows[0]["authorized"] is False, "withdrawn ID reached TTS"
        status, rows = request(deletion_rpc, "POST", admin, payload=
                               {"p_clone_id": str(clone)}, schema="api")
        assert status == 200 and rows[0]["status"] == "deletion_pending"
        status, rows = request(absence_rpc, "POST", admin, payload=
                               {"p_clone_id": str(clone),
                                "p_method": "provider_name_not_found",
                                "p_checked_at": datetime.now(timezone.utc).isoformat()},
                               schema="api")
        assert status == 200 and rows[0]["authorized"] is False, \
            "DELETE response or wrong check could mark deleted"
        status, rows = request(absence_rpc, "POST", admin, payload=
                               {"p_clone_id": str(clone), "p_method": "voice_id_not_found",
                                "p_checked_at": datetime.now(timezone.utc).isoformat()},
                               schema="api")
        assert status == 200 and rows[0]["status"] == "deleted"
        status, rows = request(status_rpc, "POST", public, guardian_token,
                               {"p_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and rows[0]["status"] == "deleted" \
            and rows[0]["ready"] is False and rows[0]["consent_id"] is None
        print("Task-local Auth guardian status → server pending/verify → withdrawal deny → absence tombstone: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.synthetic_guardian_voice_clone WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.consent_record WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_guardian_link WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_patient WHERE patient_id='{PATIENT}';
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
