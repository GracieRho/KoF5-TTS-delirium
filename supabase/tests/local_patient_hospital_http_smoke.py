"""Task-local synthetic Auth→paired hospital fact RPC and withdrawal smoke."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from uuid import UUID, uuid4

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-HOSPITAL-TURN-HTTP"
HOSPITAL_TEXT = "가상 새봄병원입니다."
CT_TEXT = "가상 내일 오후 4시 CT 촬영 예정입니다."


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    users: list[UUID] = []
    emails: list[str] = []
    anonymous_marker = uuid4().hex

    def permanent(name: str) -> tuple[UUID, str]:
        email = f"kof5-hospital-turn-{name}-{uuid4().hex}@example.invalid"
        emails.append(email)  # Recover an Auth user even when the create response is lost.
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
            f"local anonymous device Auth: {status}"
        device = UUID(anonymous["user"]["id"])
        users.append(device)
        device_token = anonymous["access_token"]
        assert sql("SELECT raw_user_meta_data ->> 'kof5_synthetic_run' "
                   f"FROM auth.users WHERE id='{device}';") == anonymous_marker

        sql(f"""
            INSERT INTO kof5.hospital_patient
                (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
            VALUES ('{PATIENT}','{HOSPITAL}','TEST-HOSPITAL-TURN-P','가상 환자','TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
                (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
            VALUES ('{ENCOUNTER}','{PATIENT}','TEST-HOSPITAL-TURN-E','in_progress',now()-interval '1 day');
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
                (patient_id,author_guardian_user_id,category,content)
            VALUES ('{PATIENT}','{guardian}','travel','가상 제주도 가족 여행 기억');
            INSERT INTO kof5.hospital_context_fact
                (patient_id,encounter_id,category,content,source_staff_ref,approved_by_staff_ref,
                 verified_at,valid_until,status)
            VALUES ('{PATIENT}',NULL,'hospital','{HOSPITAL_TEXT}','TEST-SOURCE','TEST-APPROVER',
                    now()-interval '1 hour',now()+interval '1 day','approved'),
                   ('{PATIENT}','{ENCOUNTER}','test_schedule','{CT_TEXT}','TEST-SOURCE','TEST-APPROVER',
                    now()-interval '3 hours',now()+interval '1 day','approved'),
                   ('{PATIENT}','{ENCOUNTER}','test_schedule','가상 내일 오전 9시 MRI 촬영 예정입니다.',
                    'TEST-SOURCE','TEST-APPROVER',now()-interval '2 hours',now()+interval '1 day','approved');
        """)

        base = f"{url}/rest/v1"
        turn = f"{base}/rpc/patient_hospital_turn_context"

        def hospital_turn(token: str, question: str) -> tuple[int, object]:
            return request(turn, "POST", public, token,
                           {"p_patient_id": str(PATIENT), "p_term": question}, schema="api")

        status, rows = hospital_turn(guardian_token, "어느 병원인가요?")
        assert status == 200 and rows == [{"authorized": False, "facts": []}], \
            "guardian used device hospital turn"
        status, rows = request(f"{base}/hospital_context_current?select=content", "GET",
                               public, guardian_token, schema="api")
        assert status == 200 and rows == [], "guardian saw staff hospital context"
        status, rows = hospital_turn(device_token, "어느 병원인가요?")
        assert status == 200 and rows == [{"authorized": False, "facts": []}], \
            "unpaired device saw hospital fact"
        expiry = (datetime.now(timezone.utc) + timedelta(hours=7)).isoformat()
        status, _ = request(f"{base}/patient_device_pairing", "POST", public, staff_token,
                            {"device_user_id": str(device), "patient_id": str(PATIENT),
                             "encounter_id": str(ENCOUNTER), "expires_at": expiry}, schema="api")
        assert status == 201, f"assigned staff pairing: {status}"
        status, rows = request(f"{base}/hospital_context_current?select=content", "GET",
                               public, device_token, schema="api")
        assert status == 200 and rows == [], "paired device enumerated staff hospital view"
        status, rows = hospital_turn(device_token, "어느 병원인가요?")
        assert status == 200 and len(rows) == 1 and rows[0]["authorized"] is True
        assert len(rows[0]["facts"]) == 1 and rows[0]["facts"][0]["content"] == HOSPITAL_TEXT
        assert rows[0]["facts"][0]["verified_at"] and rows[0]["facts"][0]["valid_until"]
        assert "source_staff_ref" not in rows[0]["facts"][0], "staff ID leaked to device"
        status, rows = hospital_turn(device_token, "CT 검사는 몇 시인가요?")
        assert status == 200 and rows[0]["authorized"] is True \
            and rows[0]["facts"][0]["content"] == CT_TEXT, "CT question selected newer MRI"
        for question in ("검사는 언제인가요?", "CT 검사 결과 어때요?", "음악 좋아하세요?"):
            status, rows = hospital_turn(device_token, question)
            assert status == 200 and rows == [{"authorized": True, "facts": []}], \
                f"ambiguous/unrelated hospital turn guessed an original: {question}"
        status, family = request(f"{base}/rpc/patient_family_turn_context", "POST", public,
                                 device_token, {"p_patient_id": str(PATIENT),
                                                "p_term": "제주도 기억 알려줘"}, schema="api")
        assert status == 200 and family[0]["authorized"] is True \
            and family[0]["facts"][0]["content"] == "가상 제주도 가족 여행 기억", \
            "guardian fact namespace did not remain separate"
        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE patient_id='{PATIENT}' AND scope='ambient_processing';")
        status, rows = hospital_turn(device_token, "어느 병원인가요?")
        assert status == 200 and rows == [{"authorized": False, "facts": []}], \
            "ambient withdrawal appeared as an authorized no-match"
        status, rows = request(f"{base}/hospital_context_current?select=content", "GET",
                               public, device_token, schema="api")
        assert status == 200 and rows == [], "withdrawn device reached staff hospital view"
        print("Task-local Auth → paired hospital/family namespaces → atomic withdrawal: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.hospital_context_fact WHERE patient_id='{PATIENT}';
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
