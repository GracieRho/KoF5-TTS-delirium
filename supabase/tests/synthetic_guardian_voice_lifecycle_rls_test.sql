BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;
SELECT no_plan();

-- Fixed synthetic patient975 and mock Auth identities, rolled back below.
INSERT INTO auth.users (id, is_anonymous) VALUES
    ('00000000-0000-4000-8000-000000000974', false), -- verified guardian
    ('00000000-0000-4000-8000-000000000971', false), -- unlinked user
    ('00000000-0000-4000-8000-000000000972', true);  -- misissued anonymous link
INSERT INTO kof5.hospital_patient
    (patient_id, hospital_ref, ehr_patient_ref, staff_display_name, registered_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000975', 'TEST-CLONE-H',
        'TEST-CLONE-P', '가상 환자', 'TEST-STAFF');
INSERT INTO kof5.patient_guardian_link
    (patient_id, guardian_user_id, relationship, access_status,
     effective_at, verified_by_staff_ref, verified_at)
VALUES ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974', '가상 가족', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now()),
       ('00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000972', '가상 잘못 연결된 장치', 'verified',
        now() - interval '1 day', 'TEST-VERIFY', now());
INSERT INTO kof5.consent_record
    (consent_id, patient_id, guardian_ref, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000951',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974', 'guardian_voice_clone',
        'guardian', '00000000-0000-4000-8000-000000000974',
        'not_required', 'active', now() - interval '1 day', 'TEST-STAFF');

SELECT ok((SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
    WHERE oid = 'kof5.synthetic_guardian_voice_clone'::regclass),
    'private clone metadata table force RLS');
SELECT ok(NOT has_table_privilege('authenticated',
    'kof5.synthetic_guardian_voice_clone', 'INSERT'),
    'guardian/device cannot directly insert provider metadata');
SELECT ok(NOT has_table_privilege('service_role',
    'kof5.synthetic_guardian_voice_clone', 'UPDATE'),
    'service_role cannot bypass writer transitions with direct UPDATE grant');
SELECT ok(NOT has_function_privilege('authenticated',
    'api.synthetic_guardian_voice_begin(uuid,uuid,uuid,text,uuid,integer[])',
    'EXECUTE'), 'guardian/device cannot invoke server-only begin');
SELECT ok(NOT has_function_privilege('authenticated',
    'api.synthetic_guardian_voice_confirm_remote_absence(uuid,text,timestamptz)',
    'EXECUTE'), 'guardian/device cannot attest remote deletion');
SELECT ok(NOT has_function_privilege('anon',
    'api.synthetic_guardian_voice_status(uuid)', 'EXECUTE'),
    'signed-out role cannot read clone status');
SELECT ok(NOT (SELECT prosecdef FROM pg_proc WHERE oid =
    'api.synthetic_guardian_voice_begin(uuid,uuid,uuid,text,uuid,integer[])'::regprocedure),
    'exposed server writer is invoker wrapper');
SELECT is((SELECT count(*)::integer FROM information_schema.columns
    WHERE table_schema = 'kof5' AND table_name = 'synthetic_guardian_voice_clone'
      AND column_name IN ('sample_audio', 'audio', 'transcript', 'secret', 'api_key')), 0,
    'clone table stores only bounded duration metadata, no samples or secret');

GRANT service_role, authenticated TO postgres WITH SET TRUE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000971","is_anonymous":false}', true);
SELECT ok((SELECT authorized IS FALSE AND ready IS FALSE
    AND consent_id IS NULL AND clone_id IS NULL
    FROM api.synthetic_guardian_voice_status(
        '00000000-0000-4000-8000-000000000975')),
    'unlinked permanent user cannot see clone status');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000972","is_anonymous":true}', true);
SELECT ok((SELECT authorized IS FALSE AND ready IS FALSE
    AND consent_id IS NULL AND clone_id IS NULL
    FROM api.synthetic_guardian_voice_status(
        '00000000-0000-4000-8000-000000000975')),
    'misissued anonymous guardian link cannot read clone');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000974","is_anonymous":false}', true);
SELECT ok((SELECT authorized AND ready AND consent_id =
    '00000000-0000-4000-8000-000000000951'::uuid
    AND status = 'none' AND clone_id IS NULL
    FROM api.synthetic_guardian_voice_status(
        '00000000-0000-4000-8000-000000000975')),
    'verified permanent guardian starts with no clone');
RESET ROLE;

SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_tts_ready(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974')),
    'no clone ID is supplied for TTS before provider creation');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_begin(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974',
    '00000000-0000-4000-8000-000000000951', 'elevenlabs',
    '00000000-0000-4000-8000-000000000801', ARRAY[19999,25000,30000])) ,
    'begin rejects any sample shorter than 20 seconds');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_begin(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974',
    '00000000-0000-4000-8000-000000000951', 'elevenlabs',
    '00000000-0000-4000-8000-000000000801', ARRAY[20000,25000,30001])) ,
    'begin rejects any sample longer than 30 seconds');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_begin(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000971',
    '00000000-0000-4000-8000-000000000951', 'elevenlabs',
    '00000000-0000-4000-8000-000000000801', ARRAY[20000,25000,30000])) ,
    'server writer cannot clone for unlinked Auth user');
