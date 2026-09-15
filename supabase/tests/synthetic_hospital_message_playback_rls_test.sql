BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(23);

-- Fixture 975 is a synthetic sentinel, not a patient. This transaction rolls back.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000991', false), -- proposer
    ('00000000-0000-4000-8000-000000000992', false), -- distinct approver
    ('00000000-0000-4000-8000-000000000993', false), -- unassigned staff
    ('00000000-0000-4000-8000-000000000994', true),  -- paired iPad
    ('00000000-0000-4000-8000-000000000995', true),  -- unpaired iPad
    ('00000000-0000-4000-8000-000000000996', false); -- guardian
INSERT INTO kof5.hospital_patient
    (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975', 'TEST-PLAYBACK-H', 'TEST-P975', '가상 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter
    (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
VALUES ('00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000975', 'TEST-E975', 'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation
    (hospital_ref, status, institution_approval_ref, clinical_safety_approval_ref, approved_at)
VALUES ('TEST-PLAYBACK-H', 'approved', 'TEST-INSTITUTION', 'TEST-SAFETY', now() - interval '1 day');
INSERT INTO kof5.hospital_staff_membership
    (membership_id, auth_user_id, hospital_ref, product_role, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961', '00000000-0000-4000-8000-000000000991',
        'TEST-PLAYBACK-H', 'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962', '00000000-0000-4000-8000-000000000992',
        'TEST-PLAYBACK-H', 'care_staff', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000963', '00000000-0000-4000-8000-000000000994',
        'TEST-PLAYBACK-H', 'registrar', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.hospital_staff_assignment
    (membership_id, hospital_ref, patient_id, status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000961', 'TEST-PLAYBACK-H',
        '00000000-0000-4000-8000-000000000975', 'verified', now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000962', 'TEST-PLAYBACK-H',
        '00000000-0000-4000-8000-000000000975', 'verified', now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.consent_record
    (consent_id, patient_id, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000981', '00000000-0000-4000-8000-000000000975',
        'patient_participation', 'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000982', '00000000-0000-4000-8000-000000000975',
        'ambient_processing', 'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000983', '00000000-0000-4000-8000-000000000975',
        'patient_voice_feature', 'patient', 'TEST-SIGNER', 'assented', 'active', now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile
    (patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
     embedding_model, embedding_version, encrypted_embedding_ref, quality_status,
     enrolled_by_staff_ref, enrolled_at)
VALUES ('00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000983', 'active', 30000,
        'TEST-MODEL', 'TEST-VERSION', 'TEST-NOT-A-VOICE', 'accepted', 'TEST-STAFF', now() - interval '1 day');
INSERT INTO kof5.patient_device_assignment
    (device_user_id, patient_id, encounter_id, paired_by_staff_user_id, expires_at)
VALUES ('00000000-0000-4000-8000-000000000994', '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976', '00000000-0000-4000-8000-000000000991',
        now() + interval '2 hours');

SELECT ok(NOT has_function_privilege('anon',
    'api.synthetic_hospital_message_playback_complete(uuid,uuid,uuid)', 'EXECUTE'),
    'signed-out role cannot call completion RPC');
SELECT ok(NOT has_function_privilege('service_role',
    'api.synthetic_hospital_message_playback_complete(uuid,uuid,uuid)', 'EXECUTE'),
    'service key cannot call exposed completion RPC');
SELECT ok(has_function_privilege('authenticated',
    'api.synthetic_hospital_message_playback_complete(uuid,uuid,uuid)', 'EXECUTE'),
    'signed-in paired device can call invoker RPC');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid =
    'api.synthetic_hospital_message_playback_complete(uuid,uuid,uuid)'::regprocedure),
    'completion RPC is invoker');
SELECT ok(NOT has_table_privilege('authenticated', 'kof5.hospital_message', 'INSERT'),
    'device cannot manufacture approved message');

-- Actual separate staff proposal/approval creates an exact current due message.
GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
INSERT INTO api.synthetic_hospital_message_draft
    (patient_id, encounter_id, proposed_text, schedule_mode)
VALUES ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976', '가상 승인 안내 원문', 'now');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000992', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000992","is_anonymous":false}', true);
UPDATE api.synthetic_hospital_message_draft SET status='approved'
WHERE proposed_text='가상 승인 안내 원문';
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM kof5.hospital_message), 1,
    'distinct staff approval produced exactly one pending message');
SELECT set_config('test.playback_message_id',
    (SELECT message_id::text FROM kof5.hospital_message
     WHERE approved_text='가상 승인 안내 원문'), true);

-- Privileged synthetic fixtures test non-due/old/direct-origin boundaries.
INSERT INTO kof5.synthetic_hospital_message_draft (
    draft_id, patient_id, encounter_id, proposed_text, schedule_mode,
    requested_due_at, proposed_by_auth_user_id, status,
    approved_by_auth_user_id, approved_at
) VALUES
    ('00000000-0000-4000-8000-000000000941',
     '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000976',
     '가상 미래 안내 원문', 'scheduled', now() + interval '1 hour',
     '00000000-0000-4000-8000-000000000991', 'approved',
     '00000000-0000-4000-8000-000000000992', now()),
    ('00000000-0000-4000-8000-000000000942',
     '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000976',
     '가상 출처 안 맞는 문구', 'now', NULL,
     '00000000-0000-4000-8000-000000000991', 'approved',
     '00000000-0000-4000-8000-000000000992', now()),
    ('00000000-0000-4000-8000-000000000945',
     '00000000-0000-4000-8000-000000000975',
     '00000000-0000-4000-8000-000000000976',
     '가상 별도 승인 안내', 'now', NULL,
     '00000000-0000-4000-8000-000000000991', 'approved',
     '00000000-0000-4000-8000-000000000992', now());
INSERT INTO kof5.hospital_message (
    message_id, patient_id, encounter_id, approved_text,
    approved_by_staff_ref, approved_at, due_at
) SELECT draft_id, patient_id, encounter_id, proposed_text,
         approved_by_auth_user_id::text, approved_at, requested_due_at
    FROM kof5.synthetic_hospital_message_draft
    WHERE draft_id = '00000000-0000-4000-8000-000000000941';
INSERT INTO kof5.hospital_message (
    message_id, patient_id, encounter_id, approved_text,
    approved_by_staff_ref, approved_at, due_at
) VALUES ('00000000-0000-4000-8000-000000000942',
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000976',
    '가상 위조 문구', '00000000-0000-4000-8000-000000000992',
    now(), now());
INSERT INTO kof5.hospital_message (
    message_id, patient_id, encounter_id, approved_text,
    approved_by_staff_ref, approved_at, due_at
) VALUES ('00000000-0000-4000-8000-000000000945',
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000976',
    '가상 별도 승인 안내', '00000000-0000-4000-8000-000000000992',
    now(), now());
INSERT INTO kof5.hospital_encounter (
    encounter_id, patient_id, ehr_encounter_ref, status,
    admitted_at, discharged_at
) VALUES ('00000000-0000-4000-8000-000000000979',
    '00000000-0000-4000-8000-000000000975', 'TEST-OLD', 'finished',
    now() - interval '3 days', now() - interval '2 days');
INSERT INTO kof5.synthetic_hospital_message_draft (
    draft_id, patient_id, encounter_id, proposed_text, schedule_mode,
    proposed_by_auth_user_id, status, approved_by_auth_user_id, approved_at
) VALUES ('00000000-0000-4000-8000-000000000943',
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000979',
    '가상 이전 입원 안내', 'now',
    '00000000-0000-4000-8000-000000000991', 'approved',
    '00000000-0000-4000-8000-000000000992', now());
INSERT INTO kof5.hospital_message (
    message_id, patient_id, encounter_id, approved_text,
    approved_by_staff_ref, approved_at, due_at
) VALUES ('00000000-0000-4000-8000-000000000943',
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000979',
    '가상 이전 입원 안내', '00000000-0000-4000-8000-000000000992',
    now(), now());

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000951'), false,
    'assigned staff cannot spoof native device playback');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000996', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000996","is_anonymous":false}', true);
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000951'), false,
    'guardian cannot claim playback');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000995', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000995","is_anonymous":true}', true);
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000951'), false,
    'unpaired anonymous device cannot claim playback');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000977',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000951'), false,
    'nonfixture patient UUID cannot be completed');
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-1000-8000-000000000951'), false,
    'non-v4 attempt UUID is denied');
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000941',
    '00000000-0000-4000-8000-000000000951'), false,
    'future scheduled message is not due');
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000942',
    '00000000-0000-4000-8000-000000000951'), false,
    'spoofed original text is denied despite pending due row');
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000943',
    '00000000-0000-4000-8000-000000000951'), false,
    'finished previous admission message is denied');
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000951'), true,
    'current paired device claims native completion of exact due original');
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000951'), true,
    'same current device and attempt can safely retry');
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000952'), false,
    'different attempt cannot overwrite delivered receipt');
