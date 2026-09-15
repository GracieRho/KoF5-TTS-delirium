BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT plan(32);

-- All IDs and references are fixed synthetic values; transaction rolls back.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000991', false),
    ('00000000-0000-4000-8000-000000000994', true),
    ('00000000-0000-4000-8000-000000000996', true),
    ('00000000-0000-4000-8000-000000000997', true);
INSERT INTO kof5.hospital_patient
    (patient_id, hospital_ref, ehr_patient_ref, staff_display_name,
     registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975', 'TEST-SESSION-H',
        'TEST-P975', '가상 환자', 'TEST-STAFF');
INSERT INTO kof5.hospital_encounter
    (encounter_id, patient_id, ehr_encounter_ref, status, admitted_at)
VALUES ('00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000975', 'TEST-E975',
        'in_progress', now() - interval '1 day');
INSERT INTO kof5.hospital_registry_activation
    (hospital_ref, status, institution_approval_ref,
     clinical_safety_approval_ref, approved_at)
VALUES ('TEST-SESSION-H', 'approved', 'TEST-INSTITUTION',
        'TEST-SAFETY', now() - interval '1 day');
INSERT INTO kof5.consent_record
    (consent_id, patient_id, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000981',
        '00000000-0000-4000-8000-000000000975', 'patient_participation',
        'patient', 'TEST-SIGNER', 'assented', 'active',
        now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000982',
        '00000000-0000-4000-8000-000000000975', 'ambient_processing',
        'patient', 'TEST-SIGNER', 'assented', 'active',
        now() - interval '1 day', 'TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000983',
        '00000000-0000-4000-8000-000000000975', 'patient_voice_feature',
        'patient', 'TEST-SIGNER', 'assented', 'active',
        now() - interval '1 day', 'TEST-STAFF');
INSERT INTO kof5.patient_voice_profile
    (patient_id, encounter_id, consent_id, status, enrollment_duration_ms,
     embedding_model, embedding_version, encrypted_embedding_ref,
     quality_status, enrolled_by_staff_ref, enrolled_at)
VALUES ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000983', 'active', 30000,
        'TEST-MODEL', 'TEST-VERSION', 'TEST-NOT-A-VOICE', 'accepted',
        'TEST-STAFF', now() - interval '1 day');
INSERT INTO kof5.patient_device_assignment
    (device_user_id, patient_id, encounter_id, paired_by_staff_user_id,
     expires_at)
VALUES ('00000000-0000-4000-8000-000000000994',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000991', now() + interval '2 hours'),
       ('00000000-0000-4000-8000-000000000996',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000976',
        '00000000-0000-4000-8000-000000000991', now() + interval '2 hours');

SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
    WHERE oid = 'kof5.synthetic_conversation_session'::regclass),
    'private session row uses FORCE RLS');
SELECT ok(NOT has_table_privilege('authenticated',
    'kof5.synthetic_conversation_session', 'SELECT'),
    'no device has direct session table read');
SELECT ok(NOT has_function_privilege('anon',
    'api.synthetic_conversation_session_read(uuid)', 'EXECUTE'),
    'signed-out Data API cannot call session read');
SELECT ok(NOT EXISTS (
    SELECT 1 FROM pg_attribute a
    WHERE a.attrelid = 'kof5.synthetic_conversation_session'::regclass
      AND a.attnum > 0 AND NOT a.attisdropped
      AND a.attname IN ('transcript', 'audio', 'prompt', 'reply', 'pcm', 'wav')),
    'session stores no speech or provider content');

GRANT authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000991', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000991","is_anonymous":false}', true);
SELECT ok((SELECT authorized IS FALSE AND session_id IS NULL
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'permanent staff cannot impersonate anonymous device');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000997', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000997","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'unpaired anonymous device is denied');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000977')),
    'nonfixture patient never gets a session');