SELECT ok((SELECT authorized AND status = 'pending' AND newly_created
    AND clone_id IS NOT NULL
    AND provider_name ~ '^KoF5 internal self-voice test [0-9a-f]{32}$'
    FROM api.synthetic_guardian_voice_begin(
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974',
        '00000000-0000-4000-8000-000000000951', 'elevenlabs',
        '00000000-0000-4000-8000-000000000801', ARRAY[20000,25000,30000])) ,
    'valid own-voice intent is pending before provider POST');
RESET ROLE;
SELECT set_config('test.clone_one', (SELECT clone_id::text
    FROM kof5.synthetic_guardian_voice_clone
    WHERE request_key = '00000000-0000-4000-8000-000000000801'), true);
SELECT is((SELECT count(*)::integer FROM kof5.synthetic_guardian_voice_clone), 1,
    'one metadata row exists without provider voice ID');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000974","is_anonymous":false}', true);
SELECT ok((SELECT authorized AND ready IS FALSE AND status = 'pending'
    AND consent_id = '00000000-0000-4000-8000-000000000951'::uuid
    FROM api.synthetic_guardian_voice_status(
        '00000000-0000-4000-8000-000000000975')),
    'guardian sees consent ID but cannot start another open clone');
RESET ROLE;
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized AND newly_created IS FALSE
    AND clone_id = current_setting('test.clone_one')::uuid
    FROM api.synthetic_guardian_voice_begin(
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974',
        '00000000-0000-4000-8000-000000000951', 'elevenlabs',
        '00000000-0000-4000-8000-000000000801', ARRAY[20000,25000,30000])) ,
    'same request key is idempotent, not a second provider create');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_begin(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974',
    '00000000-0000-4000-8000-000000000951', 'elevenlabs',
    '00000000-0000-4000-8000-000000000802', ARRAY[20000,25000,30000])) ,
    'another open clone cannot be started during uncertain pending create');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_tts_ready(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974')),
    'pending clone cannot reach TTS');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_provider_result(
    current_setting('test.clone_one')::uuid, 'bad voice ID', NULL)),
    'malformed provider ID is rejected');
SELECT ok((SELECT authorized AND status = 'verification_pending'
    FROM api.synthetic_guardian_voice_provider_result(
        current_setting('test.clone_one')::uuid, 'test-voice-001', NULL)),
    'reconciled provider ID with unknown verification stays pending');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_tts_ready(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974')),
    'verification-pending voice cannot be used');
SELECT ok((SELECT authorized AND status = 'created'
    FROM api.synthetic_guardian_voice_provider_result(
        current_setting('test.clone_one')::uuid, 'test-voice-001', true)),
    'explicit provider verification makes the clone created');
SELECT ok((SELECT authorized AND voice_id = 'test-voice-001'
    FROM api.synthetic_guardian_voice_tts_ready(
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974')),
    'TTS-use returns only verified, current synthetic clone ID');
RESET ROLE;

UPDATE kof5.patient_guardian_link SET expires_at = now() - interval '1 hour'
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000974';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_tts_ready(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974')),
    'link expiry immediately hides provider voice ID');
RESET ROLE;
UPDATE kof5.patient_guardian_link SET expires_at = NULL
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000974';
UPDATE kof5.consent_record SET status = 'withdrawn', withdrawn_at = now()
WHERE consent_id = '00000000-0000-4000-8000-000000000951';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_tts_ready(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974')),
    'clone consent withdrawal immediately hides provider voice ID');
SELECT ok((SELECT authorized AND status = 'deletion_pending'
    FROM api.synthetic_guardian_voice_provider_result(
        current_setting('test.clone_one')::uuid, 'test-voice-001', true)),
    'late provider result after withdrawal redirects to deletion, not TTS');
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000974","is_anonymous":false}', true);
SELECT ok((SELECT authorized AND ready IS FALSE AND consent_id IS NULL
    AND status = 'deletion_pending'
    FROM api.synthetic_guardian_voice_status(
        '00000000-0000-4000-8000-000000000975')),
    'withdrawn consent is hidden while guardian can see deletion cleanup state');
RESET ROLE;
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized AND status = 'deletion_pending'
    FROM api.synthetic_guardian_voice_request_deletion(
        current_setting('test.clone_one')::uuid)),
    'deletion request is idempotent after withdrawal');
SELECT ok((SELECT authorized IS FALSE FROM
    api.synthetic_guardian_voice_confirm_remote_absence(
        current_setting('test.clone_one')::uuid, 'provider_name_not_found', now())),
    'wrong absence method cannot mark a known voice ID deleted');
