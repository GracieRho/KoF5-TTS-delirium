BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT no_plan();

-- Pinned fixture975 and TEST-* users exist only inside this rollback.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000991', false), -- assigned care_staff
    ('00000000-0000-4000-8000-000000000993', false), -- unassigned staff
    ('00000000-0000-4000-8000-000000000994', true);  -- misissued anonymous care_staff
INSERT INTO kof5.hospital_patient
    (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975', 'TEST-ENROLL-H',
        'TEST-ENROLL-P', '가상 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter
    (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
VALUES ('00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000975', 'TEST-ENROLL-E',
        'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation
    (hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref, approved_at)
VALUES ('TEST-ENROLL-H', 'approved', 'TEST-INSTITUTION', 'TEST-CLINICAL',
        now() - interval '1 day');
INSERT INTO kof5.hospital_staff_membership
    (membership_id, auth_user_id, hospital_ref, product_role, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961',
        '00000000-0000-4000-8000-000000000991', 'TEST-ENROLL-H',
        'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962',
        '00000000-0000-4000-8000-000000000994', 'TEST-ENROLL-H',
        'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment
    (membership_id, hospital_ref, patient_id, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-ENROLL-H',
        '00000000-0000-4000-8000-000000000975', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962', 'TEST-ENROLL-H',
        '00000000-0000-4000-8000-000000000975', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.consent_record
    (consent_id, patient_id, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000981',
        '00000000-0000-4000-8000-000000000975', 'patient_participation',
        'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000983',
        '00000000-0000-4000-8000-000000000975', 'patient_voice_feature',
        'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF');

SELECT ok(NOT has_function_privilege('anon',
    'api.synthetic_voice_enrollment_ready()', 'EXECUTE'),
    'signed-out role cannot call enrollment readiness');
SELECT ok(NOT has_function_privilege('service_role',
    'api.synthetic_voice_enrollment_ready()', 'EXECUTE'),
    'service role has no public readiness call');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid =
    'api.synthetic_voice_enrollment_ready()'::regprocedure),
    'exposed readiness RPC is invoker');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.patient_voice_profile', 'SELECT'),
    'staff app still cannot read private voice profile directly');
SELECT is((SELECT count(*)::integer FROM kof5.patient_voice_profile
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'), 0,
    'first-enrollment fixture has no voice profile');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT ready IS FALSE AND patient_id IS NULL
    AND voice_profile_state IS NULL FROM api.synthetic_voice_enrollment_ready()),
    'misissued anonymous care_staff cannot see readiness');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000993', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000993","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE AND patient_id IS NULL
    AND voice_profile_state IS NULL FROM api.synthetic_voice_enrollment_ready()),
    'permanent unassigned staff cannot see readiness');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready AND patient_id =
    '00000000-0000-4000-8000-000000000975'::uuid
    AND voice_profile_state = 'none' FROM api.synthetic_voice_enrollment_ready()),
    'assigned care_staff ready before any voice profile or ambient consent exists');
RESET ROLE;

UPDATE kof5.consent_record SET status = 'draft', assent_status = 'declined'
WHERE consent_id = '00000000-0000-4000-8000-000000000981';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE AND voice_profile_state = 'none'
    FROM api.synthetic_voice_enrollment_ready()),
    'declined participation assent blocks first enrollment');
RESET ROLE;
UPDATE kof5.consent_record SET status = 'active', assent_status = 'assented'
WHERE consent_id = '00000000-0000-4000-8000-000000000981';
UPDATE kof5.consent_record SET expires_at = now() - interval '1 hour'
WHERE consent_id = '00000000-0000-4000-8000-000000000983';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE FROM api.synthetic_voice_enrollment_ready()),
    'stale patient voice-feature consent blocks enrollment');
RESET ROLE;
UPDATE kof5.consent_record SET expires_at = NULL
WHERE consent_id = '00000000-0000-4000-8000-000000000983';
UPDATE kof5.hospital_registry_activation SET expires_at = now() - interval '1 hour'
WHERE hospital_ref = 'TEST-ENROLL-H';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE FROM api.synthetic_voice_enrollment_ready()),
    'expired institution approval blocks enrollment');
RESET ROLE;
UPDATE kof5.hospital_registry_activation SET expires_at = NULL
WHERE hospital_ref = 'TEST-ENROLL-H';

INSERT INTO kof5.patient_voice_profile
    (profile_id, patient_id, encounter_id, consent_id, status,
     quality_status, enrolled_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000984',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000983',
        'pending', 'pending', 'TEST-STAFF');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready AND voice_profile_state = 'pending'
    FROM api.synthetic_voice_enrollment_ready()),
    'readiness reports pending profile without making it a prerequisite');
RESET ROLE;
UPDATE kof5.patient_voice_profile
SET status = 'active', quality_status = 'accepted', enrollment_duration_ms = 30000,
    embedding_model = 'TEST-MODEL', embedding_version = 'TEST-VERSION',
    encrypted_embedding_ref = 'TEST-NOT-A-VOICE', enrolled_at = now()
WHERE profile_id = '00000000-0000-4000-8000-000000000984';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready AND voice_profile_state = 'active'
    FROM api.synthetic_voice_enrollment_ready()),
    'active state is informational and does not create circular readiness');
RESET ROLE;
UPDATE kof5.patient_voice_profile SET status = 'revoked', revoked_at = now()
WHERE profile_id = '00000000-0000-4000-8000-000000000984';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready AND voice_profile_state = 'revoked'
    FROM api.synthetic_voice_enrollment_ready()),
    'terminal profile state is visible but does not authorize profile reuse');
RESET ROLE;
UPDATE kof5.patient_voice_profile SET status = 'deleted', deleted_at = now()
WHERE profile_id = '00000000-0000-4000-8000-000000000984';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready AND voice_profile_state = 'deleted'
    FROM api.synthetic_voice_enrollment_ready()),
    'deleted state is reported without exposing voice material');
RESET ROLE;

UPDATE kof5.hospital_encounter SET status = 'finished', discharged_at = now()
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE AND patient_id =
    '00000000-0000-4000-8000-000000000975'::uuid
    AND voice_profile_state = 'none' FROM api.synthetic_voice_enrollment_ready()),
    'finished encounter blocks enrollment and hides former profile state');
RESET ROLE;
UPDATE kof5.hospital_encounter SET status = 'in_progress', discharged_at = NULL
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
INSERT INTO kof5.safety_audit_event (patient_id, event_type)
VALUES ('00000000-0000-4000-8000-000000000975', 'patient_dissent');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE FROM api.synthetic_voice_enrollment_ready()),
    'patient dissent during current admission blocks enrollment');
RESET ROLE;
UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000983';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE FROM api.synthetic_voice_enrollment_ready()),
    'withdrawn voice-feature consent blocks enrollment');
RESET ROLE;
UPDATE kof5.hospital_staff_assignment SET status = 'revoked', revoked_at = now()
WHERE membership_id = '00000000-0000-4000-8000-000000000961';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT ready IS FALSE AND patient_id IS NULL
    AND voice_profile_state IS NULL FROM api.synthetic_voice_enrollment_ready()),
    'revoked care_staff assignment removes all readiness fields');

SELECT * FROM finish();
ROLLBACK;