SELECT ok((SELECT authorized IS TRUE
           AND encounter_id = '00000000-0000-4000-8000-000000000976'
           AND session_id IS NULL AND version = 0 AND state = 'IDLE'
           AND proactive_paused IS FALSE
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'current paired device reads initial IDLE state');
SELECT ok((SELECT authorized IS TRUE AND committed IS TRUE
           AND session_id IS NOT NULL AND version = 1
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000841')),
    'first routed turn atomically creates an ACTIVE session');
SELECT ok((SELECT authorized IS TRUE AND state = 'ACTIVE_LISTENING'
           AND version = 1 AND last_activity IS NOT NULL
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'next function invocation sees persisted ACTIVE state');
SELECT ok((SELECT authorized IS TRUE AND committed IS FALSE
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000841')),
    'immediate same-turn replay is refused');
SELECT ok((SELECT authorized IS TRUE AND committed IS FALSE
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000842')),
    'different stale CAS version is refused');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000996', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000996","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'second simultaneously paired iPad cannot read the active owner session');
SELECT ok((SELECT authorized IS TRUE AND committed IS FALSE
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000843')),
    'second iPad cannot overwrite active owner even with fresh turn UUID');
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND committed IS TRUE AND version = 2
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975',
        (SELECT session_id FROM api.synthetic_conversation_session_read(
            '00000000-0000-4000-8000-000000000975')), 1,
        'IDLE', false, '00000000-0000-4000-8000-000000000844')),
    'explicit close persists IDLE');
SELECT ok((SELECT authorized IS TRUE AND committed IS TRUE AND version = 3
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975',
        (SELECT session_id FROM api.synthetic_conversation_session_read(
            '00000000-0000-4000-8000-000000000975')), 2,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000845')),
    'closed session may begin a later directed turn');
RESET ROLE;
UPDATE kof5.synthetic_conversation_session
SET last_activity = now() - interval '46 seconds'
WHERE patient_id = '00000000-0000-4000-8000-000000000975';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND state = 'IDLE'
           AND last_activity IS NULL AND version = 3 AND session_id IS NOT NULL
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    '45-second ACTIVE silence projects IDLE without losing CAS token');
SELECT ok((SELECT authorized IS TRUE AND committed IS TRUE AND version = 4
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975',
        (SELECT session_id FROM api.synthetic_conversation_session_read(
            '00000000-0000-4000-8000-000000000975')), 3,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000846')),
    'fresh directed turn commits after expiry under same version CAS');

RESET ROLE;
SAVEPOINT withdrawal_test;
UPDATE kof5.consent_record
SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000981';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'withdrawn participation consent closes routing read');
SELECT ok((SELECT authorized IS FALSE AND committed IS FALSE
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000847')),
    'withdrawn consent stops CAS commit before provider work');
RESET ROLE;
ROLLBACK TO SAVEPOINT withdrawal_test;

SAVEPOINT dissent_test;
INSERT INTO kof5.safety_audit_event (patient_id, event_type)
VALUES ('00000000-0000-4000-8000-000000000975', 'patient_dissent');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND proactive_paused IS TRUE
           AND state = 'IDLE'
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'post-admission dissent reports terminal pause to current device');
SELECT ok((SELECT authorized IS FALSE AND committed IS FALSE
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000848')),
    'post-admission dissent closes routing commit');
RESET ROLE;
ROLLBACK TO SAVEPOINT dissent_test;

SAVEPOINT takeover_test;
UPDATE kof5.patient_device_assignment
SET status = 'revoked', revoked_at = now()
WHERE device_user_id = '00000000-0000-4000-8000-000000000994';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000996', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000996","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND state = 'IDLE'
           AND session_id IS NULL AND version = 0
           AND proactive_paused IS FALSE
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'after old pairing terminates, new device gets safe takeover projection');
SELECT ok((SELECT authorized IS TRUE AND committed IS TRUE
           AND session_id IS NOT NULL AND version = 1
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000852')),
    'new device takes over with fresh session identity and CAS version one');
SELECT ok((SELECT authorized IS TRUE AND state = 'ACTIVE_LISTENING'
           AND version = 1 AND session_id IS NOT NULL
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'new device reads its own transferred active session');
RESET ROLE;
ROLLBACK TO SAVEPOINT takeover_test;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000994', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000994","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND committed IS TRUE AND version = 5
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975',
        (SELECT session_id FROM api.synthetic_conversation_session_read(
            '00000000-0000-4000-8000-000000000975')), 4,
        'IDLE', true, '00000000-0000-4000-8000-000000000849')),
    'patient refusal persists terminal pause on the admission row');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM kof5.safety_audit_event
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'
      AND event_type = 'patient_dissent'), 1,
    'session refusal atomically records shared safety-audit dissent gate');
UPDATE kof5.patient_device_assignment
SET status = 'revoked', revoked_at = now()
WHERE device_user_id = '00000000-0000-4000-8000-000000000994';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000996', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000996","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS TRUE AND state = 'IDLE'
           AND proactive_paused IS TRUE AND session_id IS NULL
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'new iPad sees old iPad refusal after reassignment');
SELECT ok((SELECT authorized IS FALSE AND committed IS FALSE
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'ACTIVE_LISTENING', false,
        '00000000-0000-4000-8000-000000000850')),
    'shared dissent gate stops new iPad from clearing patient refusal');
SELECT ok((SELECT authorized IS FALSE AND committed IS FALSE
    FROM api.synthetic_conversation_session_commit(
        '00000000-0000-4000-8000-000000000975', NULL, 0,
        'IDLE', true, '00000000-0000-4000-8000-000000000851')),
    'shared dissent audit blocks every later commit, even a paused no-op');
RESET ROLE;
DELETE FROM kof5.patient_device_assignment
WHERE device_user_id = '00000000-0000-4000-8000-000000000994';
DELETE FROM auth.users WHERE id = '00000000-0000-4000-8000-000000000994';
SELECT ok((SELECT device_user_id IS NULL AND proactive_paused IS TRUE
    FROM kof5.synthetic_conversation_session
    WHERE patient_id = '00000000-0000-4000-8000-000000000975'),
    'deleting old device Auth user clears owner reference but retains refusal');
UPDATE kof5.hospital_encounter
SET status = 'finished', discharged_at = now()
WHERE encounter_id = '00000000-0000-4000-8000-000000000976';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000996', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000996","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE
    FROM api.synthetic_conversation_session_read(
        '00000000-0000-4000-8000-000000000975')),
    'ended admission closes session routing');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
