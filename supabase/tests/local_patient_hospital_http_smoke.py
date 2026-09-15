"""Task-local synthetic Auth→paired hospital fact RPC and withdrawal smoke."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from base64 import b64encode
import os
from pathlib import Path
import secrets
import sys
from unittest.mock import patch
from uuid import UUID, uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from fastapi.testclient import TestClient
from kof5_tts.api import app

from local_http_smoke import local_keys, request, sql, verify_local_target

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-HOSPITAL-TURN-HTTP"
HOSPITAL_TEXT = "가상 새봄병원입니다."
CT_TEXT = "가상 내일 오후 4시 CT 촬영 예정입니다."
ROOM_TEXT = "가상 302호 병실입니다."


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
        reviewer, reviewer_token = permanent("reviewer")
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
            VALUES ('{staff}','{HOSPITAL}','care_staff','verified',now()-interval '1 day','TEST-VERIFY',now()),
                   ('{reviewer}','{HOSPITAL}','care_staff','verified',now()-interval '1 day','TEST-VERIFY',now());
            INSERT INTO kof5.hospital_staff_assignment
                (membership_id,hospital_ref,patient_id,status,effective_at,verified_by_staff_ref,verified_at)
            SELECT membership_id,'{HOSPITAL}','{PATIENT}','verified',now()-interval '1 day','TEST-VERIFY',now()
            FROM kof5.hospital_staff_membership WHERE hospital_ref='{HOSPITAL}';
            INSERT INTO kof5.consent_record
                (patient_id,scope,signer_role,signer_ref,assent_status,status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','patient_participation','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','ambient_processing','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF'),
                   ('{PATIENT}','patient_voice_feature','patient','TEST-SIGNER','assented','active',now()-interval '1 day','TEST-STAFF');
            INSERT INTO kof5.consent_record
                (patient_id,guardian_ref,scope,signer_role,signer_ref,assent_status,status,effective_at,recorded_by_staff_ref)
            VALUES ('{PATIENT}','{guardian}','guardian_voice_clone','guardian','{guardian}',
                    'not_required','active',now()-interval '1 day','TEST-STAFF');
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
        drafts = f"{base}/synthetic_hospital_context_draft"
        proposal = {"patient_id": str(PATIENT), "encounter_id": str(ENCOUNTER),
                    "category": "room", "proposed_text": ROOM_TEXT,
                    "source_ref": "TEST-ROOM-BOARD-1"}
        status, _ = request(drafts, "POST", public, guardian_token, proposal, schema="api")
        assert status in (401, 403), "guardian proposed a hospital fact"
        status, _ = request(drafts, "POST", public, staff_token, proposal, schema="api")
        assert status == 201, f"assigned staff proposal: {status}"
        status, proposed = request(f"{drafts}?select=draft_id,category,proposed_text,source_ref,status,proposed_by_auth_user_id",
                                   "GET", public, reviewer_token, schema="api")
        assert status == 200 and len(proposed) == 1 and proposed[0]["proposed_text"] == ROOM_TEXT
        assert proposed[0]["category"] == "room" and proposed[0]["source_ref"] == proposal["source_ref"]
        assert proposed[0]["proposed_by_auth_user_id"] == str(staff)
        draft_id = UUID(proposed[0]["draft_id"])
        approval_path = f"{drafts}?draft_id=eq.{draft_id}&status=eq.draft"
        status, rows = request(approval_path, "PATCH", public, staff_token,
                               {"status": "approved"}, schema="api")
        assert status == 200 and rows == [], "proposer self-approved hospital fact"
        status, rows = request(approval_path, "PATCH", public, reviewer_token,
                               {"status": "approved"}, schema="api")
        assert status == 200 and len(rows) == 1 and rows[0]["approved_by_auth_user_id"] == str(reviewer), \
            f"distinct reviewer approval failed: {status}"
        status, approved = request(f"{base}/hospital_context_current?fact_id=eq.{draft_id}&select=fact_id,category,content,encounter_id,synthetic_source_ref",
                                   "GET", public, reviewer_token, schema="api")
        assert status == 200 and approved == [{"fact_id": str(draft_id), "category": "room",
                                                "content": ROOM_TEXT, "encounter_id": str(ENCOUNTER),
                                                "synthetic_source_ref": proposal["source_ref"]}], \
            "approved exact original was not published to current encounter"
        status, hospital_name = request(
            f"{base}/hospital_context_current?patient_id=eq.{PATIENT}&category=eq.hospital&select=content,encounter_id",
            "GET", public, reviewer_token, schema="api")
        assert status == 200 and hospital_name == [
            {"content": HOSPITAL_TEXT, "encounter_id": None}], \
            "assigned staff lost a current global hospital-name fact"

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
        guardian_consent = UUID(sql("SELECT consent_id FROM kof5.consent_record "
                                    f"WHERE patient_id='{PATIENT}' AND guardian_ref='{guardian}' "
                                    "AND scope='guardian_voice_clone';"))
        status, begun = request(f"{base}/rpc/synthetic_guardian_voice_begin", "POST",
                                admin, payload={"p_patient_id": str(PATIENT),
                                                "p_guardian_user_id": str(guardian),
                                                "p_consent_id": str(guardian_consent),
                                                "p_provider": "elevenlabs",
                                                "p_request_key": str(uuid4()),
                                                "p_sample_durations_ms": [20000, 25000, 30000]},
                                schema="api")
        assert status == 200 and begun[0]["authorized"] is True \
            and begun[0]["newly_created"] is True, "synthetic guardian voice metadata was not begun"
        status, result = request(f"{base}/rpc/synthetic_guardian_voice_provider_result",
                                 "POST", admin,
                                 payload={"p_clone_id": begun[0]["clone_id"],
                                          "p_voice_id": "TEST-VOICE-975",
                                          "p_verification_confirmed": True}, schema="api")
        assert status == 200 and result[0]["status"] == "created", \
            "synthetic guardian voice metadata was not selected"
        status, rows = hospital_turn(device_token, "어느 병원인가요?")
        assert status == 200 and len(rows) == 1 and rows[0]["authorized"] is True
        assert len(rows[0]["facts"]) == 1 and rows[0]["facts"][0]["content"] == HOSPITAL_TEXT
        assert rows[0]["facts"][0]["verified_at"] and rows[0]["facts"][0]["valid_until"]
        assert "source_staff_ref" not in rows[0]["facts"][0], "staff ID leaked to device"
        status, rows = hospital_turn(device_token, "CT 검사는 몇 시인가요?")
        assert status == 200 and rows[0]["authorized"] is True \
            and rows[0]["facts"][0]["content"] == CT_TEXT, "CT question selected newer MRI"
        status, rows = hospital_turn(device_token, "병실은 어디인가요?")
        assert status == 200 and rows[0]["authorized"] is True \
            and len(rows[0]["facts"]) == 1 \
            and rows[0]["facts"][0]["category"] == "room" \
            and rows[0]["facts"][0]["content"] == ROOM_TEXT \
            and rows[0]["facts"][0]["encounter_id"] == str(ENCOUNTER), \
            "paired device did not receive exact two-staff approved room fact"
        session_read = f"{base}/rpc/synthetic_conversation_session_read"
        session_commit = f"{base}/rpc/synthetic_conversation_session_commit"
        status, state = request(session_read, "POST", public, device_token,
                                {"p_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and len(state) == 1 and state[0]["authorized"] is True \
            and state[0]["state"] == "IDLE" and state[0]["version"] == 0 \
            and state[0]["session_id"] is None, "paired device did not start idle"
        first_turn = uuid4()
        first = {"p_patient_id": str(PATIENT), "p_expected_session_id": None,
                 "p_expected_version": 0, "p_new_state": "ACTIVE_LISTENING",
                 "p_proactive_paused": False, "p_client_turn_id": str(first_turn)}
        status, committed = request(session_commit, "POST", public, device_token,
                                    first, schema="api")
        assert status == 200 and committed[0]["authorized"] is True \
            and committed[0]["committed"] is True and committed[0]["version"] == 1 \
            and UUID(committed[0]["session_id"]), "paired first turn did not persist"
        status, state = request(session_read, "POST", public, device_token,
                                {"p_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and state[0]["state"] == "ACTIVE_LISTENING" \
            and state[0]["session_id"] == committed[0]["session_id"] \
            and state[0]["version"] == 1, "next request lost active session"
        status, duplicate = request(session_commit, "POST", public, device_token,
                                    first, schema="api")
        assert status == 200 and duplicate[0]["committed"] is False, \
            "duplicate client turn committed twice"
        follow = {**first, "p_expected_session_id": state[0]["session_id"],
                  "p_expected_version": 1, "p_client_turn_id": str(uuid4())}
        status, committed = request(session_commit, "POST", public, device_token,
                                    follow, schema="api")
        assert status == 200 and committed[0]["committed"] is True \
            and committed[0]["version"] == 2, "second turn did not advance CAS"
        close = {**follow, "p_expected_version": 2, "p_new_state": "IDLE",
                 "p_client_turn_id": str(uuid4())}
        status, closed = request(session_commit, "POST", public, device_token,
                                 close, schema="api")
        assert status == 200 and closed[0]["committed"] is True \
            and closed[0]["version"] == 3, "synthetic setup did not close before API turn"

        trial_headers = {"X-Internal-Demo-Token": "t" * 32,
                         "X-Synthetic-Material": "confirmed",
                         "Authorization": f"Bearer {device_token}"}
        trial_path = f"/internal/synthetic/paired/{PATIENT}/text"
        trial_env = {"KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
                     "KOF5_SUPABASE_URL": url,
                     "KOF5_SUPABASE_PUBLISHABLE_KEY": public,
                     "KOF5_SUPABASE_SECRET_KEY": keys["SECRET_KEY"],
                     "OPENAI_API_KEY": "synthetic-no-network",
                     "ELEVENLABS_API_KEY": "synthetic-no-network"}
        with patch.dict(os.environ, trial_env), patch(
            "kof5_tts.cloud_prototype.synthesize_mp3", return_value=b"synthetic-mp3"
        ) as synthesize:
            with TestClient(app) as first_client:
                first_response = first_client.post(trial_path, headers=trial_headers,
                    json={"transcript": "수민아", "label": "DIRECTED",
                          "client_turn_id": str(uuid4())})
            with TestClient(app) as second_client:
                follow_response = second_client.post(trial_path, headers=trial_headers,
                    json={"transcript": "수민아", "label": "UNCERTAIN",
                          "client_turn_id": str(uuid4())})
        assert first_response.status_code == follow_response.status_code == 200, \
            f"FastAPI paired two-turn round-trip failed: {first_response.status_code}/{follow_response.status_code}"
        for response in (first_response, follow_response):
            assert response.json()["reply"] == "응, 왜?" \
                and response.json()["audio_mp3_base64"] == b64encode(b"synthetic-mp3").decode(), \
                "DB-backed second turn failed to reach synthetic family-voice playback"
        assert synthesize.call_count == 2, "second turn did not synthesize independently"
        assert sql(f"SELECT count(*) FROM kof5.synthetic_directed_turn WHERE patient_id='{PATIENT}'") == "1", \
            "UNCERTAIN follow-up was logged as verified DIRECTED speech"
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
        status, state = request(session_read, "POST", public, device_token,
                                {"p_patient_id": str(PATIENT)}, schema="api")
        assert status == 200 and state[0]["authorized"] is False, \
            "withdrawn device retained its conversation session"
        print("Task-local Auth → approved hospital original → CAS/FastAPI second turn/withdrawal: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.hospital_context_fact WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.synthetic_hospital_context_draft WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.synthetic_directed_turn WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.synthetic_guardian_voice_clone WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.family_fact WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_guardian_link WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.synthetic_conversation_session WHERE patient_id='{PATIENT}';
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
