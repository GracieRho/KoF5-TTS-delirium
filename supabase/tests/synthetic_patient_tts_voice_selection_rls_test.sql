BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT no_plan();

SELECT ok(NOT has_function_privilege('anon',
    'api.synthetic_patient_tts_voice_ready(uuid)', 'EXECUTE'),
    'signed-out user cannot call TTS voice selection');
SELECT ok(NOT has_function_privilege('authenticated',
    'api.synthetic_patient_tts_voice_ready(uuid)', 'EXECUTE'),
    'guardian and anonymous paired device cannot call TTS voice selection');
SELECT ok(has_function_privilege('service_role',
    'api.synthetic_patient_tts_voice_ready(uuid)', 'EXECUTE'),
    'server role alone can call exposed read-only selector');
SELECT is((SELECT prosecdef FROM pg_proc
    WHERE oid = 'api.synthetic_patient_tts_voice_ready(uuid)'::regprocedure),
    false, 'exposed Data API function is invoker wrapper');

INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000974', false),
    ('00000000-0000-4000-8000-000000000973', false);
INSERT INTO kof5.hospital_registry_activation
    (hospital_ref,status,institution_approval_ref,clinical_safety_approval_ref,approved_at)
VALUES ('TEST-TTS-H','approved','TEST-INSTITUTION','TEST-SAFETY',now()-interval '1 day');
INSERT INTO kof5.hospital_patient
    (patient_id,hospital_ref,ehr_patient_ref,staff_display_name,registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975','TEST-TTS-H','TEST-TTS-P',
        '가상 환자','TEST-STAFF');
INSERT INTO kof5.hospital_encounter
    (encounter_id,patient_id,ehr_encounter_ref,status,admitted_at)
VALUES ('00000000-0000-4000-8000-000000000970',
        '00000000-0000-4000-8000-000000000975','TEST-TTS-E',
        'in_progress',now()-interval '1 day');
INSERT INTO kof5.patient_guardian_link
    (patient_id,guardian_user_id,relationship,access_status,effective_at,
     verified_by_staff_ref,verified_at)
VALUES ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974','가상 가족 1','verified',
        now()-interval '1 day','TEST-VERIFY',now()),
       ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000973','가상 가족 2','verified',
        now()-interval '1 day','TEST-VERIFY',now());
INSERT INTO kof5.consent_record
    (consent_id,patient_id,scope,signer_role,signer_ref,assent_status,
     status,effective_at,recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000941',
        '00000000-0000-4000-8000-000000000975','patient_participation',
        'patient','TEST-PATIENT','assented','active',now()-interval '1 day','TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000942',
        '00000000-0000-4000-8000-000000000975','ambient_processing',
        'patient','TEST-PATIENT','assented','active',now()-interval '1 day','TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000943',
        '00000000-0000-4000-8000-000000000975','patient_voice_feature',
        'patient','TEST-PATIENT','assented','active',now()-interval '1 day','TEST-STAFF');
INSERT INTO kof5.consent_record
    (consent_id,patient_id,guardian_ref,scope,signer_role,signer_ref,
     assent_status,status,effective_at,recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000951',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974','guardian_voice_clone',
        'guardian','00000000-0000-4000-8000-000000000974',
        'not_required','active',now()-interval '1 day','TEST-STAFF'),
       ('00000000-0000-4000-8000-000000000952',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000973','guardian_voice_clone',
        'guardian','00000000-0000-4000-8000-000000000973',
        'not_required','active',now()-interval '1 day','TEST-STAFF');

SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE AND guardian_user_id IS NULL
    AND clone_id IS NULL AND provider IS NULL AND voice_id IS NULL
    FROM api.synthetic_patient_tts_voice_ready(
        '00000000-0000-4000-8000-000000000975')),
    'zero created candidates returns only a null-IDs denial');
SELECT is((SELECT count(*)::integer FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')), 1,
    'zero candidates still returns exactly one row');
RESET ROLE;

INSERT INTO kof5.synthetic_guardian_voice_clone
    (clone_id,patient_id,guardian_user_id,consent_id,provider,provider_name,
     request_key,sample_durations_ms,status,voice_id,
     provider_created_at,verification_confirmed_at)
VALUES ('00000000-0000-4000-8000-000000000981',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974',
        '00000000-0000-4000-8000-000000000951','elevenlabs',
        'KoF5 internal self-voice test 00000000000000000000000000000981',
        '00000000-0000-4000-8000-000000000801',ARRAY[20000,25000,30000],
        'created','test-tts-001',now(),now());
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized AND guardian_user_id =
    '00000000-0000-4000-8000-000000000974'::uuid
    AND clone_id = '00000000-0000-4000-8000-000000000981'::uuid
    AND provider = 'elevenlabs' AND voice_id = 'test-tts-001'
    FROM api.synthetic_patient_tts_voice_ready(
        '00000000-0000-4000-8000-000000000975')),
    'one created clone with all patient and guardian gates returns exact metadata');