SELECT ok((SELECT authorized IS FALSE FROM
    api.synthetic_guardian_voice_confirm_remote_absence(
        current_setting('test.clone_one')::uuid, 'voice_id_not_found',
        now() - interval '1 hour')),
    'remote absence observation before deletion request is rejected');
SELECT ok((SELECT authorized AND status = 'deleted'
    FROM api.synthetic_guardian_voice_confirm_remote_absence(
        current_setting('test.clone_one')::uuid, 'voice_id_not_found', now())),
    'separate provider ID-absence attestation makes deletion tombstone');
SELECT ok((SELECT authorized AND status = 'deleted'
    FROM api.synthetic_guardian_voice_confirm_remote_absence(
        current_setting('test.clone_one')::uuid, 'voice_id_not_found', now())),
    'remote absence retry returns same deleted tombstone');
RESET ROLE;
SELECT throws_ok($sql$UPDATE kof5.synthetic_guardian_voice_clone
    SET status = 'created', remote_absence_verified_at = NULL
    WHERE clone_id = current_setting('test.clone_one')::uuid$sql$,
    '23514', NULL, 'deleted clone cannot be reactivated');

-- A new consent may start a new synthetic clone; the withdrawn old one stays terminal.
INSERT INTO kof5.consent_record
    (consent_id, patient_id, guardian_ref, scope, signer_role, signer_ref,
     assent_status, status, effective_at, recorded_by_staff_ref)
VALUES ('00000000-0000-4000-8000-000000000952',
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974', 'guardian_voice_clone',
        'guardian', '00000000-0000-4000-8000-000000000974',
        'not_required', 'active', now() - interval '1 day', 'TEST-STAFF');
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized AND status = 'pending'
    FROM api.synthetic_guardian_voice_begin(
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974',
        '00000000-0000-4000-8000-000000000952', 'elevenlabs',
        '00000000-0000-4000-8000-000000000802', ARRAY[20000,25000,30000])) ,
    'new consent allows a fresh pending intent, not reopening old tombstone');
RESET ROLE;
SELECT set_config('test.clone_two', (SELECT clone_id::text
    FROM kof5.synthetic_guardian_voice_clone
    WHERE request_key = '00000000-0000-4000-8000-000000000802'), true);
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized AND status = 'deletion_pending' AND voice_id IS NULL
    FROM api.synthetic_guardian_voice_request_deletion(
        current_setting('test.clone_two')::uuid)),
    'uncertain pending create can request deletion before ID reconciliation');
SELECT ok((SELECT authorized IS FALSE FROM
    api.synthetic_guardian_voice_confirm_remote_absence(
        current_setting('test.clone_two')::uuid, 'voice_id_not_found', now())),
    'ID-absence method is invalid when pending create had no voice ID');
SELECT ok((SELECT authorized AND status = 'deleted'
    FROM api.synthetic_guardian_voice_confirm_remote_absence(
        current_setting('test.clone_two')::uuid, 'provider_name_not_found', now())),
    'separate exact provider-name search absence resolves uncertain create');
SELECT ok((SELECT authorized AND status = 'pending'
    FROM api.synthetic_guardian_voice_begin(
        '00000000-0000-4000-8000-000000000975',
        '00000000-0000-4000-8000-000000000974',
        '00000000-0000-4000-8000-000000000952', 'elevenlabs',
        '00000000-0000-4000-8000-000000000803', ARRAY[20000,25000,30000])) ,
    'third independent request starts after confirmed remote absence');
RESET ROLE;
SELECT set_config('test.clone_three', (SELECT clone_id::text
    FROM kof5.synthetic_guardian_voice_clone
    WHERE request_key = '00000000-0000-4000-8000-000000000803'), true);
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok((SELECT authorized AND status = 'failed'
    FROM api.synthetic_guardian_voice_confirm_failure(
        current_setting('test.clone_three')::uuid)),
    'only explicit provider rejection before any ID marks failed');
SELECT ok((SELECT authorized IS FALSE FROM api.synthetic_guardian_voice_tts_ready(
    '00000000-0000-4000-8000-000000000975',
    '00000000-0000-4000-8000-000000000974')),
    'failed and deleted clones never reach TTS');
RESET ROLE;
UPDATE kof5.patient_guardian_link SET access_status = 'revoked', revoked_at = now()
WHERE guardian_user_id = '00000000-0000-4000-8000-000000000974';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000974","is_anonymous":false}', true);
SELECT ok((SELECT authorized IS FALSE AND clone_id IS NULL
    FROM api.synthetic_guardian_voice_status(
        '00000000-0000-4000-8000-000000000975')),
    'revoked guardian link hides even historical clone metadata');

SELECT * FROM finish();
ROLLBACK;
