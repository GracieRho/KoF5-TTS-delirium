"""Task-local synthetic service writer→GoTrue device semantic turn smoke."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from hashlib import md5
import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-SEMANTIC-HTTP"
FACT = UUID("00000000-0000-4000-8000-000000009101")
SPOOF = UUID("00000000-0000-4000-8000-000000009108")
ORIGINAL = "가상 제주도 가족 여행 기억"
UPDATED = "가상 제주도 가족 여행 수정 기억"
RELATED = [1.0] + [0.0] * 1535
UNRELATED = [0.0, 1.0] + [0.0] * 1534


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []
    emails: list[str] = []
    anonymous_marker = uuid4().hex

    def permanent(name: str) -> tuple[UUID, str]:
        email = f"kof5-semantic-{name}-{uuid4().hex}@example.invalid"
        emails.append(email)  # Recovers an Auth user after a lost create response.
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
        guardian, guardian_token = permanent("guardian")
        status, anonymous = request(f"{url}/auth/v1/signup", "POST", public,
                                    payload={"data": {"kof5_synthetic_run": anonymous_marker},
                                             "gotrue_meta_security": {"captcha_token": None}})
        assert status == 200 and anonymous["user"]["is_anonymous"] is True, \
            f"local device Auth create: {status}"
        device = UUID(anonymous["user"]["id"])
        users.append(device)
        device_token = anonymous["access_token"]
        assert sql("SELECT raw_user_meta_data ->> 'kof5_synthetic_run' "
                   f"FROM auth.users WHERE id='{device}';") == anonymous_marker

        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-SEMANTIC-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
            VALUES ('{ENCOUNTER}','{PATIENT}','TEST-SEMANTIC-E','in_progress',now()-interval '1 day');
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
            INSERT INTO kof5.patient_guardian_link
                (patient_id,guardian_user_id,relationship,access_status,effective_at,verified_by_staff_ref,verified_at)
            VALUES ('{PATIENT}','{guardian}','가상 가족','verified',now()-interval '1 day','TEST-VERIFY',now());
            INSERT INTO kof5.family_fact
                (fact_id,patient_id,author_guardian_user_id,category,content)
            VALUES ('{FACT}','{PATIENT}','{guardian}','travel','{ORIGINAL}'),
                   ('{SPOOF}','{PATIENT}','{guardian}','hospital','가상 병원 사실인 척한 가족 입력');
        """)

        base = f"{url}/rest/v1"
        writer = f"{base}/rpc/upsert_synthetic_family_fact_embedding"
        turn = f"{base}/rpc/patient_family_semantic_turn_context"

        def write(token: str | None, key: str, fact: UUID, content: str) -> tuple[int, object]:
            return request(writer, "POST", key, token,
                           {"p_fact_id": str(fact), "p_embedding": RELATED,
                            "p_model": "text-embedding-3-small",
                            "p_content_md5": md5(content.encode("utf-8")).hexdigest()},
                           schema="api")

        def semantic_turn(token: str, vector: list[float]) -> tuple[int, object]:
            return request(turn, "POST", public, token,
                           {"p_patient_id": str(PATIENT), "p_query_embedding": vector},
                           schema="api")

        status, _ = write(guardian_token, public, FACT, ORIGINAL)
        assert status in (401, 403, 404), "guardian invoked server-only embedding writer"
        # A legacy service-role JWT is Bearer; a modern secret key is apikey only.
        server_token = admin if admin.startswith("eyJ") else None
        status, result = write(server_token, admin, FACT, ORIGINAL)
        assert status == 200 and result is True, f"server-only upsert failed: {status}"
        status, result = write(server_token, admin, SPOOF, "가상 병원 사실인 척한 가족 입력")
        assert status == 200 and result is False, "forged hospital category entered family index"
        status, rows = semantic_turn(device_token, RELATED)
        assert status == 200 and rows == [{"authorized": False, "facts": []}], \
            "unpaired device used semantic memory"
        status, rows = semantic_turn(guardian_token, RELATED)
        assert status == 200 and rows == [{"authorized": False, "facts": []}], \
            "guardian used device semantic turn"
        expiry = (datetime.now(timezone.utc) + timedelta(hours=7)).isoformat()
        status, _ = request(f"{base}/patient_device_pairing", "POST", public, staff_token,
                            {"device_user_id": str(device), "patient_id": str(PATIENT),
                             "encounter_id": str(ENCOUNTER), "expires_at": expiry}, schema="api")
        assert status == 201, f"assigned staff pairing: {status}"
        status, rows = semantic_turn(device_token, RELATED)
        assert status == 200 and rows == [{"authorized": True,
                                          "facts": [{"category": "travel", "content": ORIGINAL}]}], \
            "paired device did not retrieve exact synthetic family vector"
        status, rows = semantic_turn(device_token, UNRELATED)
        assert status == 200 and rows == [{"authorized": True, "facts": []}], \
            "unrelated vector passed provisional distance gate"
        status, rows = request(f"{base}/family_context?select=content", "GET", public,
                               device_token, schema="api")
        assert status == 200 and rows == [], "device enumerated guardian edit view"
        sql(f"UPDATE kof5.family_fact SET content='{UPDATED}' WHERE fact_id='{FACT}';")
        status, rows = semantic_turn(device_token, RELATED)
        assert status == 200 and rows == [{"authorized": True, "facts": []}], \
            "stale embedding remained visible after edit"
        status, result = write(server_token, admin, FACT, ORIGINAL)
        assert status == 200 and result is False, "late writer revived stale source text"
        status, result = write(server_token, admin, FACT, UPDATED)
        assert status == 200 and result is True, "updated family fact could not be reindexed"
        status, rows = semantic_turn(device_token, RELATED)
        assert status == 200 and rows == [{"authorized": True,
                                          "facts": [{"category": "travel", "content": UPDATED}]}], \
            "new source hash not reflected in semantic turn"
        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE patient_id='{PATIENT}' AND scope='ambient_processing';")
        status, rows = semantic_turn(device_token, RELATED)
        assert status == 200 and rows == [{"authorized": False, "facts": []}], \
            "consent withdrawal looked like authorized no-match"
        print("Task-local server-only writer → device semantic RLS → stale/withdrawal: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.family_fact_embedding WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.family_fact WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_guardian_link WHERE patient_id='{PATIENT}';
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
                        f"AND raw_user_meta_data ->> 'kof5_synthetic_run'='{anonymous_marker}';")
            if found:
                recovered.add(UUID(found))
            for uid in recovered:
                status, _ = request(f"{url}/auth/v1/admin/users/{uid}", "DELETE", admin)
                assert status in (200, 204), f"local synthetic Auth cleanup: {status}"


if __name__ == "__main__":
    main()