SELECT is((SELECT count(*)::integer FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')), 1,
    'one candidate returns exactly one row');
SELECT ok((SELECT authorized IS FALSE AND guardian_user_id IS NULL
    AND clone_id IS NULL AND provider IS NULL AND voice_id IS NULL
    FROM api.synthetic_patient_tts_voice_ready(
        '00000000-0000-4000-8000-000000000976')),
    'real or other patient UUID cannot receive synthetic voice identifiers');
RESET ROLE;

UPDATE kof5.consent_record SET status='expired'
WHERE consent_id='00000000-0000-4000-8000-000000000941';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'patient participation withdrawal immediately denies selection');
RESET ROLE;
UPDATE kof5.consent_record SET status='active'
WHERE consent_id='00000000-0000-4000-8000-000000000941';
UPDATE kof5.consent_record SET status='expired'
WHERE consent_id='00000000-0000-4000-8000-000000000942';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'ambient processing consent withdrawal immediately denies selection');
RESET ROLE;
UPDATE kof5.consent_record SET status='active'
WHERE consent_id='00000000-0000-4000-8000-000000000942';
UPDATE kof5.consent_record SET status='expired'
WHERE consent_id='00000000-0000-4000-8000-000000000943';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'patient voice feature consent withdrawal immediately denies selection');
RESET ROLE;
UPDATE kof5.consent_record SET status='active',assent_status='not_attempted'
WHERE consent_id='00000000-0000-4000-8000-000000000943';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'patient voice feature assent not obtained denies selection');
RESET ROLE;
UPDATE kof5.consent_record SET assent_status='assented'
WHERE consent_id='00000000-0000-4000-8000-000000000943';
UPDATE kof5.hospital_registry_activation
SET status='revoked',revoked_at=now() WHERE hospital_ref='TEST-TTS-H';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'institution approval revocation immediately denies selection');
RESET ROLE;
UPDATE kof5.hospital_registry_activation
SET status='approved',revoked_at=NULL WHERE hospital_ref='TEST-TTS-H';
INSERT INTO kof5.safety_audit_event (patient_id,event_type)
VALUES ('00000000-0000-4000-8000-000000000975','patient_dissent');
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'dissent after current admission immediately denies selection');
RESET ROLE;
DELETE FROM kof5.safety_audit_event WHERE patient_id=
    '00000000-0000-4000-8000-000000000975';
UPDATE kof5.hospital_encounter SET status='finished',discharged_at=now()
WHERE encounter_id='00000000-0000-4000-8000-000000000970';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'finished encounter immediately denies selection');
RESET ROLE;
UPDATE kof5.hospital_encounter SET status='in_progress',discharged_at=NULL
WHERE encounter_id='00000000-0000-4000-8000-000000000970';
UPDATE kof5.patient_guardian_link SET expires_at=now()-interval '1 hour'
WHERE guardian_user_id='00000000-0000-4000-8000-000000000974';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'expired guardian link immediately denies selection');
RESET ROLE;
UPDATE kof5.patient_guardian_link SET expires_at=NULL
WHERE guardian_user_id='00000000-0000-4000-8000-000000000974';
UPDATE kof5.consent_record SET status='expired'
WHERE consent_id='00000000-0000-4000-8000-000000000951';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')),
    'distinct mapped guardian clone consent withdrawal denies selection');
RESET ROLE;
UPDATE kof5.consent_record SET status='active'
WHERE consent_id='00000000-0000-4000-8000-000000000951';

INSERT INTO kof5.synthetic_guardian_voice_clone
    (clone_id,patient_id,guardian_user_id,consent_id,provider,provider_name,
     request_key,sample_durations_ms,status,voice_id,
     provider_created_at,verification_confirmed_at)
VALUES ('00000000-0000-4000-8000-000000000982',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000973',
        '00000000-0000-4000-8000-000000000952','other_provider',
        'KoF5 internal self-voice test 00000000000000000000000000000982',
        '00000000-0000-4000-8000-000000000802',ARRAY[20000,25000,30000],
        'created','test-tts-002',now(),now());
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE AND guardian_user_id IS NULL
    AND clone_id IS NULL AND provider IS NULL AND voice_id IS NULL
    FROM api.synthetic_patient_tts_voice_ready(
        '00000000-0000-4000-8000-000000000975')),
    'two eligible guardian clones are ambiguous and return no identifiers');
SELECT is((SELECT count(*)::integer FROM api.synthetic_patient_tts_voice_ready(
    '00000000-0000-4000-8000-000000000975')), 1,
    'two candidates still return exactly one denial row');
RESET ROLE;
UPDATE kof5.synthetic_guardian_voice_clone
SET status='deletion_pending',deletion_requested_at=now()
WHERE clone_id='00000000-0000-4000-8000-000000000982';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized AND clone_id=
    '00000000-0000-4000-8000-000000000981'::uuid
    FROM api.synthetic_patient_tts_voice_ready(
        '00000000-0000-4000-8000-000000000975')),
    'deletion-pending candidate is excluded without leaking its ID');
RESET ROLE;
UPDATE kof5.synthetic_guardian_voice_clone
SET status='deletion_pending',deletion_requested_at=now()
WHERE clone_id='00000000-0000-4000-8000-000000000981';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT ok((SELECT authorized IS FALSE AND voice_id IS NULL
    FROM api.synthetic_patient_tts_voice_ready(
        '00000000-0000-4000-8000-000000000975')),
    'all deletion-pending clones deny server TTS use');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