RESET ROLE;
SELECT is((SELECT delivery_status FROM kof5.hospital_message
    WHERE approved_text='가상 승인 안내 원문'), 'delivered',
    'fresh completion atomically marks delivered');
SELECT ok((SELECT delivered_at IS NOT NULL
    AND delivered_by_device_user_id = '00000000-0000-4000-8000-000000000994'
    AND playback_attempt_id = '00000000-0000-4000-8000-000000000951'
    AND approved_text='가상 승인 안내 원문'
    FROM kof5.hospital_message WHERE approved_text='가상 승인 안내 원문'),
    'receipt binds approved original to device and UUIDv4 attempt');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is((SELECT count(*)::integer FROM api.synthetic_due_hospital_message_ids(
    '00000000-0000-4000-8000-000000000975')
    WHERE message_id = current_setting('test.playback_message_id')::uuid), 0,
    'delivered message is absent from device due discovery');
RESET ROLE;

INSERT INTO kof5.patient_device_assignment (
    device_user_id, patient_id, encounter_id, paired_by_staff_user_id, expires_at
) VALUES ('00000000-0000-4000-8000-000000000995',
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000976',
    '00000000-0000-4000-8000-000000000991', now() + interval '2 hours');
UPDATE kof5.patient_device_assignment SET status='revoked', revoked_at=now()
WHERE device_user_id='00000000-0000-4000-8000-000000000995';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000995', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000995","is_anonymous":true}', true);
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000945',
    '00000000-0000-4000-8000-000000000953'), false,
    'revoked paired device cannot complete a separate pending due message');
RESET ROLE;

INSERT INTO kof5.safety_audit_event (patient_id,event_type)
VALUES ('00000000-0000-4000-8000-000000000975','patient_dissent');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000945',
    '00000000-0000-4000-8000-000000000953'), false,
    'post-admission dissent denies a fresh pending due completion');
RESET ROLE;
DELETE FROM kof5.safety_audit_event
WHERE patient_id='00000000-0000-4000-8000-000000000975'
  AND event_type='patient_dissent';

UPDATE kof5.consent_record SET status='withdrawn', withdrawn_at=now()
WHERE consent_id='00000000-0000-4000-8000-000000000982';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT is(api.synthetic_hospital_message_playback_complete(
    '00000000-0000-4000-8000-000000000975',
    current_setting('test.playback_message_id')::uuid,
    '00000000-0000-4000-8000-000000000951'), false,
    'withdrawn consent denies even identical receipt replay');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
