"""Task-local synthetic GoTrue→staff pairing→device RLS→family search round trip."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import secrets
import sys
from unittest.mock import patch
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from local_http_smoke import local_keys, request, sql, verify_local_target

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from kof5_tts.api import app  # noqa: E402

PATIENT = UUID("00000000-0000-4000-8000-000000000975")
ENCOUNTER = UUID("00000000-0000-4000-8000-000000000976")
HOSPITAL = "TEST-DEVICE-HTTP"


def main() -> None:
    keys = local_keys()
    verify_local_target(keys)
    url, public, admin = keys["API_URL"], keys["PUBLISHABLE_KEY"], keys["SERVICE_ROLE_KEY"]
    assert sql(f"SELECT count(*) FROM kof5.hospital_patient WHERE patient_id='{PATIENT}'") == "0"
    created_users: list[UUID] = []
    created_emails: list[str] = []
    anonymous_marker = uuid4().hex

    def create_user(name: str) -> tuple[UUID, str]:
        email = f"kof5-{name}-{uuid4().hex}@example.invalid"
        created_emails.append(email)
        password = secrets.token_urlsafe(24)
        status, user = request(f"{url}/auth/v1/admin/users", "POST", admin,
                               payload={"email": email, "password": password,
                                        "email_confirm": True})
        assert status in (200, 201), f"local {name} Auth create failed: {status}"
        user_id = UUID(user["id"])
        created_users.append(user_id)
        status, session = request(f"{url}/auth/v1/token?grant_type=password", "POST",
                                  public, payload={"email": email, "password": password})
        assert status == 200, f"local {name} Auth login failed: {status}"
        return user_id, session["access_token"]

    try:
        staff, staff_token = create_user("staff")
        unassigned, unassigned_token = create_user("unassigned")
        guardian, _ = create_user("guardian")
        status, anonymous = request(f"{url}/auth/v1/signup", "POST", public,
                                    payload={"data": {"kof5_synthetic_run": anonymous_marker},
                                             "gotrue_meta_security": {"captcha_token": None}})
        assert status == 200 and anonymous["user"]["is_anonymous"] is True, \
            f"task-local anonymous Auth failed: {status}"
        device = UUID(anonymous["user"]["id"])
        created_users.append(device)
        device_token = anonymous["access_token"]
        assert sql("SELECT raw_user_meta_data ->> 'kof5_synthetic_run' "
                   f"FROM auth.users WHERE id='{device}';") == anonymous_marker, \
            "anonymous response-loss cleanup marker was not stored"

        sql(f"""
            INSERT INTO kof5.hospital_patient
              (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
            VALUES ('{PATIENT}', '{HOSPITAL}', 'TEST-DEVICE-P', '가상 환자', 'TEST-STAFF');
            INSERT INTO kof5.hospital_encounter
              (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
            VALUES ('{ENCOUNTER}', '{PATIENT}', 'TEST-DEVICE-E', 'in_progress', now()-interval '1 day');
            INSERT INTO kof5.hospital_registry_activation
              (hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref, approved_at)
            VALUES ('{HOSPITAL}', 'approved', 'TEST-INSTITUTION', 'TEST-CLINICAL', now()-interval '1 day');
            INSERT INTO kof5.hospital_staff_membership
              (auth_user_id, hospital_ref, product_role, status, effective_at,
               verified_by_staff_ref, verified_at)
            VALUES ('{staff}', '{HOSPITAL}', 'care_staff', 'verified', now()-interval '1 day',
                    'TEST-VERIFY', now());
            INSERT INTO kof5.hospital_staff_assignment
              (membership_id, hospital_ref, patient_id, status, effective_at,
               verified_by_staff_ref, verified_at)
            SELECT membership_id, '{HOSPITAL}', '{PATIENT}', 'verified', now()-interval '1 day',
                   'TEST-VERIFY', now() FROM kof5.hospital_staff_membership
            WHERE auth_user_id='{staff}';
            INSERT INTO kof5.consent_record
              (patient_id, scope, signer_role, signer_ref, assent_status, status,
               effective_at, recorded_by_staff_ref)
            VALUES
              ('{PATIENT}', 'patient_participation', 'patient', 'TEST-SIGNER', 'assented',
               'active', now()-interval '1 day', 'TEST-STAFF'),
              ('{PATIENT}', 'ambient_processing', 'patient', 'TEST-SIGNER', 'assented',
               'active', now()-interval '1 day', 'TEST-STAFF'),
              ('{PATIENT}', 'patient_voice_feature', 'patient', 'TEST-SIGNER', 'assented',
               'active', now()-interval '1 day', 'TEST-STAFF');
            INSERT INTO kof5.patient_voice_profile
              (patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
               embedding_model, embedding_version, encrypted_embedding_ref, quality_status,
               enrolled_by_staff_ref, enrolled_at)
            SELECT '{PATIENT}', '{ENCOUNTER}', consent_id, 'active', 30000,
                   'TEST-MODEL', 'TEST-VERSION', 'TEST-FAKE-VOICE-REF', 'accepted',
                   'TEST-STAFF', now()-interval '1 day'
            FROM kof5.consent_record
            WHERE patient_id='{PATIENT}' AND scope='patient_voice_feature';
            INSERT INTO kof5.patient_guardian_link
              (patient_id, guardian_user_id, relationship, access_status, effective_at,
               verified_by_staff_ref, verified_at)
            VALUES ('{PATIENT}', '{guardian}', '가상 가족', 'verified', now()-interval '1 day',
                    'TEST-VERIFY', now());
            INSERT INTO kof5.family_fact
              (patient_id, author_guardian_user_id, category, content)
            VALUES ('{PATIENT}', '{guardian}', 'travel', '2024년 5월 제주도에 함께 갔었다.');
        """)

        base = f"{url}/rest/v1"
        ready = f"{base}/synthetic_device_pairing_ready?select=patient_id,encounter_id"
        context = f"{base}/patient_device_context?select=patient_id,encounter_id"
        search = f"{base}/rpc/patient_family_search"
        turn_context = f"{base}/rpc/patient_family_turn_context"
        pair = f"{base}/patient_device_pairing"
        status, rows = request(ready, "GET", public, unassigned_token, schema="api")
        assert status == 200 and rows == [], "unassigned staff saw pairing readiness"
        status, rows = request(ready, "GET", public, staff_token, schema="api")
        assert status == 200 and rows == [{"patient_id": str(PATIENT),
                                          "encounter_id": str(ENCOUNTER)}], \
            "assigned staff pairing readiness missing"
        status, rows = request(context, "GET", public, device_token, schema="api")
        assert status == 200 and rows == [], "unpaired device saw a patient"
        due = (datetime.now(timezone.utc) + timedelta(hours=7)).isoformat()
        payload = {"device_user_id": str(device), "patient_id": str(PATIENT),
                   "encounter_id": str(ENCOUNTER), "expires_at": due}
        status, _ = request(pair, "POST", public, unassigned_token, payload, schema="api")
        assert status in (401, 403), f"unassigned staff paired device: {status}"
        status, _ = request(pair, "POST", public, device_token, payload, schema="api")
        assert status in (401, 403), f"device self-paired: {status}"
        status, _ = request(pair, "POST", public, staff_token, payload, schema="api")
        assert status == 201, f"assigned staff pairing failed: {status}"
        status, rows = request(context, "GET", public, device_token, schema="api")
        assert status == 200 and rows == [{"patient_id": str(PATIENT),
                                          "encounter_id": str(ENCOUNTER)}], \
            "paired device lacked current context"
        status, facts = request(search, "POST", public, device_token,
                                {"p_patient_id": str(PATIENT),
                                 "p_term": "제주도 언제 갔었어?"}, schema="api")
        assert status == 200 and facts == [{"category": "travel",
                                            "content": "2024년 5월 제주도에 함께 갔었다."}], \
            "paired device failed bounded family retrieval"
        status, turn = request(turn_context, "POST", public, device_token,
                               {"p_patient_id": str(PATIENT),
                                "p_term": "제주도 언제 갔었어?"}, schema="api")
        assert status == 200 and turn == [{"authorized": True, "facts": facts}], \
            "atomic paired-turn context missed a current fact"
        status, rows = request(f"{base}/family_context?select=content", "GET", public,
                               device_token, schema="api")
        assert status == 200 and rows == [], "device enumerated guardian edit view"
        # Even an institution mistake that verifies this device as a guardian
        # cannot turn its Auth identity into a family-memory author.
        sql(f"""
            INSERT INTO kof5.patient_guardian_link
              (patient_id, guardian_user_id, relationship, access_status, effective_at,
               verified_by_staff_ref, verified_at)
            VALUES ('{PATIENT}', '{device}', '가상 잘못된 연결', 'verified', now()-interval '1 day',
                    'TEST-VERIFY', now());
            INSERT INTO kof5.family_fact
              (patient_id, author_guardian_user_id, category, content)
            VALUES ('{PATIENT}', '{device}', 'favorite_story', '가상 장치오류 기억');
        """)
        status, rows = request(f"{base}/family_context?select=content", "GET", public,
                               device_token, schema="api")
        assert status == 200 and rows == [], "misissued guardian link exposed edit view"
        status, facts = request(search, "POST", public, device_token,
                                {"p_patient_id": str(PATIENT), "p_term": "장치오류 알려줘"},
                                schema="api")
        assert status == 200 and facts == [], "anonymous-authored fact reached patient memory"
        status, turn = request(turn_context, "POST", public, device_token,
                               {"p_patient_id": str(PATIENT), "p_term": "장치오류 알려줘"},
                               schema="api")
        assert status == 200 and turn == [{"authorized": True, "facts": []}], \
            "authorized empty memory must exclude anonymous author"
        status, _ = request(f"{base}/family_context", "POST", public, device_token,
                            {"patient_id": str(PATIENT),
                             "author_guardian_user_id": str(device),
                             "category": "family", "content": "잘못 쓴 기억"}, schema="api")
        assert status != 201, "misissued device wrote a family memory"
        status, changed = request(
            f"{base}/family_context?author_guardian_user_id=eq.{device}", "PATCH",
            public, device_token, {"content": "잘못 수정한 기억"}, schema="api",
        )
        assert status != 200 or changed == [], "misissued device edited family memory"
        assert sql(f"SELECT content FROM kof5.family_fact WHERE patient_id='{PATIENT}' "
                   f"AND author_guardian_user_id='{device}'") == "가상 장치오류 기억", \
            "device-authored synthetic fact changed"
        backend_env = {
            "KOF5_SUPABASE_URL": url,
            "KOF5_SUPABASE_PUBLISHABLE_KEY": public,
            "KOF5_INTERNAL_DEMO_TOKEN": "t" * 32,
            "VOICE_OWNER_CONSENT_RECORD_ID": "synthetic-owner-consent",
            "DEEPGRAM_API_KEY": "mock-deepgram",
            "OPENAI_API_KEY": "mock-openai",
            "ELEVENLABS_API_KEY": "mock-elevenlabs",
            "ELEVENLABS_VOICE_ID": "mock-voice",
        }
        backend_headers = {
            "Authorization": f"Bearer {device_token}",
            "X-Internal-Demo-Token": backend_env["KOF5_INTERNAL_DEMO_TOKEN"],
            "X-Synthetic-Material": "confirmed",
        }
        backend_path = f"/internal/synthetic/paired/{PATIENT}/text"
        with patch.dict(os.environ, backend_env), patch(
            "kof5_tts.api.run_synthetic_text_pipeline",
            return_value=("2024년 5월에 같이 갔었어.", b"mock-mp3"),
        ) as hosted, TestClient(app) as backend:
            response = backend.post(backend_path, json={
                "transcript": "제주도 언제 갔었어?", "label": "DIRECTED",
            }, headers=backend_headers)
            assert response.status_code == 200, f"paired backend turn failed: {response.status_code}"
            assert hosted.call_args.args[3] == "2024년 5월 제주도에 함께 갔었다.", \
                "backend did not use current RLS family memory"
            assert response.json()["audio_mp3_base64"] is not None
        sql(f"UPDATE kof5.patient_guardian_link SET access_status='revoked', revoked_at=now() "
            f"WHERE patient_id='{PATIENT}' AND guardian_user_id='{guardian}';")
        status, facts = request(search, "POST", public, device_token,
                                {"p_patient_id": str(PATIENT), "p_term": "제주도 언제 갔었어?"},
                                schema="api")
        assert status == 200 and facts == [], "guardian revocation left fact visible"
        status, turn = request(turn_context, "POST", public, device_token,
                               {"p_patient_id": str(PATIENT),
                                "p_term": "제주도 언제 갔었어?"}, schema="api")
        assert status == 200 and turn == [{"authorized": True, "facts": []}], \
            "guardian withdrawal must be authorized-but-memory-empty"
        with patch.dict(os.environ, backend_env), patch(
            "kof5_tts.api.run_synthetic_text_pipeline", return_value=("모르겠어.", b"mock-mp3"),
        ) as hosted, TestClient(app) as backend:
            response = backend.post(backend_path, json={
                "transcript": "제주도 언제 갔었어?", "label": "DIRECTED",
            }, headers=backend_headers)
            assert response.status_code == 200 and hosted.call_args.args[3] == "", \
                "backend reused memory after guardian revocation"
        sql(f"UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now() "
            f"WHERE patient_id='{PATIENT}' AND scope='ambient_processing';")
        status, rows = request(context, "GET", public, device_token, schema="api")
        assert status == 200 and rows == [], "ambient withdrawal left device active"
        status, turn = request(turn_context, "POST", public, device_token,
                               {"p_patient_id": str(PATIENT),
                                "p_term": "제주도 언제 갔었어?"}, schema="api")
        assert status == 200 and turn == [{"authorized": False, "facts": []}], \
            "consent withdrawal must be explicit authorization failure"
        with patch.dict(os.environ, backend_env), patch(
            "kof5_tts.api.run_synthetic_text_pipeline", return_value=("unsafe", b"mock-mp3"),
        ) as hosted, TestClient(app) as backend:
            response = backend.post(backend_path, json={
                "transcript": "제주도 언제 갔었어?", "label": "DIRECTED",
            }, headers=backend_headers)
            assert response.status_code == 403, "backend used device after ambient withdrawal"
            hosted.assert_not_called()
        print("Task-local Auth → staff pair → atomic device memory/FastAPI → revocation: PASS")
    finally:
        try:
            sql(f"""
                DELETE FROM kof5.patient_device_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.family_fact WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_guardian_link WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.patient_voice_profile WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.consent_record WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_assignment WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_staff_membership WHERE hospital_ref='{HOSPITAL}';
                DELETE FROM kof5.hospital_encounter WHERE patient_id='{PATIENT}';
                DELETE FROM kof5.hospital_registry_activation WHERE hospital_ref='{HOSPITAL}';
                DELETE FROM kof5.hospital_patient WHERE patient_id='{PATIENT}';
            """)
        finally:
            recovered = set(created_users)
            for email in created_emails:
                found = sql(f"SELECT id FROM auth.users WHERE email='{email}';")
                if found:
                    recovered.add(UUID(found))
            found = sql("SELECT id FROM auth.users WHERE is_anonymous IS TRUE "
                        f"AND raw_user_meta_data ->> 'kof5_synthetic_run'='{anonymous_marker}';")
            if found:
                recovered.add(UUID(found))
            for user_id in recovered:
                status, _ = request(f"{url}/auth/v1/admin/users/{user_id}", "DELETE", admin)
                assert status in (200, 204), f"local synthetic Auth cleanup failed: {status}"


if __name__ == "__main__":
    main()
